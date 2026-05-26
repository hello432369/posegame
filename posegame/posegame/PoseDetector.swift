import Vision
import CoreVideo

struct DetectionResult {
    let body: [Landmark]
    let hands: [HandLandmark]
    let face: [FaceLandmark]
    let faceBoundingBox: CGRect
    let debug: String
}

class PoseDetector {
    enum Phase { case all, bodyOnly, bodyAndHands, bodyAndFace }

    private let bodyRequest = VNDetectHumanBodyPoseRequest()
    private let handRequest = VNDetectHumanHandPoseRequest()
    private let faceRequest = VNDetectFaceLandmarksRequest()

    // 身体关节点名 -> BodyJoint 映射
    /// Apple Vision 的关节命名与 BodyJoint enum 的映射
    private static let bodyJointMap: [String: BodyJoint] = [
        "nose": .nose, "head": .nose,
        "left_eye": .leftEye, "right_eye": .rightEye,
        "left_ear": .leftEar, "right_ear": .rightEar,
        "neck": .neck,
        "root": .root, "center_hip": .root,
        "left_shoulder": .leftShoulder, "right_shoulder": .rightShoulder,
        "left_forearm": .leftElbow, "right_forearm": .rightElbow,
        "left_hand": .leftWrist, "right_hand": .rightWrist,
        "left_upLeg": .leftHip, "right_upLeg": .rightHip,
        "left_leg": .leftKnee, "right_leg": .rightKnee,
        "left_foot": .leftAnkle, "right_foot": .rightAnkle,
        "left_toes": .leftAnkle, "right_toes": .rightAnkle,
    ]

    init() {
        handRequest.maximumHandCount = 2
    }

    func detect(pixelBuffer: CVPixelBuffer, phase: Phase = .all) -> DetectionResult {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        switch phase {
        case .all:
            try? handler.perform([bodyRequest, handRequest, faceRequest])
        case .bodyOnly:
            try? handler.perform([bodyRequest])
        case .bodyAndHands:
            try? handler.perform([bodyRequest, handRequest])
        case .bodyAndFace:
            try? handler.perform([bodyRequest, faceRequest])
        }

        let body = detectBody()
        let hands = detectHands()
        let (face, faceBbox) = detectFace()
        let dbg = debugLabel(body: body, hands: hands, face: face)
        return DetectionResult(body: body, hands: hands, face: face, faceBoundingBox: faceBbox, debug: dbg)
    }

    // MARK: - 身体

    private func detectBody() -> [Landmark] {
        guard let observation = bodyRequest.results?.first,
              let allPoints = try? observation.recognizedPoints(.all)
        else { return [] }

        var landmarks: [Landmark] = []
        for (key, point) in allPoints {
            guard point.confidence > 0.3 else { continue }
            // key.rawValue 类似 "VNHumanBodyPoseObservedPoint_nose"
            let raw = "\(key)"
            let name = extractJointName(from: raw)
            guard let joint = Self.bodyJointMap[name] else { continue }
            landmarks.append(Landmark(
                joint: joint,
                x: Double(point.x),
                y: Double(point.y),
                confidence: Double(point.confidence)
            ))
        }
        return landmarks
    }

    private func extractJointName(from raw: String) -> String {
        // 格式: VNHumanBodyPoseObservation.JointName(_rawValue: nose)
        guard let r1 = raw.range(of: "_rawValue: ") else { return raw }
        let after = raw[r1.upperBound...]
        let name: String
        if let end = after.firstIndex(of: ")") {
            name = String(after[..<end])
        } else {
            name = String(after)
        }
        return name
            .replacingOccurrences(of: "_1_joint", with: "")
            .replacingOccurrences(of: "_joint", with: "")
    }

    // MARK: - 手部

