import AVFoundation
import CoreGraphics

class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let detector = PoseDetector()
    let matcher = PoseMatcher()
    let sender = UDPSender()

    @Published var landmarks: [Landmark] = []
    @Published var handLandmarks: [HandLandmark] = []
    @Published var faceLandmarks: [FaceLandmark] = []
    @Published var videoSize: CGSize = .zero
    // 手部/面部模板 & 动作
    @Published var handTemplates: [PoseTemplate] = []
    @Published var faceTemplates: [PoseTemplate] = []
    @Published var activeActions: [String] = []
    @Published var udpConnected = false
    @Published var statusMessage = "启动相机..."
    @Published var cameraPosition: AVCaptureDevice.Position = .front
    @Published var autoHoldThreshold: Double = 0.3
    @Published var enableBody = true
    @Published var enableHands = true
    @Published var enableFace = true
    @Published var faceBoundingBox: CGRect = .zero
    private var configFrameCount = 0

    // MARK: - 多帧平均采样缓冲区

    /// 手部多帧缓冲（用于录制时取平均，减少单帧抖动）
    private var handFrameBuffer: [[HandLandmark]] = []
    /// 面部多帧缓冲
    private var faceFrameBuffer: [[FaceLandmark]] = []
    /// 身体多帧缓冲
    private var bodyFrameBuffer: [[Landmark]] = []
    /// 缓冲区最大帧数（约 0.5 秒 @30fps）
    private let bufferMaxFrames = 15
    /// 是否启用缓冲区（只在录制时启用，避免影响实时性能）
    @Published var isBufferingEnabled = false

    /// EMA 平滑：存储上一次平滑后的 landmark 坐标，用于帧间去抖
    private var emaBody: [BodyJoint: (x: Double, y: Double)] = [:]
    private var emaHands: [String: (x: Double, y: Double)] = [:]   // key = "left|jointName"
    private var emaFace: [FaceLandmarkKey: (x: Double, y: Double)] = [:]
    private let emaAlpha: Double = 0.7

    private let processQueue = DispatchQueue(label: "vision.process")

    /// 分帧交替检测：身体每帧都跑，手部和面部交替，减少单帧负载
    private var detectionPhase = 0
    private var cachedHands: [HandLandmark] = []
    private var cachedFace: [FaceLandmark] = []

    override init() {
        super.init()
        sender.host = UserDefaults.standard.string(forKey: "savedHost") ?? ""
        sender.port = UInt16(UserDefaults.standard.integer(forKey: "savedPort"))
        autoHoldThreshold = UserDefaults.standard.double(forKey: "autoHoldThreshold")
        if autoHoldThreshold < 0.05 { autoHoldThreshold = 0.3 }
        enableBody = UserDefaults.standard.object(forKey: "enableBody") as? Bool ?? true
        enableHands = UserDefaults.standard.object(forKey: "enableHands") as? Bool ?? true
        enableFace = UserDefaults.standard.object(forKey: "enableFace") as? Bool ?? true
        sender.onStatusChange = { [weak self] connected in
            DispatchQueue.main.async {
                self?.udpConnected = connected
                if connected {
                    self?.sendAllMappings()
                }
            }
        }
        loadHandTemplates()
        loadFaceTemplates()
    }

    func requestAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            statusMessage = "相机已授权，启动中..."
            startCamera()
        case .notDetermined:
            statusMessage = "请求相机权限..."
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.statusMessage = "权限已获取，启动相机..."
                        self?.startCamera()
                    } else {
                        self?.statusMessage = "需要相机权限才能使用"
                    }
                }
            }
        case .denied, .restricted:
            statusMessage = "请在 设置 → 隐私 → 相机 中允许访问"
        @unknown default:
            break
        }
    }

    private func startCamera() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setupSession()
            self?.session.startRunning()
            DispatchQueue.main.async {
                if self?.session.isRunning == true {
                    self?.statusMessage = ""
                } else {
                    self?.statusMessage = "相机启动失败，请重启 App"
                }
            }
        }
    }

    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition) else {
            DispatchQueue.main.async { self.statusMessage = "未找到摄像头" }
            session.commitConfiguration()
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                DispatchQueue.main.async { self.statusMessage = "无法添加相机输入" }
                session.commitConfiguration()
                return
            }
            session.addInput(input)
        } catch {
            DispatchQueue.main.async { self.statusMessage = "相机错误: \(error.localizedDescription)" }
            session.commitConfiguration()
            return
        }

        videoOutput.setSampleBufferDelegate(self, queue: processQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        if let conn = videoOutput.connection(with: .video) {
            // 使用旧的 API（iOS 17 弃用但仍可用），保持原有行为
            // 新的 rotationAngle API 行为不同，会导致骨骼坐标异常
            if conn.isVideoOrientationSupported { conn.videoOrientation = .portrait }
            // 前置摄像头：镜像像素流以匹配自拍预览，避免骨骼左右颠倒
            if cameraPosition == .front && conn.isVideoMirroringSupported {
                conn.isVideoMirrored = true
            }
        }

        session.commitConfiguration()
    }

    func stop() {
        session.stopRunning()
        sender.disconnect()
    }

    func pauseTracking() {
        if session.isRunning { session.stopRunning() }
    }

    func resumeTracking() {
        if !session.isRunning { session.startRunning() }
    }

    func toggleCamera() {
        session.stopRunning()
        for input in session.inputs {
            session.removeInput(input)
        }
        cameraPosition = (cameraPosition == .back) ? .front : .back
        startCamera()
    }

    func connectUDP(host: String, port: String) {
        sender.host = host
        let p = UInt16(port) ?? 54321
        sender.port = p
        UserDefaults.standard.set(host, forKey: "savedHost")
        UserDefaults.standard.set(Int(p), forKey: "savedPort")
        sender.connect()
    }

    func disconnectUDP() {
        sender.disconnect()
    }

    func loadRules() {
        if let data = UserDefaults.standard.data(forKey: "combinationRules"),
           let rules = try? JSONDecoder().decode([CombinationRule].self, from: data) {
            matcher.combinationRules = rules
        }
        if let data = UserDefaults.standard.data(forKey: "sequenceRules"),
           let rules = try? JSONDecoder().decode([SequenceRule].self, from: data) {
            matcher.sequenceRules = rules
        }
    }

    func saveRules() {
        if let data = try? JSONEncoder().encode(matcher.combinationRules) {
            UserDefaults.standard.set(data, forKey: "combinationRules")
        }
        if let data = try? JSONEncoder().encode(matcher.sequenceRules) {
            UserDefaults.standard.set(data, forKey: "sequenceRules")
        }
    }

    func saveHoldThreshold() {
        UserDefaults.standard.set(autoHoldThreshold, forKey: "autoHoldThreshold")
    }

    func saveDetectionToggles() {
        UserDefaults.standard.set(enableBody, forKey: "enableBody")
        UserDefaults.standard.set(enableHands, forKey: "enableHands")
        UserDefaults.standard.set(enableFace, forKey: "enableFace")
    }

    func sendAllMappings() {
        if let data = UserDefaults.standard.data(forKey: "templates"),
           let templates = try? JSONDecoder().decode([PoseTemplate].self, from: data) {
            matcher.templates = templates
        }
        var mappings: [String: ActionMapping] = [:]
        for t in matcher.templates {
            if !t.keyboardKey.isEmpty {
                mappings[t.actionKey] = ActionMapping(key: t.keyboardKey, mode: t.pressMode)
            }
        }
        // 也把手部/脸部模板的按键映射加进去
        for t in handTemplates {
            if !t.keyboardKey.isEmpty {
                mappings[t.actionKey] = ActionMapping(key: t.keyboardKey, mode: t.pressMode)
            }
        }
        for t in faceTemplates {
            if !t.keyboardKey.isEmpty {
                mappings[t.actionKey] = ActionMapping(key: t.keyboardKey, mode: t.pressMode)
            }
        }
        // 收集所有分类的动作名
        let bodyNames = matcher.templates.map(\.actionKey)
        let handNames = handTemplates.map(\.actionKey)
        let faceNames = faceTemplates.map(\.actionKey)
        sender.sendConfig(mappings, threshold: autoHoldThreshold,
                          bodyNames: bodyNames, handNames: handNames, faceNames: faceNames)
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // 身体每帧检测优先保证响应速度，手势/脸部分频交替
        var runHands = enableHands && (detectionPhase % 3 == 1)
        var runFace = enableFace && (detectionPhase % 3 == 2)
        if enableHands && !enableFace { runHands = (detectionPhase % 2 == 0) }
        if enableFace && !enableHands { runFace = (detectionPhase % 2 == 0) }
        detectionPhase += 1

        let phase: PoseDetector.Phase
        switch (runHands, runFace) {
        case (true, true): phase = .all
        case (true, false): phase = .bodyAndHands
        case (false, true): phase = .bodyAndFace
        case (false, false): phase = .bodyOnly
        }

        let result = detector.detect(pixelBuffer: pixelBuffer, phase: phase)

        // 用当前帧结果更新缓存，未检测的用缓存补充
        var finalHands = result.hands
        var finalFace = result.face
        if !enableHands { finalHands = [] }
        else if !runHands { finalHands = cachedHands }
        else { cachedHands = result.hands }

        if !enableFace { finalFace = [] }
        else if !runFace { finalFace = cachedFace }
        else { cachedFace = result.face }

        // 如果身体检测关闭，直接用空结果
        let finalBody = enableBody ? result.body : []

        // 只在录制时更新缓冲区（避免影响实时性能）
        if isBufferingEnabled {
            if !finalHands.isEmpty {
                handFrameBuffer.append(finalHands)
                if handFrameBuffer.count > bufferMaxFrames { handFrameBuffer.removeFirst() }
            }
            if !finalFace.isEmpty {
                faceFrameBuffer.append(finalFace)
                if faceFrameBuffer.count > bufferMaxFrames { faceFrameBuffer.removeFirst() }
            }
            if !finalBody.isEmpty {
                bodyFrameBuffer.append(finalBody)
                if bodyFrameBuffer.count > bufferMaxFrames { bodyFrameBuffer.removeFirst() }
            }
        }

        // 同步 matcher 模板
        matcher.handTemplates = handTemplates
        matcher.faceTemplates = faceTemplates

        // EMA 平滑（仅用于骨骼显示，不参与匹配以减少延迟）
        let smoothedBody = smoothBody(finalBody)
        let smoothedHands = smoothHands(finalHands)
        let smoothedFace = smoothFace(finalFace)

        // 动作匹配使用原始数据（无 EMA 延迟）
        let bodyActions = enableBody ? matcher.match(landmarks: finalBody) : []
        let handActions = enableHands ? matcher.matchHands(handLandmarks: finalHands) : []
        let faceActions = enableFace ? matcher.matchFace(faceLandmarks: finalFace) : []

        // 合并所有动作 + 组合规则
        var allActions = Set(bodyActions + handActions + faceActions)

        // 分支组合
        for rule in matcher.combinationRules {
            if rule.requires.allSatisfy({ allActions.contains($0) }) {
                allActions.insert(rule.actionKey)
            }
        }
        // 顺序组合
        for rule in matcher.sequenceRules {
            let now = Date()
            var progress = matcher.sequenceProgress[rule.id] ?? (step: 0, lastTime: now)
            if now.timeIntervalSince(progress.lastTime) > rule.timeout {
                progress = (step: 0, lastTime: now)
            }
            let expected = rule.steps.indices.contains(progress.step) ? rule.steps[progress.step] : nil
            if let exp = expected, allActions.contains(exp) {
                progress.step += 1
                progress.lastTime = now
                if progress.step >= rule.steps.count {
                    allActions.insert(rule.actionKey)
                    progress = (step: 0, lastTime: now)
                }
            }
            matcher.sequenceProgress[rule.id] = progress
        }

        let vw = CVPixelBufferGetWidth(pixelBuffer)
        let vh = CVPixelBufferGetHeight(pixelBuffer)

        DispatchQueue.main.async {
                self.landmarks = smoothedBody
                self.handLandmarks = smoothedHands
                self.faceLandmarks = smoothedFace
                self.faceBoundingBox = self.enableFace ? result.faceBoundingBox : .zero
                self.videoSize = CGSize(width: vw, height: vh)
                self.activeActions = Array(allActions)
        }

        var sendActions = Array(allActions)
        if sendActions.isEmpty && sender.isConnected {
            sendActions = ["connected"]
        }
        sender.send(result: result, actions: sendActions,
                     bodyActions: bodyActions, handActions: handActions, faceActions: faceActions)

        // 每 150 帧重发一次配置（Mac 重启后能自动恢复）
        configFrameCount += 1
        if configFrameCount >= 150 {
            configFrameCount = 0
            sendAllMappings()
        }
    }

    // MARK: - EMA 平滑

    private func smoothBody(_ landmarks: [Landmark]) -> [Landmark] {
        return landmarks.map { lm in
            if let prev = emaBody[lm.joint] {
                let sx = prev.x + emaAlpha * (lm.x - prev.x)
                let sy = prev.y + emaAlpha * (lm.y - prev.y)
                emaBody[lm.joint] = (sx, sy)
                return Landmark(joint: lm.joint, x: sx, y: sy, confidence: lm.confidence)
            } else {
                emaBody[lm.joint] = (lm.x, lm.y)
                return lm
            }
        }
    }

    private func smoothHands(_ hands: [HandLandmark]) -> [HandLandmark] {
        return hands.map { hand in
            let prefix = hand.chirality.rawValue
            let smoothedJoints = hand.joints.map { jp in
                let key = "\(prefix)|\(jp.n)"
                if let prev = emaHands[key] {
                    let sx = prev.x + emaAlpha * (jp.x - prev.x)
                    let sy = prev.y + emaAlpha * (jp.y - prev.y)
                    emaHands[key] = (sx, sy)
                    return HandJointPoint(n: jp.n, x: sx, y: sy, c: jp.c)
                } else {
                    emaHands[key] = (jp.x, jp.y)
                    return jp
                }
            }
            return HandLandmark(chirality: hand.chirality, joints: smoothedJoints)
        }
    }

    private func smoothFace(_ face: [FaceLandmark]) -> [FaceLandmark] {
        return face.map { f in
            if let prev = emaFace[f.n] {
                let sx = prev.x + emaAlpha * (f.x - prev.x)
                let sy = prev.y + emaAlpha * (f.y - prev.y)
                emaFace[f.n] = (sx, sy)
                return FaceLandmark(n: f.n, x: sx, y: sy, c: f.c)
            } else {
                emaFace[f.n] = (f.x, f.y)
                return f
            }
        }
    }

    // MARK: - 保存/加载手部模板

    func saveHandTemplates() {
        if let data = try? JSONEncoder().encode(handTemplates) {
            UserDefaults.standard.set(data, forKey: "handTemplates")
        }
    }

    func loadHandTemplates() {
        guard let data = UserDefaults.standard.data(forKey: "handTemplates"),
              let templates = try? JSONDecoder().decode([PoseTemplate].self, from: data)
        else { return }
        handTemplates = templates
    }

    // MARK: - 保存/加载面部模板

    func saveFaceTemplates() {
        if let data = try? JSONEncoder().encode(faceTemplates) {
            UserDefaults.standard.set(data, forKey: "faceTemplates")
        }
    }

    func loadFaceTemplates() {
        guard let data = UserDefaults.standard.data(forKey: "faceTemplates"),
              let templates = try? JSONDecoder().decode([PoseTemplate].self, from: data)
        else { return }
        faceTemplates = templates
    }

    // MARK: - 多帧平均采样

    /// 对手部多帧缓冲取平均，返回平滑后的 HandLandmark
    /// - Parameter chirality: 指定左手或右手，nil 则自动选择出现频率最高的
    func averagedHandLandmark(for chirality: HandChirality? = nil) -> HandLandmark? {
        guard !handFrameBuffer.isEmpty else { return nil }
        // 取最近的帧（最多 10 帧）
        let frames = Array(handFrameBuffer.suffix(10))
        // 展平所有检测到的手，按左右手分组
        let allHands = frames.flatMap { $0 }
        
        let targetHands: [HandLandmark]
        if let chirality = chirality {
            // 指定了左右手，只取对应的手
            targetHands = allHands.filter { $0.chirality == chirality }
            guard !targetHands.isEmpty else { return nil }
        } else {
            // 未指定，选择出现频率更高的那只手
            let leftHands = allHands.filter { $0.chirality == .left }
            let rightHands = allHands.filter { $0.chirality == .right }
            targetHands = leftHands.count >= rightHands.count ? leftHands : rightHands
            guard !targetHands.isEmpty else { return nil }
        }
        
        guard let first = targetHands.first else { return nil }

        // 对每个关节点取平均坐标
        var avgJoints: [String: (sumX: Double, sumY: Double, sumC: Double, count: Int)] = [:]
        for hand in targetHands {
            for jp in hand.joints {
                let entry = avgJoints[jp.n, default: (0, 0, 0, 0)]
                avgJoints[jp.n] = (entry.sumX + jp.x, entry.sumY + jp.y, entry.sumC + jp.c, entry.count + 1)
            }
        }

        var joints: [HandJointPoint] = []
        for (name, entry) in avgJoints {
            joints.append(HandJointPoint(
                n: name,
                x: entry.sumX / Double(entry.count),
                y: entry.sumY / Double(entry.count),
                c: entry.sumC / Double(entry.count)
            ))
        }
        return HandLandmark(chirality: first.chirality, joints: joints)
    }

    /// 对面部多帧缓冲取平均
    func averagedFaceLandmarks() -> [FaceLandmark] {
        guard !faceFrameBuffer.isEmpty else { return [] }
        let frames = Array(faceFrameBuffer.suffix(10))

        var avgPoints: [String: (sumX: Double, sumY: Double, sumC: Double, count: Int)] = [:]
        for face in frames {
            for f in face {
                let key = f.n.rawValue
                let entry = avgPoints[key, default: (0, 0, 0, 0)]
                avgPoints[key] = (entry.sumX + f.x, entry.sumY + f.y, entry.sumC + f.c, entry.count + 1)
            }
        }

        var results: [FaceLandmark] = []
        for (name, entry) in avgPoints {
            guard let key = FaceLandmarkKey(rawValue: name) else { continue }
            results.append(FaceLandmark(
                n: key,
                x: entry.sumX / Double(entry.count),
                y: entry.sumY / Double(entry.count),
                c: entry.sumC / Double(entry.count)
            ))
        }
        return results
    }

    /// 对身体多帧缓冲取平均
    func averagedBodyLandmarks() -> [Landmark] {
        guard !bodyFrameBuffer.isEmpty else { return [] }
        let frames = Array(bodyFrameBuffer.suffix(10))

        var avgPoints: [String: (sumX: Double, sumY: Double, sumC: Double, count: Int)] = [:]
        for body in frames {
            for lm in body {
                let key = lm.joint.rawValue
                let entry = avgPoints[key, default: (0, 0, 0, 0)]
                avgPoints[key] = (entry.sumX + lm.x, entry.sumY + lm.y, entry.sumC + lm.confidence, entry.count + 1)
            }
        }

        var results: [Landmark] = []
        for (name, entry) in avgPoints {
            guard let joint = BodyJoint(rawValue: name) else { continue }
            results.append(Landmark(
                joint: joint,
                x: entry.sumX / Double(entry.count),
                y: entry.sumY / Double(entry.count),
                confidence: entry.sumC / Double(entry.count)
            ))
        }
        return results
    }

    /// 清空所有缓冲区
    func clearBuffers() {
        handFrameBuffer.removeAll()
        faceFrameBuffer.removeAll()
        bodyFrameBuffer.removeAll()
    }
}
