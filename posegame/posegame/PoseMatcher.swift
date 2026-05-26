import Foundation

class PoseMatcher {
    /// 指尖 → 对应 MCP 关节，用于计算手指弯曲度
    private static let fingerTipToMCP: [String: String] = [
        "thumbTip": "thumbMP",
        "indexTip": "indexMCP",
        "middleTip": "middleMCP",
        "ringTip": "ringMCP",
        "littleTip": "littleMCP",
    ]

    // 身体
    var templates: [PoseTemplate] = []
    // 手部
    var handTemplates: [PoseTemplate] = []
    // 面部
    var faceTemplates: [PoseTemplate] = []

    var combinationRules: [CombinationRule] = []
    var sequenceRules: [SequenceRule] = []
    var activeActionKeys: [String] = []

    private var lastActions: Set<String> = []
    var sequenceProgress: [UUID: (step: Int, lastTime: Date)] = [:]

    // MARK: - 时序平滑

    /// 手部动作的连续匹配帧计数器（actionKey -> 连续匹配帧数）
    private var handMatchCounts: [String: Int] = [:]
    /// 手部动作的连续未匹配帧计数器（actionKey -> 连续未匹配帧数）
    private var handMissCounts: [String: Int] = [:]
    /// 面部动作的连续匹配帧计数器
    private var faceMatchCounts: [String: Int] = [:]
    /// 面部动作的连续未匹配帧计数器
    private var faceMissCounts: [String: Int] = [:]
    /// 身体动作的连续匹配帧计数器
    private var bodyMatchCounts: [String: Int] = [:]
    /// 身体动作的连续未匹配帧计数器
    private var bodyMissCounts: [String: Int] = [:]
    /// 触发所需的最小连续匹配帧数
    private let smoothOnFrames = 1
    /// 取消触发所需的连续未匹配帧数
    private let smoothOffFrames = 1

    // MARK: - 身体匹配（带时序平滑）

    func match(landmarks: [Landmark]) -> [String] {
        var rawMatched: [String] = []
        for template in templates {
            let score = matchTemplate(template, landmarks: landmarks)
            if score > template.threshold {
                rawMatched.append(template.actionKey)
            }
        }
        return smoothActions(rawMatched, matchCounts: &bodyMatchCounts,
                             missCounts: &bodyMissCounts,
                             allKeys: templates.map(\.actionKey))
    }

    /// 通用匹配：把 [String: (x, y, c)] 字典和 PoseTemplate 比较
    /// 同时使用角度和距离进行综合打分，解决"握拳 vs 出布"等角度相似但距离不同的手势
    private func matchPointsDict(template: PoseTemplate,
                                  points: [String: (x: Double, y: Double, c: Double)]) -> Double {
        guard !template.joints.isEmpty else { return 0 }

        // 优先用 wrist 做参照（手部录制时以 wrist 为基准）
        guard let refVal: (x: Double, y: Double, c: Double) = {
            if let w = points["wrist"], w.c > 0.3 { return w }
            return points.first(where: { $0.value.c > 0.3 })?.value
        }() else { return 0 }

        var scores: [Double] = []

        for (jointName, pos) in template.joints {
            guard let pt = points[jointName],
                  pt.c > 0.3
            else { continue }

            let relX = pt.x - refVal.x
            let relY = pt.y - refVal.y
            let currentAngle = atan2(relY, relX)
            let currentMag = sqrt(relX * relX + relY * relY)

            // 角度得分（权重 70%）
            var angleDiff = abs(currentAngle - pos[0])
            if angleDiff > .pi { angleDiff = 2 * .pi - angleDiff }
            let angleScore = max(0, 1 - angleDiff / (.pi / 3))

            // 距离得分（权重 20%）：使用相对差异而非归一化
            var distScore: Double = 1.0
            if pos.count > 1 {
                let templateMag = pos[1]
                let maxMag = max(currentMag, templateMag, 0.01)
                let relativeDiff = abs(currentMag - templateMag) / maxMag
                distScore = max(0, 1 - relativeDiff)
            }

            // 弯曲度得分（权重 30%）：仅手部模板有第三维
            var curlScore: Double = 1.0
            if pos.count > 2,
               let mcpName = Self.fingerTipToMCP[jointName],
               let mcpPt = points[mcpName], mcpPt.c > 0.3,
               let palmRef = points["middleMCP"], palmRef.c > 0.3 {
                let tipToMcp = sqrt(pow(pt.x - mcpPt.x, 2) + pow(pt.y - mcpPt.y, 2))
                let palmSize = sqrt(pow(refVal.x - palmRef.x, 2) + pow(refVal.y - palmRef.y, 2))
                let currentCurl = palmSize > 0.001 ? tipToMcp / palmSize : 0
                let templateCurl = pos[2]
                let curlDiff = abs(currentCurl - templateCurl)
                curlScore = max(0, 1 - curlDiff / 0.5)
                let combinedScore = angleScore * 0.5 + distScore * 0.2 + curlScore * 0.3
                scores.append(combinedScore)
                continue
            }

            // 综合得分（无弯曲度数据时用原权重）
            let combinedScore = angleScore * 0.7 + distScore * 0.3
            scores.append(combinedScore)
        }

        guard !scores.isEmpty else { return 0 }
        scores.sort(by: >)
        let topCount = max(1, scores.count * 60 / 100)
        let topScores = scores[..<topCount]
        return topScores.reduce(0, +) / Double(topCount)
    }

