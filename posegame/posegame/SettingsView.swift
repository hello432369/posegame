import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var camera: CameraManager
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var port = "54321"
    @State private var showRecorder = false
    @State private var showHandRecorder = false
    @State private var showFaceRecorder = false
    @State private var showComboBuilder = false
    @State private var showSequenceBuilder = false

    // 手势分组
    private var leftHandTemplates: [PoseTemplate] {
        camera.handTemplates.filter { $0.name.hasSuffix("[left]") }
    }
    private var rightHandTemplates: [PoseTemplate] {
        camera.handTemplates.filter { $0.name.hasSuffix("[right]") }
    }
    private var unspecifiedHandTemplates: [PoseTemplate] {
        camera.handTemplates.filter { !$0.name.hasSuffix("[left]") && !$0.name.hasSuffix("[right]") }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("UDP 连接") {
                    TextField("电脑 IP", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .onChange(of: host) { _ in
                            camera.sender.host = host
                        }
                    TextField("端口", text: $port)
                        .keyboardType(.numberPad)
                    HStack {
                        Button(camera.udpConnected ? "断开" : "连接") {
                            if camera.udpConnected {
                                camera.disconnectUDP()
                            } else {
                                camera.connectUDP(host: host, port: port)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                        Circle().fill(camera.udpConnected ? Color.green : Color.red).frame(width: 10, height: 10)
                        Text(camera.udpConnected ? "已连接" : "未连接")
                            .foregroundColor(camera.udpConnected ? .green : .secondary)
                    }
                }

                Section("智能模式") {
                    VStack {
                        HStack {
                            Text("快速抬起阈值: \(String(format: "%.2f", camera.autoHoldThreshold))秒")
                            Spacer()
                        }
                        Slider(value: $camera.autoHoldThreshold, in: 0.05...1.0, step: 0.05) { _ in
                            camera.saveHoldThreshold()
                        }
                        Text("抬起后在这个时间内放下 = 点按\n超过这个时间 = 按住")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Section("检测开关") {
                    Toggle(isOn: $camera.enableBody) {
                        VStack(alignment: .leading) {
                            Text("身体检测")
                            Text("检测全身骨骼关节点").font(.caption).foregroundColor(.secondary)
                        }
                    }.onChange(of: camera.enableBody) { _ in camera.saveDetectionToggles() }
                    Toggle(isOn: $camera.enableHands) {
                        VStack(alignment: .leading) {
                            Text("手势检测")
                            Text("检测左右手 21 个关节点").font(.caption).foregroundColor(.secondary)
                        }
                    }.onChange(of: camera.enableHands) { _ in camera.saveDetectionToggles() }
                    Toggle(isOn: $camera.enableFace) {
                        VStack(alignment: .leading) {
                            Text("面部检测")
                            Text("检测面部五官特征点").font(.caption).foregroundColor(.secondary)
                        }
                    }.onChange(of: camera.enableFace) { _ in camera.saveDetectionToggles() }
                }

                Section("基础姿势") {
                    if camera.matcher.templates.isEmpty {
                        Text("暂无基础姿势，点击下方录制")
                            .foregroundColor(.secondary)
                    }
                    ForEach(camera.matcher.templates) { t in
                        NavigationLink(destination: TemplateEditView(template: t, onUpdate: { updated in
                            if let idx = camera.matcher.templates.firstIndex(where: { $0.id == t.id }) {
                                camera.matcher.templates[idx] = updated
                            }
                            saveTemplates()
                        })) {
                            VStack(alignment: .leading) {
                                Text(t.name).font(.headline)
                                HStack {
                                    Text("→ \(t.actionKey)").foregroundColor(.secondary).font(.caption)
                                    if !t.keyboardKey.isEmpty {
                                        Text("| \(t.keyboardKey)").foregroundColor(.blue).font(.caption)
                                        Text(modeLabel(t.pressMode)).foregroundColor(.secondary).font(.caption)
                                    }
                                }
                                Text("阈值: \(String(format: "%.2f", t.threshold)) | \(t.joints.count) 个关节点")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        camera.matcher.templates.remove(atOffsets: offsets)
                        saveTemplates()
                    }
                    Button("录制身体姿势") { showRecorder = true }
                }

                // 左手手势
                if !leftHandTemplates.isEmpty {
                    Section("👈 右手手势") {
                        ForEach(leftHandTemplates) { t in
                            NavigationLink(destination: TemplateEditView(template: t, onUpdate: { updated in
                                if let idx = camera.handTemplates.firstIndex(where: { $0.id == t.id }) {
                                    camera.handTemplates[idx] = updated
                                }
                                camera.saveHandTemplates()
                            })) {
                                VStack(alignment: .leading) {
                                    Text(t.name.replacingOccurrences(of: "[left]", with: "")).font(.headline)
                                    HStack {
                                        Text("→ \(t.actionKey)").foregroundColor(.secondary).font(.caption)
                                        if !t.keyboardKey.isEmpty {
                                            Text("| \(t.keyboardKey)").foregroundColor(.blue).font(.caption)
                                            Text(modeLabel(t.pressMode)).foregroundColor(.secondary).font(.caption)
                                        }
                                    }
                                    Text("\(t.joints.count) 个关节点").font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            let idsToDelete = Set(offsets.map { leftHandTemplates[$0].id })
                            camera.handTemplates.removeAll { idsToDelete.contains($0.id) }
                            camera.saveHandTemplates()
                        }
                    }
                }

                // 右手手势
                if !rightHandTemplates.isEmpty {
                    Section("👉 左手手势") {
                        ForEach(rightHandTemplates) { t in
                            NavigationLink(destination: TemplateEditView(template: t, onUpdate: { updated in
                                if let idx = camera.handTemplates.firstIndex(where: { $0.id == t.id }) {
                                    camera.handTemplates[idx] = updated
                                }
                                camera.saveHandTemplates()
                            })) {
                                VStack(alignment: .leading) {
                                    Text(t.name.replacingOccurrences(of: "[right]", with: "")).font(.headline)
                                    HStack {
                                        Text("→ \(t.actionKey)").foregroundColor(.secondary).font(.caption)
                                        if !t.keyboardKey.isEmpty {
                                            Text("| \(t.keyboardKey)").foregroundColor(.blue).font(.caption)
                                            Text(modeLabel(t.pressMode)).foregroundColor(.secondary).font(.caption)
                                        }
                                    }
                                    Text("\(t.joints.count) 个关节点").font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            let idsToDelete = Set(offsets.map { rightHandTemplates[$0].id })
                            camera.handTemplates.removeAll { idsToDelete.contains($0.id) }
                            camera.saveHandTemplates()
                        }
                    }
                }

                // 未指定手的手势（旧模板兼容）
                if !unspecifiedHandTemplates.isEmpty {
                    Section("✋ 未指定手的手势") {
                        ForEach(unspecifiedHandTemplates) { t in
                            NavigationLink(destination: TemplateEditView(template: t, onUpdate: { updated in
                                if let idx = camera.handTemplates.firstIndex(where: { $0.id == t.id }) {
                                    camera.handTemplates[idx] = updated
                                }
                                camera.saveHandTemplates()
                            })) {
                                VStack(alignment: .leading) {
                                    Text(t.name).font(.headline)
                                    HStack {
                                        Text("→ \(t.actionKey)").foregroundColor(.secondary).font(.caption)
                                        if !t.keyboardKey.isEmpty {
                                            Text("| \(t.keyboardKey)").foregroundColor(.blue).font(.caption)
                                            Text(modeLabel(t.pressMode)).foregroundColor(.secondary).font(.caption)
                                        }
                                    }
                                    Text("\(t.joints.count) 个关节点").font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            let idsToDelete = Set(offsets.map { unspecifiedHandTemplates[$0].id })
                            camera.handTemplates.removeAll { idsToDelete.contains($0.id) }
                            camera.saveHandTemplates()
                        }
                    }
                }

                if camera.handTemplates.isEmpty {
                    Section("手势姿势") {
                        Text("暂无手势姿势，点击下方录制")
                            .foregroundColor(.secondary)
                        Button("录制手势姿势") { showHandRecorder = true }
                    }
                } else {
                    Section {
                        Button("录制手势姿势") { showHandRecorder = true }
                    }
                }

                Section("头部姿势") {
                    if camera.faceTemplates.isEmpty {
                        Text("暂无头部姿势，点击下方录制")
                            .foregroundColor(.secondary)
                    }
                    ForEach(camera.faceTemplates) { t in
                        NavigationLink(destination: TemplateEditView(template: t, onUpdate: { updated in
                            if let idx = camera.faceTemplates.firstIndex(where: { $0.id == t.id }) {
                                camera.faceTemplates[idx] = updated
                            }
                            camera.saveFaceTemplates()
                        })) {
                            VStack(alignment: .leading) {
                                Text(t.name).font(.headline)
                                HStack {
                                    Text("→ \(t.actionKey)").foregroundColor(.secondary).font(.caption)
                                    if !t.keyboardKey.isEmpty {
                                        Text("| \(t.keyboardKey)").foregroundColor(.blue).font(.caption)
                                        Text(modeLabel(t.pressMode)).foregroundColor(.secondary).font(.caption)
                                    }
                                }
                                Text("\(t.joints.count) 个特征点").font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        camera.faceTemplates.remove(atOffsets: offsets)
                        camera.saveFaceTemplates()
                    }
                    Button("录制头部姿势") { showFaceRecorder = true }
                }

                Section("顺序组合") {
                    if camera.matcher.sequenceRules.isEmpty {
                        Text("暂无顺序组合")
                            .foregroundColor(.secondary)
                    }
                    ForEach(camera.matcher.sequenceRules) { rule in
                        NavigationLink(destination: SequenceRuleEditView(rule: rule, available: allActions, onSave: { updated in
                            if let idx = camera.matcher.sequenceRules.firstIndex(where: { $0.id == rule.id }) {
                                camera.matcher.sequenceRules[idx] = updated
                            }
                            camera.saveRules()
                        })) {
                            VStack(alignment: .leading) {
                                Text(rule.name).font(.headline)
                                Text("\(rule.steps.joined(separator: " → ")) → \(rule.actionKey)")
                                    .foregroundColor(.secondary).font(.caption)
                                Text("超时 \(String(format: "%.0f", rule.timeout))秒")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        camera.matcher.sequenceRules.remove(atOffsets: offsets)
                        camera.saveRules()
                    }
                    Button("添加顺序组合") { showSequenceBuilder = true }
                }

                Section("分支组合") {
                    if camera.matcher.combinationRules.isEmpty {
                        Text("暂无分支组合")
                            .foregroundColor(.secondary)
                    }
                    ForEach(camera.matcher.combinationRules) { rule in
                        NavigationLink(destination: BranchRuleEditView(rule: rule, available: allActions, onSave: { updated in
                            if let idx = camera.matcher.combinationRules.firstIndex(where: { $0.id == rule.id }) {
                                camera.matcher.combinationRules[idx] = updated
                            }
                            camera.saveRules()
                        })) {
                            VStack(alignment: .leading) {
                                Text(rule.name).font(.headline)
                                Text("当 \(rule.requires.joined(separator: " + ")) → \(rule.actionKey)")
                                    .foregroundColor(.secondary).font(.caption)
                            }
                        }
                    }
                    .onDelete { offsets in
                        camera.matcher.combinationRules.remove(atOffsets: offsets)
                        camera.saveRules()
                    }
                    Button("添加分支组合") { showComboBuilder = true }
                }

                Section("帮助") {
                    Text("1. 确保电脑和手机在同一个 Wi-Fi\n2. 电脑上运行 KeyBridge (桌面 App)\n3. 连接后摆出姿势即可控制游戏")
                        .font(.caption)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .navigationTitle("设置")
            .onAppear {
                host = camera.sender.host
                port = String(camera.sender.port)
                loadTemplates()
                camera.loadRules()
            }
            .sheet(isPresented: $showRecorder) {
                PoseRecorderView { template in
                    camera.matcher.templates.append(template)
                    saveTemplates()
                }
            }
            .sheet(isPresented: $showHandRecorder) {
                HandPoseRecorderView { template in
                    camera.handTemplates.append(template)
                    camera.saveHandTemplates()
                }
            }
            .sheet(isPresented: $showFaceRecorder) {
                FacePoseRecorderView { template in
                    camera.faceTemplates.append(template)
                    camera.saveFaceTemplates()
                }
            }
            .sheet(isPresented: $showComboBuilder) {
                RuleBuilderView { rule in
                    camera.matcher.combinationRules.append(rule)
                    camera.saveRules()
                }
            }
            .sheet(isPresented: $showSequenceBuilder) {
                SequenceBuilderView { rule in
                    camera.matcher.sequenceRules.append(rule)
                    camera.saveRules()
                }
            }
        }
    }

    var allActions: [String] {
        let body = camera.matcher.templates.map(\.actionKey)
        let hand = camera.handTemplates.map(\.actionKey)
        let face = camera.faceTemplates.map(\.actionKey)
        return Set(body + hand + face).sorted()
    }

    private func loadTemplates() {
        guard let data = UserDefaults.standard.data(forKey: "templates"),
              let templates = try? JSONDecoder().decode([PoseTemplate].self, from: data)
        else { return }
        camera.matcher.templates = templates
    }

    private func saveTemplates() {
        if let data = try? JSONEncoder().encode(camera.matcher.templates) {
            UserDefaults.standard.set(data, forKey: "templates")
        }
    }
}

// MARK: - 身体姿势录制

struct PoseRecorderView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var camera: CameraManager
    @State private var name = ""
    @State private var actionKey = ""
    @State private var keyboardKey = ""
    @State private var pressMode = "auto"
    @State private var threshold: Double = 0.45
    @State private var countdownDuration: Double = 5
    @State private var isCountingDown = false
    @State private var baseLandmarks: [Landmark] = []
    @State private var actionLandmarks: [Landmark] = []
    @State private var countingFor = ""
    @State private var diffReady = false
    @State private var capturedJoints: [String: [Double]] = [:]
    @State private var recordingError = ""
    let onSave: (PoseTemplate) -> Void

    var body: some View {
        ZStack {
            Color.clear.onAppear {
                camera.resumeTracking()
                camera.isBufferingEnabled = true
            }
                .onDisappear {
                    camera.pauseTracking()
                    camera.isBufferingEnabled = false
                    camera.clearBuffers()
                }
                .frame(width: 0, height: 0)
            if isCountingDown {
                Color.black.ignoresSafeArea()
                SkeletonOverlay(landmarks: camera.landmarks, hands: [], face: [], actions: [], videoSize: camera.videoSize)
                VStack {
                    Spacer()
                    Text("\(countdownValue)")
                        .font(.system(size: 120, weight: .bold))
                        .foregroundColor(.orange)
                        .shadow(radius: 10)
                    Text(countingFor == "base" ? "保持放松姿态不动..." : "保持动作姿态不动...")
                        .foregroundColor(.white)
                        .shadow(radius: 5)
                    Button("取消") { isCountingDown = false }
                        .foregroundColor(.red)
                        .padding(.top, 20)
                    Spacer().frame(height: 80)
                }
            } else {
                NavigationStack {
                    Form {
                        Section("姿态名称") {
                            TextField("名称", text: $name)
                        }
                        Section("输出动作名") {
                            TextField("如 punch, block", text: $actionKey)
                        }
                        Section("按键映射") {
                            TextField("按键（如 a, space, ctrl+a, shift+space）", text: $keyboardKey)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            if !keyboardKey.isEmpty {
                                Picker("按键模式", selection: $pressMode) {
                                    ForEach(pressModeNames, id: \.0) { m in
                                        Text(m.1).tag(m.0)
                                    }
                                }
                            }
                        }
                        Section("灵敏度") {
                            Slider(value: $threshold, in: 0.3...0.95, step: 0.05)
                            Text("阈值: \(String(format: "%.2f", threshold))（越低越容易触发）")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Section("录制") {
                            Button(action: { startCountdown(target: "base") }) {
                                HStack {
                                    Image(systemName: baseLandmarks.isEmpty ? "circle" : "checkmark.circle.fill")
                                        .foregroundColor(baseLandmarks.isEmpty ? .gray : .green)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(baseLandmarks.isEmpty ? "录制基准姿态（放松状态）" : "重新录制基准姿态")
                                            .font(.body)
                                        if !baseLandmarks.isEmpty {
                                            Text("✓ 已录 \(baseLandmarks.filter { $0.confidence > 0.5 }.count) 个关节")
                                                .font(.caption).foregroundColor(.green)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            .disabled(!actionLandmarks.isEmpty)
                            .buttonStyle(.plain)

                            Button(action: { startCountdown(target: "action") }) {
                                HStack {
                                    Image(systemName: actionLandmarks.isEmpty ? "circle" : "checkmark.circle.fill")
                                        .foregroundColor(actionLandmarks.isEmpty ? .gray : .green)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(actionLandmarks.isEmpty ? "录制动作姿态（比划的动作）" : "重新录制动作姿态")
                                            .font(.body)
                                        if !actionLandmarks.isEmpty {
                                            Text("✓ 已录 \(actionLandmarks.filter { $0.confidence > 0.5 }.count) 个关节")
                                                .font(.caption).foregroundColor(.green)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            .disabled(baseLandmarks.isEmpty || !actionLandmarks.isEmpty)
                            .buttonStyle(.plain)

                            HStack(spacing: 8) {
                                Text("倒计时")
                                Slider(value: $countdownDuration, in: 2...30, step: 1)
                                Text("\(Int(countdownDuration))秒")
                                    .font(.caption).frame(width: 40)
                            }

                            if !recordingError.isEmpty {
                                Text(recordingError).foregroundColor(.red).font(.caption)
                            }

                            if diffReady {
                                VStack(alignment: .center, spacing: 12) {
                                    Divider()
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(.green)
                                    Text("已记录 \(capturedJoints.count) 个变化关节")
                                        .font(.headline)
                                    if !capturedJoints.isEmpty {
                                        Text(capturedJoints.keys.sorted().joined(separator: ", "))
                                            .font(.caption2).foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    HStack(spacing: 20) {
                                        Button("重录") {
                                            baseLandmarks = []
                                            actionLandmarks = []
                                            capturedJoints = [:]
                                            diffReady = false
                                            recordingError = ""
                                        }
                                        .foregroundColor(.orange)
                                        Button("保存") {
                                            let t = PoseTemplate(
                                                id: UUID(),
                                                name: name.isEmpty ? actionKey : name,
                                                actionKey: actionKey,
                                                joints: capturedJoints,
                                                threshold: threshold,
                                                keyboardKey: keyboardKey,
                                                pressMode: pressMode
                                            )
                                            onSave(t)
                                            camera.sendAllMappings()
                                            dismiss()
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("录制姿态")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(diffReady ? "关闭" : "取消") { dismiss() }
                        }
                        if diffReady {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") { dismiss() }
                            }
                        }
                    }
                }
            }
        }
    }

    func startCountdown(target: String) {
        recordingError = ""
        countingFor = target
        countdownValue = Int(countdownDuration)
        isCountingDown = true
        tickCountdown()
    }

    @State private var countdownValue = 0

    private func tickCountdown() {
        guard isCountingDown else { return }
        guard countdownValue > 1 else {
            if countingFor == "base" { captureBase() }
            else { captureAction() }
            return
        }
        countdownValue -= 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { tickCountdown() }
    }

    func captureBase() {
        // 使用多帧平均采样
        let landmarks = camera.averagedBodyLandmarks()
        let validCount = landmarks.filter { $0.confidence > 0.5 }.count
        if validCount < 3 {
            recordingError = "未检测到身体，请确保全身在画面内保持不动"
            isCountingDown = false
            return
        }
        baseLandmarks = landmarks
        isCountingDown = false
        recordingError = ""
    }

    func captureAction() {
        guard !baseLandmarks.isEmpty else {
            recordingError = "请先录制基准姿态"
            isCountingDown = false
            return
        }
        // 使用多帧平均采样
        actionLandmarks = camera.averagedBodyLandmarks()
        isCountingDown = false

        let t = camera.matcher.recordDifferentialTemplate(
            name: name.isEmpty ? "未命名" : name,
            actionKey: actionKey,
            landmarks: actionLandmarks,
            baseLandmarks: baseLandmarks
        )
        capturedJoints = t.joints
        if capturedJoints.isEmpty {
            recordingError = "动作与基准太像，换个姿势再试"
            actionLandmarks = []
        } else {
            diffReady = true
            recordingError = ""
        }
    }

    func sendConfigToMac() {
        var mappings: [String: ActionMapping] = [:]
        if !keyboardKey.isEmpty {
            mappings[actionKey] = ActionMapping(key: keyboardKey, mode: pressMode)
        }
        camera.sender.sendConfig(mappings, threshold: camera.autoHoldThreshold)
    }
}

// MARK: - 手部姿势录制（差分录制）

struct HandPoseRecorderView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var camera: CameraManager
    @State private var name = ""
    @State private var actionKey = ""
    @State private var keyboardKey = ""
    @State private var pressMode = "auto"
    @State private var threshold: Double = 0.5
    @State private var isCountingDown = false
    @State private var countdownValue = 0
    @State private var countdownDuration: Double = 5
    @State private var baseHand: HandLandmark?
    @State private var actionHand: HandLandmark?
    @State private var countingFor = ""
    @State private var diffReady = false
    @State private var capturedJoints: [String: [Double]] = [:]
    @State private var recordingError = ""
    @State private var selectedHand: HandChirality? = nil
    let onSave: (PoseTemplate) -> Void

    var body: some View {
        ZStack {
            Color.clear.onAppear {
                camera.resumeTracking()
                camera.isBufferingEnabled = true
            }
                .onDisappear {
                    camera.pauseTracking()
                    camera.isBufferingEnabled = false
                    camera.clearBuffers()
                }
                .frame(width: 0, height: 0)
            if isCountingDown {
                Color.black.ignoresSafeArea()
                SkeletonOverlay(landmarks: [], hands: camera.handLandmarks, face: [],
                                actions: [], videoSize: camera.videoSize)
                VStack {
                    Spacer()
                    Text("\(countdownValue)")
                        .font(.system(size: 120, weight: .bold))
                        .foregroundColor(.orange)
                        .shadow(radius: 10)
                    Text(countingFor == "base" ? "保持放松手势不动..." : "保持手势不动...")
                        .foregroundColor(.white)
                        .shadow(radius: 5)
                    Button("取消") { isCountingDown = false }
                        .foregroundColor(.red)
                        .padding(.top, 20)
                    Spacer().frame(height: 80)
                }
            } else {
                NavigationStack {
                    Form {
                        Section("手势名称") {
                            TextField("名称", text: $name)
                        }
                        Section("输出动作名") {
                            TextField("如 punch, wave", text: $actionKey)
                        }
                        Section("按键映射") {
                            TextField("按键（如 a, space, ctrl+a）", text: $keyboardKey)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            if !keyboardKey.isEmpty {
                                Picker("按键模式", selection: $pressMode) {
                                    ForEach(pressModeNames, id: \.0) { m in
                                        Text(m.1).tag(m.0)
                                    }
                                }
                            }
                        }
                        Section("灵敏度") {
                            Slider(value: $threshold, in: 0.3...0.95, step: 0.05)
                            Text("阈值: \(String(format: "%.2f", threshold))（越低越容易触发）")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Section("选择手") {
                            HStack(spacing: 20) {
                                Button(action: { selectedHand = .left }) {
                                    HStack {
                                        Image(systemName: selectedHand == .left ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedHand == .left ? .blue : .gray)
                                        Text("右手")
                                            .foregroundColor(selectedHand == .left ? .primary : .secondary)
                                    }
                                }
                                .buttonStyle(.plain)

                                Button(action: { selectedHand = .right }) {
                                    HStack {
                                        Image(systemName: selectedHand == .right ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedHand == .right ? .blue : .gray)
                                        Text("左手")
                                            .foregroundColor(selectedHand == .right ? .primary : .secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            if selectedHand == nil {
                                Text("请先选择要录制的手")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        Section("录制") {
                            Button(action: { startCountdown(target: "base") }) {
                                HStack {
                                    Image(systemName: baseHand != nil ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(baseHand != nil ? .green : .gray)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(baseHand == nil ? "录制放松手势（手部放松状态）" : "重新录制放松手势")
                                            .font(.body)
                                        if let h = baseHand {
                                            Text("✓ 已录 \(h.joints.count) 个关节点")
                                                .font(.caption).foregroundColor(.green)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            .disabled(selectedHand == nil || actionHand != nil)
                            .buttonStyle(.plain)

                            Button(action: { startCountdown(target: "action") }) {
                                HStack {
                                    Image(systemName: actionHand != nil ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(actionHand != nil ? .green : .gray)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(actionHand == nil ? "录制动作手势（比划的手势）" : "重新录制动作手势")
                                            .font(.body)
                                        if let h = actionHand {
                                            Text("✓ 已录 \(h.joints.count) 个关节点")
                                                .font(.caption).foregroundColor(.green)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            .disabled(selectedHand == nil || baseHand == nil || actionHand != nil)
                            .buttonStyle(.plain)

                            HStack(spacing: 8) {
                                Text("倒计时")
                                Slider(value: $countdownDuration, in: 2...30, step: 1)
                                Text("\(Int(countdownDuration))秒")
                                    .font(.caption).frame(width: 40)
                            }

                            if !recordingError.isEmpty {
                                Text(recordingError).foregroundColor(.red).font(.caption)
                            }

                            if diffReady {
                                VStack(alignment: .center, spacing: 12) {
                                    Divider()
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(.green)
                                    Text("已记录 \(capturedJoints.count) 个关节点")
                                        .font(.headline)
                                    if !capturedJoints.isEmpty {
                                        Text(capturedJoints.keys.sorted().joined(separator: ", "))
                                            .font(.caption2).foregroundColor(.secondary).lineLimit(2)
                                    }
                                    HStack(spacing: 20) {
                                        Button("重录") {
                                            baseHand = nil
                                            actionHand = nil
                                            capturedJoints = [:]
                                            diffReady = false
                                            recordingError = ""
                                        }
                                        .foregroundColor(.orange)
                                        Button("保存") {
                                            let t = PoseTemplate(
                                                id: UUID(),
                                                name: name.isEmpty ? actionKey : name,
                                                actionKey: actionKey,
                                                joints: capturedJoints,
                                                threshold: threshold,
                                                keyboardKey: keyboardKey,
                                                pressMode: pressMode
                                            )
                                            onSave(t)
                                            camera.sendAllMappings()
                                            dismiss()
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("录制手势姿势")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(diffReady ? "关闭" : "取消") { dismiss() }
                        }
                        if diffReady {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") { dismiss() }
                            }
                        }
                    }
                }
            }
        }
    }

    func startCountdown(target: String) {
        recordingError = ""
        countingFor = target
        countdownValue = Int(countdownDuration)
        isCountingDown = true
        tickCountdown()
    }

    private func tickCountdown() {
        guard isCountingDown else { return }
        guard countdownValue > 1 else {
            if countingFor == "base" { captureBase() }
            else { captureAction() }
            return
        }
        countdownValue -= 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { tickCountdown() }
    }

    func captureBase() {
        // 使用多帧平均采样，减少单帧抖动
        guard let selected = selectedHand else {
            recordingError = "请先选择左手或右手"
            isCountingDown = false
            return
        }
        guard let h = camera.averagedHandLandmark(for: selected) else {
            recordingError = "未检测到\(selected == .left ? "左手" : "右手")，请确保选择的手在画面内保持不动"
            isCountingDown = false
            return
        }
        baseHand = h
        isCountingDown = false
        recordingError = ""
    }

    func captureAction() {
        guard let selected = selectedHand else {
            recordingError = "请先选择左手或右手"
            isCountingDown = false
            return
        }
        guard let base = baseHand else {
            recordingError = "请先录制放松手势"
            isCountingDown = false
            return
        }
        // 使用多帧平均采样
        guard let action = camera.averagedHandLandmark(for: selected) else {
            recordingError = "未检测到\(selected == .left ? "左手" : "右手")，请确保选择的手在画面内保持不动"
            isCountingDown = false
            return
        }
        actionHand = action
        isCountingDown = false

        // 差分：以放松为基准，只保留变化大的关节（门槛已降至 0.3）
        guard let tmpl = camera.matcher.recordHandDifferentialTemplate(
            name: name.isEmpty ? "手势" : name,
            actionKey: actionKey,
            actionHand: action,
            baseHand: base
        ) else {
            recordingError = "手部未检测到足够关节点"
            return
        }
        capturedJoints = tmpl.joints
        if capturedJoints.isEmpty {
            recordingError = "手势与放松太像，换个姿势再试"
            actionHand = nil
        } else {
            diffReady = true
            recordingError = ""
        }
    }
}

// MARK: - 脸部姿势录制（差分录制）

struct FacePoseRecorderView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var camera: CameraManager
    @State private var name = ""
    @State private var actionKey = ""
    @State private var keyboardKey = ""
    @State private var pressMode = "auto"
    @State private var threshold: Double = 0.5
    @State private var isCountingDown = false
    @State private var countdownValue = 0
    @State private var countdownDuration: Double = 5
    @State private var baseFace: [FaceLandmark] = []
    @State private var actionFace: [FaceLandmark] = []
    @State private var countingFor = ""
    @State private var diffReady = false
    @State private var capturedJoints: [String: [Double]] = [:]
    @State private var recordingError = ""
    let onSave: (PoseTemplate) -> Void

    var body: some View {
        ZStack {
            Color.clear.onAppear {
                camera.resumeTracking()
                camera.isBufferingEnabled = true
            }
                .onDisappear {
                    camera.pauseTracking()
                    camera.isBufferingEnabled = false
                    camera.clearBuffers()
                }
                .frame(width: 0, height: 0)
            if isCountingDown {
                Color.black.ignoresSafeArea()
                SkeletonOverlay(landmarks: [], hands: [], face: camera.faceLandmarks,
                                actions: [], videoSize: camera.videoSize)
                VStack {
                    Spacer()
                    Text("\(countdownValue)")
                        .font(.system(size: 120, weight: .bold))
                        .foregroundColor(.orange)
                        .shadow(radius: 10)
                    Text(countingFor == "base" ? "保持放松表情不动..." : "保持动作表情不动...")
                        .foregroundColor(.white)
                        .shadow(radius: 5)
                    Button("取消") { isCountingDown = false }
                        .foregroundColor(.red)
                        .padding(.top, 20)
                    Spacer().frame(height: 80)
                }
            } else {
                NavigationStack {
                    Form {
                        Section("表情名称") {
                            TextField("名称", text: $name)
                        }
                        Section("输出动作名") {
                            TextField("如 smile, blink", text: $actionKey)
                        }
                        Section("按键映射") {
                            TextField("按键（如 a, space, ctrl+a）", text: $keyboardKey)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            if !keyboardKey.isEmpty {
                                Picker("按键模式", selection: $pressMode) {
                                    ForEach(pressModeNames, id: \.0) { m in
                                        Text(m.1).tag(m.0)
                                    }
                                }
                            }
                        }
                        Section("灵敏度") {
                            Slider(value: $threshold, in: 0.3...0.95, step: 0.05)
                            Text("阈值: \(String(format: "%.2f", threshold))（越低越容易触发）")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Section("录制") {
                            Button(action: { startCountdown(target: "base") }) {
                                HStack {
                                    Image(systemName: baseFace.isEmpty ? "circle" : "checkmark.circle.fill")
                                        .foregroundColor(baseFace.isEmpty ? .gray : .green)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(baseFace.isEmpty ? "录制放松表情（自然状态）" : "重新录制放松表情")
                                            .font(.body)
                                        if !baseFace.isEmpty {
                                            Text("✓ 已录 \(baseFace.count) 个特征点")
                                                .font(.caption).foregroundColor(.green)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            .disabled(!actionFace.isEmpty)
                            .buttonStyle(.plain)

                            Button(action: { startCountdown(target: "action") }) {
                                HStack {
                                    Image(systemName: actionFace.isEmpty ? "circle" : "checkmark.circle.fill")
                                        .foregroundColor(actionFace.isEmpty ? .gray : .green)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(actionFace.isEmpty ? "录制动作表情（要做出的表情）" : "重新录制动作表情")
                                            .font(.body)
                                        if !actionFace.isEmpty {
                                            Text("✓ 已录 \(actionFace.count) 个特征点")
                                                .font(.caption).foregroundColor(.green)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            .disabled(baseFace.isEmpty || !actionFace.isEmpty)
                            .buttonStyle(.plain)

                            HStack(spacing: 8) {
                                Text("倒计时")
                                Slider(value: $countdownDuration, in: 2...30, step: 1)
                                Text("\(Int(countdownDuration))秒")
                                    .font(.caption).frame(width: 40)
                            }

                            if !recordingError.isEmpty {
                                Text(recordingError).foregroundColor(.red).font(.caption)
                            }

                            if diffReady {
                                VStack(alignment: .center, spacing: 12) {
                                    Divider()
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(.green)
                                    Text("已记录 \(capturedJoints.count) 个变化特征点")
                                        .font(.headline)
                                    if !capturedJoints.isEmpty {
                                        Text(capturedJoints.keys.sorted().joined(separator: ", "))
                                            .font(.caption2).foregroundColor(.secondary).lineLimit(2)
                                    }
                                    HStack(spacing: 20) {
                                        Button("重录") {
                                            baseFace = []
                                            actionFace = []
                                            capturedJoints = [:]
                                            diffReady = false
                                            recordingError = ""
                                        }
                                        .foregroundColor(.orange)
                                        Button("保存") {
                                            let t = PoseTemplate(
                                                id: UUID(),
                                                name: name.isEmpty ? actionKey : name,
                                                actionKey: actionKey,
                                                joints: capturedJoints,
                                                threshold: threshold,
                                                keyboardKey: keyboardKey,
                                                pressMode: pressMode
                                            )
                                            onSave(t)
                                            camera.sendAllMappings()
                                            dismiss()
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("录制头部姿势")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(diffReady ? "关闭" : "取消") { dismiss() }
                        }
                        if diffReady {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") { dismiss() }
                            }
                        }
                    }
                }
            }
        }
    }

    func startCountdown(target: String) {
        recordingError = ""
        countingFor = target
        countdownValue = Int(countdownDuration)
        isCountingDown = true
        tickCountdown()
    }

    private func tickCountdown() {
        guard isCountingDown else { return }
        guard countdownValue > 1 else {
            if countingFor == "base" { captureBase() }
            else { captureAction() }
            return
        }
        countdownValue -= 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { tickCountdown() }
    }

    func captureBase() {
        // 使用多帧平均采样
        let avg = camera.averagedFaceLandmarks()
        if avg.isEmpty {
            recordingError = "未检测到面部，请正对摄像头保持不动"
            isCountingDown = false
            return
        }
        baseFace = avg
        isCountingDown = false
        recordingError = ""
    }

    func captureAction() {
        guard !baseFace.isEmpty else {
            recordingError = "请先录制放松表情"
            isCountingDown = false
            return
        }
        // 使用多帧平均采样
        let avg = camera.averagedFaceLandmarks()
        if avg.isEmpty {
            recordingError = "未检测到面部，请正对摄像头保持不动"
            isCountingDown = false
            return
        }
        actionFace = avg
        isCountingDown = false

        // 手动差分：只保留变化大的特征点
        var joints: [String: [Double]] = [:]
        let ref = actionFace.first(where: { $0.c > 0.5 })
            ?? actionFace.first
        guard let ref = ref else {
            recordingError = "未检测到面部特征点"
            return
        }

        for f in actionFace where f.c > 0.5 {
            let aRelX = f.x - ref.x
            let aRelY = f.y - ref.y
            let aAngle = atan2(aRelY, aRelX)
            let aMag = sqrt(aRelX * aRelX + aRelY * aRelY)

            if let baseF = baseFace.first(where: { $0.n == f.n && $0.c > 0.5 }) {
                let bRelX = baseF.x - ref.x
                let bRelY = baseF.y - ref.y
                let bAngle = atan2(bRelY, bRelX)
                var angleDiff = abs(aAngle - bAngle)
                if angleDiff > .pi { angleDiff = 2 * .pi - angleDiff }
                if angleDiff < 0.15 { continue }
            }
            joints[f.n.rawValue] = [aAngle, aMag]
        }

        capturedJoints = joints
        if capturedJoints.isEmpty {
            recordingError = "表情与放松太像，换个表情再试"
            actionFace = []
        } else {
            diffReady = true
            recordingError = ""
        }
    }
}

// MARK: - 分支组合

struct RuleBuilderView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var camera: CameraManager
    @State private var name = ""
    @State private var actionKey = ""
    @State private var selected: Set<String> = []
    let onSave: (CombinationRule) -> Void

    var actions: [String] {
        let body = camera.matcher.templates.map(\.actionKey)
        let hand = camera.handTemplates.map(\.actionKey)
        let face = camera.faceTemplates.map(\.actionKey)
        return Set(body + hand + face).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("规则名称") {
                    TextField("名称", text: $name)
                }

                Section("触发条件 (全部满足)") {
                    if actions.isEmpty {
                        Text("暂无可选动作，请先录制姿势/手势/头部姿势")
                            .foregroundColor(.secondary)
                    }
                    ForEach(actions, id: \.self) { a in
                        Button(action: {
                            if selected.contains(a) { selected.remove(a) }
                            else { selected.insert(a) }
                        }) {
                            HStack {
                                Image(systemName: selected.contains(a) ? "checkmark.circle.fill" : "circle")
                                Text(a)
                                Spacer()
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }

                Section("输出动作") {
                    TextField("动作名称", text: $actionKey)
                }

                Section {
                    Button("保存规则") {
                        guard !selected.isEmpty else { return }
                        let rule = CombinationRule(
                            id: UUID(),
                            name: name.isEmpty ? actionKey : name,
                            actionKey: actionKey,
                            requires: Array(selected).sorted()
                        )
                        onSave(rule)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty)
                }
            }
            .navigationTitle("分支组合")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

func modeLabel(_ m: String) -> String {
    switch m {
    case "hold": return "按住"
    case "tap": return "点按"
    case "release": return "松开"
    case "toggle": return "开关"
    default: return m
    }
}

struct TemplateEditView: View {
    @Environment(\.dismiss) var dismiss
    @State var template: PoseTemplate
    let onUpdate: (PoseTemplate) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("姿态名称") {
                    TextField("名称", text: $template.name)
                }
                Section("动作名") {
                    TextField("动作名", text: $template.actionKey)
                }
                Section("按键映射") {
                    TextField("按键（如 a, space, ctrl+a）", text: $template.keyboardKey)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    if !template.keyboardKey.isEmpty {
                        Picker("按键模式", selection: $template.pressMode) {
                            ForEach(pressModeNames, id: \.0) { m in
                                Text(m.1).tag(m.0)
                            }
                        }
                    }
                }
                Section("灵敏度") {
                    Slider(value: $template.threshold, in: 0.3...0.95, step: 0.05)
                    Text("阈值: \(String(format: "%.2f", template.threshold))")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section {
                    Text("已捕获 \(template.joints.count) 个关节点")
                        .font(.caption).foregroundColor(.secondary)
                    Text(template.joints.keys.sorted().joined(separator: ", "))
                        .font(.caption2).foregroundColor(.secondary)
                }
                Section {
                    Button("保存") {
                        onUpdate(template)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("编辑模板")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

struct BranchRuleEditView: View {
    @Environment(\.dismiss) var dismiss
    @State var rule: CombinationRule
    let available: [String]
    let onSave: (CombinationRule) -> Void
    @State private var selected: Set<String>

    init(rule: CombinationRule, available: [String], onSave: @escaping (CombinationRule) -> Void) {
        _rule = State(initialValue: rule)
        self.available = available
        self.onSave = onSave
        _selected = State(initialValue: Set(rule.requires))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("规则名称") {
                    TextField("名称", text: $rule.name)
                }
                Section("触发条件 (全部满足)") {
                    ForEach(available, id: \.self) { a in
                        Button(action: {
                            if selected.contains(a) { selected.remove(a) }
                            else { selected.insert(a) }
                        }) {
                            HStack {
                                Image(systemName: selected.contains(a) ? "checkmark.circle.fill" : "circle")
                                Text(a)
                                Spacer()
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
                Section("输出动作") {
                    TextField("动作名称", text: $rule.actionKey)
                }
                Section {
                    Button("保存") {
                        rule.requires = Array(selected).sorted()
                        onSave(rule)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty)
                }
            }
            .navigationTitle("编辑分支组合")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
    }
}

struct SequenceRuleEditView: View {
    @Environment(\.dismiss) var dismiss
    @State var rule: SequenceRule
    let available: [String]
    let onSave: (SequenceRule) -> Void
    @State private var editSteps: [String]

    init(rule: SequenceRule, available: [String], onSave: @escaping (SequenceRule) -> Void) {
        _rule = State(initialValue: rule)
        self.available = available
        self.onSave = onSave
        _editSteps = State(initialValue: rule.steps)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("规则名称") {
                    TextField("名称", text: $rule.name)
                }
                Section("输出动作") {
                    TextField("动作名称", text: $rule.actionKey)
                }
                Section("步骤顺序") {
                    ForEach(editSteps.indices, id: \.self) { i in
                        Picker("第 \(i+1) 步", selection: $editSteps[i]) {
                            ForEach(available, id: \.self) { a in
                                Text(a).tag(a)
                            }
                        }
                    }
                    .onDelete { editSteps.remove(atOffsets: $0) }
                    Button("添加步骤") { editSteps.append(available.first ?? "") }
                }
                Section("超时") {
                    Slider(value: $rule.timeout, in: 0.5...10, step: 0.5)
                    Text("两步之间超过 \(String(format: "%.0f", rule.timeout)) 秒未完成则重置")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section {
                    Button("保存") {
                        rule.steps = editSteps
                        onSave(rule)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(editSteps.count < 2)
                }
            }
            .navigationTitle("编辑顺序组合")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
    }
}

struct SequenceBuilderView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var camera: CameraManager
    @State private var name = ""
    @State private var actionKey = ""
    @State private var steps: [String] = []
    @State private var timeout: Double = 3.0
    let onSave: (SequenceRule) -> Void

    var availableActions: [String] {
        let body = camera.matcher.templates.map(\.actionKey)
        let hand = camera.handTemplates.map(\.actionKey)
        let face = camera.faceTemplates.map(\.actionKey)
        return Set(body + hand + face).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("规则名称") {
                    TextField("名称", text: $name)
                }
                Section("输出动作") {
                    TextField("如 combo_attack", text: $actionKey)
                }
                Section("步骤顺序") {
                    ForEach(steps.indices, id: \.self) { i in
                        Picker("第 \(i+1) 步", selection: $steps[i]) {
                            ForEach(availableActions, id: \.self) { a in
                                Text(a).tag(a)
                            }
                        }
                    }
                    .onDelete { steps.remove(atOffsets: $0) }
                    Button("添加步骤") { steps.append(availableActions.first ?? "") }
                }
                Section("超时") {
                    Slider(value: $timeout, in: 0.5...10, step: 0.5)
                    Text("两步之间超过 \(String(format: "%.0f", timeout)) 秒未完成则重置")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section {
                    Button("保存") {
                        guard !actionKey.isEmpty, steps.count >= 2 else { return }
                        let rule = SequenceRule(
                            id: UUID(),
                            name: name.isEmpty ? actionKey : name,
                            actionKey: actionKey,
                            steps: steps,
                            timeout: timeout
                        )
                        onSave(rule)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(actionKey.isEmpty || steps.count < 2)
                }
            }
            .navigationTitle("顺序规则")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }
}