    private func detectHands() -> [HandLandmark] {
        guard let observations = handRequest.results else { return [] }

        return observations.compactMap { obs -> HandLandmark? in
            guard let allPoints = try? obs.recognizedPoints(.all) else { return nil }
            let chirality: HandChirality = obs.chirality == .left ? .left : .right

            var points: [HandJointPoint] = []
            for (key, point) in allPoints {
                guard point.confidence > 0.3 else { continue }
                let raw = "\(key)"
                let name = extractJointName(from: raw)
                points.append(HandJointPoint(
                    n: handJointNameFromMediaPipe(name),
                    x: Double(point.x),
                    y: Double(point.y),
                    c: Double(point.confidence)
                ))
            }
            guard !points.isEmpty else { return nil }
            return HandLandmark(chirality: chirality, joints: points)
        }
    }

    /// 把 Apple Vision 的手部关节命名统一成 MediaPipe 风格（与我们的 HandJoint 枚举一致）
    private func handJointNameFromMediaPipe(_ visionName: String) -> String {
        switch visionName {
        case "wrist": return "wrist"
        case "thumb_cmc": return "thumbCMC"
        case "thumb_mp": return "thumbMP"
        case "thumb_ip": return "thumbIP"
        case "thumb_tip": return "thumbTip"
        case "index_finger_mcp": return "indexMCP"
        case "index_finger_pip": return "indexPIP"
        case "index_finger_dip": return "indexDIP"
        case "index_finger_tip": return "indexTip"
        case "middle_finger_mcp": return "middleMCP"
        case "middle_finger_pip": return "middlePIP"
        case "middle_finger_dip": return "middleDIP"
        case "middle_finger_tip": return "middleTip"
        case "ring_finger_mcp": return "ringMCP"
        case "ring_finger_pip": return "ringPIP"
        case "ring_finger_dip": return "ringDIP"
        case "ring_finger_tip": return "ringTip"
        case "little_finger_mcp": return "littleMCP"
        case "little_finger_pip": return "littlePIP"
        case "little_finger_dip": return "littleDIP"
        case "little_finger_tip": return "littleTip"
        default: return visionName
        }
    }

    // MARK: - 面部

    private func detectFace() -> ([FaceLandmark], CGRect) {
        guard let observation = faceRequest.results?.first,
              let landmarks = observation.landmarks
        else { return ([], .zero) }

        let bbox = observation.boundingBox

        var results: [FaceLandmark] = []

        let faceConf = observation.confidence
        func addRegion(key: FaceLandmarkKey, region: VNFaceLandmarkRegion2D?, at index: Int = 0) {
            guard let region = region, index < region.pointCount else { return }
            let pt = region.normalizedPoints[index]
            let fx = Double(bbox.minX) + Double(pt.x) * Double(bbox.width)
            let fy = Double(bbox.minY) + Double(pt.y) * Double(bbox.height)
            results.append(FaceLandmark(n: key, x: fx, y: fy, c: Double(faceConf)))
        }

        addRegion(key: .leftEye, region: landmarks.leftEye, at: 0)
        addRegion(key: .rightEye, region: landmarks.rightEye, at: 0)
        addRegion(key: .noseTip, region: landmarks.nose, at: 0)

        if let outerLips = landmarks.outerLips, outerLips.pointCount > 0 {
            addRegion(key: .mouthLeft, region: outerLips, at: 0)
            if outerLips.pointCount > 2 {
                addRegion(key: .mouthRight, region: outerLips, at: 2)
            }
        }

        addRegion(key: .leftEyebrow, region: landmarks.leftEyebrow, at: 0)
        addRegion(key: .rightEyebrow, region: landmarks.rightEyebrow, at: 0)

        return (results, bbox)
    }

    // MARK: - 调试

    private func debugLabel(body: [Landmark], hands: [HandLandmark], face: [FaceLandmark]) -> String {
        var parts: [String] = []
        parts.append(body.count > 0 ? "🟢\(body.count)" : "无")
        for hand in hands {
            parts.append("\(hand.chirality == .left ? "👈" : "👉")\(hand.joints.count)")
        }
        if !face.isEmpty {
            parts.append("😊\(face.count)")
        }
        return parts.joined(separator: " ")
    }
}