    // MARK: - 手部匹配（带左右手区分 + 时序平滑）

    func matchHands(handLandmarks: [HandLandmark]) -> [String] {
        guard !handTemplates.isEmpty else { return [] }
        var rawMatched: [String] = []

        for (handIndex, hand) in handLandmarks.enumerated() {
            let dict = Dictionary(uniqueKeysWithValues:
                hand.joints.map { ($0.n, (x: $0.x, y: $0.y, c: $0.c)) })
            guard !dict.isEmpty else { continue }

            let chirality = hand.chirality.rawValue // "left" 或 "right"

            for template in handTemplates {
                // 左右手区分：模板名称格式为 "name[left]" 或 "name[right]"
                // 如果模板指定了手的方向，只和同侧匹配
                if template.name.hasSuffix("[left]") && chirality != "left" { continue }
                if template.name.hasSuffix("[right]") && chirality != "right" { continue }
                
                // 旧模板兼容：没有 [left]/[right] 后缀的模板，只匹配第一只检测到的手
                // 避免左右手同时触发同一个动作
                if !template.name.hasSuffix("[left]") && !template.name.hasSuffix("[right]") {
                    // 只匹配检测到的第一只手（通过索引判断）
                    if handIndex > 0 { continue }
                }

                let score = matchPointsDict(template: template, points: dict)
                if score > template.threshold {
                    rawMatched.append(template.actionKey)
                }
            }
        }
        return smoothActions(rawMatched, matchCounts: &handMatchCounts,
                             missCounts: &handMissCounts,
                             allKeys: handTemplates.map(\.actionKey))
    }

    func recordHandTemplate(name: String, actionKey: String,
                            handLandmarks: [HandLandmark]) -> PoseTemplate? {
        guard let hand = handLandmarks.first(where: { !$0.joints.isEmpty }) else { return nil }
        let ref = hand.joints.first(where: { $0.n == "wrist" && $0.c > 0.3 })
                  ?? hand.joints.first(where: { $0.c > 0.5 })
        guard let ref = ref else { return nil }

        // 手掌尺寸参照（wrist → middleMCP），用于归一化弯曲度
        let palmRef = hand.joints.first(where: { $0.n == "middleMCP" && $0.c > 0.3 })
        let palmSize = palmRef.map { sqrt(pow(ref.x - $0.x, 2) + pow(ref.y - $0.y, 2)) } ?? 1.0

        var joints: [String: [Double]] = [:]
        for jp in hand.joints where jp.c > 0.3 {
            let relX = jp.x - ref.x
            let relY = jp.y - ref.y
            var values: [Double] = [atan2(relY, relX), sqrt(relX * relX + relY * relY)]
            // 指尖关节点：附加弯曲度（tip→MCP 距离 / 手掌尺寸）
            if let mcpName = Self.fingerTipToMCP[jp.n],
               let mcpJp = hand.joints.first(where: { $0.n == mcpName && $0.c > 0.3 }) {
                let tipToMcp = sqrt(pow(jp.x - mcpJp.x, 2) + pow(jp.y - mcpJp.y, 2))
                values.append(palmSize > 0.001 ? tipToMcp / palmSize : 0)
            }
            joints[jp.n] = values
        }
        guard joints.count >= 2 else { return nil }

        let chirality = hand.chirality.rawValue
        return PoseTemplate(id: UUID(),
                            name: "\(name)[\(chirality)]",
                            actionKey: actionKey,
                            joints: joints,
                            threshold: 0.4)
    }

    // MARK: - 面部匹配（带时序平滑）

    func matchFace(faceLandmarks: [FaceLandmark]) -> [String] {
        guard !faceTemplates.isEmpty else { return [] }
        let dict = Dictionary(uniqueKeysWithValues:
            faceLandmarks.map { ($0.n.rawValue, (x: $0.x, y: $0.y, c: $0.c)) })
        guard !dict.isEmpty else { return [] }

        var rawMatched: [String] = []
        for template in faceTemplates {
            let score = matchPointsDict(template: template, points: dict)
            if score > template.threshold {
                rawMatched.append(template.actionKey)
            }
        }
        return smoothActions(rawMatched, matchCounts: &faceMatchCounts,
                             missCounts: &faceMissCounts,
                             allKeys: faceTemplates.map(\.actionKey))
    }

    func recordHandDifferentialTemplate(
        name: String, actionKey: String,
        actionHand: HandLandmark,
        baseHand: HandLandmark,
        diffThreshold: Double = 0.05
    ) -> PoseTemplate? {
        let actionRef = actionHand.joints.first(where: { $0.n == "wrist" && $0.c > 0.3 })
                        ?? actionHand.joints.first(where: { $0.c > 0.5 })
        let baseRef = baseHand.joints.first(where: { $0.n == "wrist" && $0.c > 0.3 })
                      ?? baseHand.joints.first(where: { $0.c > 0.5 })
        guard let aRef = actionRef, let bRef = baseRef
        else { return recordHandTemplate(name: name, actionKey: actionKey, handLandmarks: [actionHand]) }

        let actionPalmRef = actionHand.joints.first(where: { $0.n == "middleMCP" && $0.c > 0.3 })
        let actionPalmSize = actionPalmRef.map { sqrt(pow(aRef.x - $0.x, 2) + pow(aRef.y - $0.y, 2)) } ?? 1.0

        var joints: [String: [Double]] = [:]
        var baseJoints: [String: [Double]] = [:]
        for jp in actionHand.joints where jp.c > 0.3 {
            let aRelX = jp.x - aRef.x
            let aRelY = jp.y - aRef.y
            let aAngle = atan2(aRelY, aRelX)
            let aMag = sqrt(aRelX * aRelX + aRelY * aRelY)

            if let baseJp = baseHand.joints.first(where: { $0.n == jp.n && $0.c > 0.3 }) {
                let bRelX = baseJp.x - bRef.x
                let bRelY = baseJp.y - bRef.y
                let bAngle = atan2(bRelY, bRelX)
                baseJoints[jp.n] = [bAngle, sqrt(bRelX * bRelX + bRelY * bRelY)]
                var angleDiff = abs(aAngle - bAngle)
                if angleDiff > .pi { angleDiff = 2 * .pi - angleDiff }
                if angleDiff < diffThreshold { continue }
            }
            var values: [Double] = [aAngle, aMag]
            if let mcpName = Self.fingerTipToMCP[jp.n],
               let mcpJp = actionHand.joints.first(where: { $0.n == mcpName && $0.c > 0.3 }) {
                let tipToMcp = sqrt(pow(jp.x - mcpJp.x, 2) + pow(jp.y - mcpJp.y, 2))
                values.append(actionPalmSize > 0.001 ? tipToMcp / actionPalmSize : 0)
            }
            joints[jp.n] = values
        }
        guard joints.count >= 2 else { return nil }
        return PoseTemplate(id: UUID(),
                            name: "\(name)[\(actionHand.chirality.rawValue)]",
                            actionKey: actionKey, joints: joints,
                            baseJoints: baseJoints.isEmpty ? nil : baseJoints,
                            threshold: 0.4)
    }

    func recordFaceTemplate(name: String, actionKey: String,
                            faceLandmarks: [FaceLandmark]) -> PoseTemplate? {
        guard let ref = faceLandmarks.first(where: { $0.c > 0.5 })
        else { return nil }

        var joints: [String: [Double]] = [:]
        for f in faceLandmarks where f.c > 0.5 {
            let relX = f.x - ref.x
            let relY = f.y - ref.y
            let angle = atan2(relY, relX)
            let magnitude = sqrt(relX * relX + relY * relY)
            joints[f.n.rawValue] = [angle, magnitude]
        }
        guard !joints.isEmpty else { return nil }
        return PoseTemplate(id: UUID(), name: name, actionKey: actionKey,
                            joints: joints, threshold: 0.5)
    }

    // MARK: - 组合规则

    private func matchTemplate(_ template: PoseTemplate, landmarks: [Landmark]) -> Double {
        let ref = landmarks.first(where: { $0.joint == .root && $0.confidence > 0.5 })
            ?? landmarks.first(where: { $0.joint == .neck && $0.confidence > 0.5 })
            ?? landmarks.max(by: { $0.confidence < $1.confidence })

        guard let ref = ref else { return 0 }

        var scores: [Double] = []

        for (jointName, pos) in template.joints {
            guard let lm = landmarks.first(where: { $0.joint.rawValue == jointName }),
                  lm.confidence > 0.5
            else { continue }

            let relX = lm.x - ref.x
            let relY = lm.y - ref.y
            // pos[0] = 录制时的向量角度（弧度）
            let currentAngle = atan2(relY, relX)
            var angleDiff = abs(currentAngle - pos[0])
            if angleDiff > .pi { angleDiff = 2 * .pi - angleDiff }
            let score = max(0, 1 - angleDiff / (.pi / 3))
            scores.append(score)
        }

        guard !scores.isEmpty else { return 0 }
        scores.sort(by: >)
        let topCount = max(1, scores.count * 60 / 100)
        let topScores = scores[..<topCount]
        return topScores.reduce(0, +) / Double(topCount)
    }

    func recordTemplate(name: String, actionKey: String, landmarks: [Landmark]) -> PoseTemplate {
        let ref = landmarks.first(where: { $0.joint == .root && $0.confidence > 0.5 })
            ?? landmarks.first(where: { $0.joint == .neck && $0.confidence > 0.5 })
            ?? landmarks.max(by: { $0.confidence < $1.confidence })

        guard let ref = ref else { return PoseTemplate(id: UUID(), name: name, actionKey: actionKey, joints: [:], threshold: 0.75) }

        var joints: [String: [Double]] = [:]
        for lm in landmarks where lm.confidence > 0.5 {
            let relX = lm.x - ref.x
            let relY = lm.y - ref.y
            let angle = atan2(relY, relX)
            let magnitude = sqrt(relX * relX + relY * relY)
            joints[lm.joint.rawValue] = [angle, magnitude]
        }
        return PoseTemplate(id: UUID(), name: name, actionKey: actionKey, joints: joints, threshold: 0.45)
    }

    /// 差分录制（角度版）：先基准（放松），再动作。
    func recordDifferentialTemplate(
        name: String,
        actionKey: String,
        landmarks: [Landmark],
        baseLandmarks: [Landmark],
        diffThreshold: Double = 0.1
    ) -> PoseTemplate {
        func refJoint(from landmarks: [Landmark]) -> Landmark? {
            landmarks.first(where: { $0.joint == .root && $0.confidence > 0.5 })
                ?? landmarks.first(where: { $0.joint == .neck && $0.confidence > 0.5 })
                ?? landmarks.max(by: { $0.confidence < $1.confidence })
        }

        guard let actionRef = refJoint(from: landmarks),
              let baseRef = refJoint(from: baseLandmarks)
        else { return PoseTemplate(id: UUID(), name: name, actionKey: actionKey, joints: [:], threshold: 0.45) }

        var joints: [String: [Double]] = [:]
        for lm in landmarks where lm.confidence > 0.5 {
            let actionRelX = lm.x - actionRef.x
            let actionRelY = lm.y - actionRef.y
            let actionAngle = atan2(actionRelY, actionRelX)
            let actionMagnitude = sqrt(actionRelX * actionRelX + actionRelY * actionRelY)

            if let baseLm = baseLandmarks.first(where: { $0.joint == lm.joint && $0.confidence > 0.5 }) {
                let baseRelX = baseLm.x - baseRef.x
                let baseRelY = baseLm.y - baseRef.y
                let baseAngle = atan2(baseRelY, baseRelX)
                var angleDiff = abs(actionAngle - baseAngle)
                if angleDiff > .pi { angleDiff = 2 * .pi - angleDiff }
                if angleDiff < diffThreshold { continue }
            }
            joints[lm.joint.rawValue] = [actionAngle, actionMagnitude]
        }
        return PoseTemplate(id: UUID(), name: name, actionKey: actionKey, joints: joints, threshold: 0.45)
    }

    // MARK: - 时序平滑

    /// 对匹配结果进行帧间平滑，避免动作闪烁
    /// - 需要连续 smoothOnFrames 帧匹配才触发
    /// - 需要连续 smoothOffFrames 帧不匹配才取消
    private func smoothActions(_ rawMatched: [String],
                                matchCounts: inout [String: Int],
                                missCounts: inout [String: Int],
                                allKeys: [String]) -> [String] {
        let rawSet = Set(rawMatched)
        var result: [String] = []

        for key in allKeys {
            if rawSet.contains(key) {
                // 本帧匹配到了
                matchCounts[key, default: 0] += 1
                missCounts[key, default: 0] = 0
                if matchCounts[key]! >= smoothOnFrames {
                    result.append(key)
                }
            } else {
                // 本帧没匹配到
                missCounts[key, default: 0] += 1
                matchCounts[key, default: 0] = 0
                // 不立即取消，等连续 missOffFrames 帧后才真正取消
                if missCounts[key]! < smoothOffFrames {
                    result.append(key) // 保持之前的触发状态
                }
            }
        }
        return result
    }
}
