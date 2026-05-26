import SwiftUI
import Foundation
import CoreGraphics

let keyCodeMap: [String: CGKeyCode] = [
    "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5,
    "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45,
    "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17,
    "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
    "space": 49, "up": 126, "down": 125, "left": 123, "right": 124,
]

struct KeyMapping: Codable {
    var key: String
    var mode: String = "hold"
}

struct Config: Codable {
    var port: UInt16 = 54321
    var mappings: [String: KeyMapping] = [:]
}

struct LandmarkPoint: Codable {
    let n: String
    let x: Double
    let y: Double
    let c: Double
}

struct HandPoint: Codable {
    let n: String
    let x: Double
    let y: Double
    let c: Double
}

struct FacePoint: Codable {
    let n: String
    let x: Double
    let y: Double
    let c: Double
}

struct PoseData: Codable {
    let a: [String]
    let l: [LandmarkPoint]?
    let h: [String: [HandPoint]]?
    let f: [FacePoint]?
    let type: String?
    let d: String?
    let ab: [String]?
    let ah: [String]?
    let af: [String]?
}

struct RemoteConfigPacket: Codable {
    let type: String
    let mappings: [String: RemoteMapping]
    let threshold: Double?
    let ab: [String]?
    let ah: [String]?
    let af: [String]?
}

struct RemoteMapping: Codable {
    let key: String
    let mode: String
}

class KeyBridgeManager: ObservableObject {
    @Published var running = false
    @Published var error: String?
    @Published var log: [String] = []
    @Published var config: Config

    @Published var bodyCount = 0
    @Published var handLeft: [HandPoint] = []
    @Published var handRight: [HandPoint] = []
    @Published var faceCount = 0
    @Published var lastActions: [String] = []
    @Published var bodyActions: [String] = []
    @Published var handActions: [String] = []
    @Published var faceActions: [String] = []
    @Published var localIP: String = "获取中..."
    // 来自配置包的分类（不动），用于三栏展示
    @Published var configBody: [String] = []
    @Published var configHand: [String] = []
    @Published var configFace: [String] = []
    // 动作名 → 分类（body/hand/face），每次收到帧都覆盖更新
    var actionCategory: [String: String] = [:]

    private let configPath: String
    private var sock: Int32 = -1
    private var listenThread: Thread?
    private var previousActions = Set<String>()
    private var heldActions = Set<String>()
    private var toggledActions = Set<String>()
    private var autoPressTimes: [String: Date] = [:]
    var autoHoldThreshold: TimeInterval = 0.3

    init() {
        configPath = (NSString(string: "~/.keybridge.json").expandingTildeInPath)
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let c = try? JSONDecoder().decode(Config.self, from: data) {
            config = c
        } else {
            config = Config()
            save()
        }
        loadKnownCategories()
        localIP = Self.getLocalIP() ?? "未连接"
    }

    static let knownKey = "knownCategories"

    func loadKnownCategories() {
        guard let data = UserDefaults.standard.data(forKey: Self.knownKey) else { return }
        // 兼容旧格式 [String: [String]]，直接丢弃
        if (try? JSONDecoder().decode([String: [String]].self, from: data)) != nil {
            UserDefaults.standard.removeObject(forKey: Self.knownKey)
            return
        }
        if let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            actionCategory = dict
        }
    }

    func saveKnownCategories() {
        if let data = try? JSONEncoder().encode(actionCategory) {
            UserDefaults.standard.set(data, forKey: Self.knownKey)
        }
    }

    /// 获取本机局域网 IP（Wi-Fi / Ethernet）
    static func getLocalIP() -> String? {
        var addr: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        var ptr = first
        while true {
            let flags = Int32(ptr.pointee.ifa_flags)
            let name = String(cString: ptr.pointee.ifa_name)
            if (flags & IFF_UP) != 0 && (flags & IFF_LOOPBACK) == 0 &&
               ["en0", "en1"].contains(name) {
                var addrData = ptr.pointee.ifa_addr.pointee
                if addrData.sa_family == sa_family_t(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(&addrData, socklen_t(addrData.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, 0, NI_NUMERICHOST)
                    addr = String(cString: hostname)
                }
            }
            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }
        freeifaddrs(ifaddr)
        return addr
    }

    func save() {
        guard let data = try? JSONEncoder().encode(config),
              let _ = try? data.write(to: URL(fileURLWithPath: configPath))
        else { return }
    }

    func toggle() {
        if running { stop() } else { start() }
    }

    private func checkAccessibility() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        sock = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else { error = "创建 socket 失败"; return }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16HostToBig(config.port)
        addr.sin_addr.s_addr = INADDR_ANY
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard r == 0 else { error = "绑定端口 \(config.port) 失败"; Darwin.close(sock); sock = -1; return }

        running = true
        error = nil
        log = []
        appendLog("监听端口 \(config.port)")
        let trusted = checkAccessibility()
        appendLog(trusted ? "✔ 辅助功能已授权" : "✘ 辅助功能未授权 — 请在弹出窗口中允许，然后重启本 App")

        heldActions = []
        toggledActions = []
        autoPressTimes = [:]
        previousActions = []

        let ackJson = try! JSONEncoder().encode(["s": "ok"])
        listenThread = Thread { [weak self] in
            guard let self = self else { return }
            var buf = [UInt8](repeating: 0, count: 2048)
            var senderAddr = sockaddr_in()
            var totalPackets = 0
            while self.running {
                var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let n = withUnsafeMutablePointer(to: &senderAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { addrPtr in
                        recvfrom(self.sock, &buf, buf.count, 0, addrPtr, &addrLen)
                    }
                }
                guard n > 0 else { continue }

                // Send ack back to phone
                ackJson.withUnsafeBytes { ackPtr in
                    guard let ackBase = ackPtr.baseAddress else { return }
                    withUnsafePointer(to: senderAddr) { addrPtr in
                        let _ = addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                            sendto(self.sock, ackBase, ackJson.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
                totalPackets += 1
                let data = Data(bytes: buf, count: n)

                // Check if it's a config packet from phone
                if let configPacket = try? JSONDecoder().decode(RemoteConfigPacket.self, from: data),
                   configPacket.type == "config" {
                    var newMappings: [String: KeyMapping] = [:]
                    for (action, rm) in configPacket.mappings {
                        newMappings[action] = KeyMapping(key: rm.key, mode: rm.mode)
                    }
                    self.config.mappings = newMappings
                    if let t = configPacket.threshold {
                        self.autoHoldThreshold = t
                    }
                    // 从配置包中同步分类信息（所有动作名，不依赖当前帧）
                    DispatchQueue.main.async {
                        self.configBody = configPacket.ab ?? []
                        self.configHand = configPacket.ah ?? []
                        self.configFace = configPacket.af ?? []
                    }
                    if let ba = configPacket.ab {
                        for a in ba { self.actionCategory[a] = "body" }
                    }
                    if let ha = configPacket.ah {
                        for a in ha { self.actionCategory[a] = "hand" }
                    }
                    if let fa = configPacket.af {
                        for a in fa { self.actionCategory[a] = "face" }
                    }
                    self.save()
                    self.saveKnownCategories()
                    self.appendLog("收到配置: \(newMappings.count) 个映射, body=\(configPacket.ab ?? [])")
                    continue
                }

                guard let pose = try? JSONDecoder().decode(PoseData.self, from: data) else { continue }

                // 更新展示数据
                DispatchQueue.main.async {
                    self.bodyCount = pose.l?.count ?? 0
                    self.handLeft = pose.h?["left"] ?? []
                    self.handRight = pose.h?["right"] ?? []
                    self.faceCount = pose.f?.count ?? 0
                    self.lastActions = pose.a

                    let ba = pose.ab ?? (pose.ah == nil && pose.af == nil ? pose.a : [])
                    let ha = pose.ah ?? []
                    let fa = pose.af ?? []
                    self.bodyActions = ba
                    self.handActions = ha
                    self.faceActions = fa
                    // 按最新帧覆盖分类，排除心跳 "connected"
                    let before = self.actionCategory.count
                    for a in ba where a != "connected" { self.actionCategory[a] = "body" }
                    for a in ha where a != "connected" { self.actionCategory[a] = "hand" }
                    for a in fa where a != "connected" { self.actionCategory[a] = "face" }
                    if self.actionCategory.count != before {
                        self.saveKnownCategories()
                    }
                }

                let actions = Set(pose.a).intersection(self.config.mappings.keys)
                let started = actions.subtracting(self.previousActions)
                let ended = self.previousActions.subtracting(actions)

                for action in started {
                    guard let m = self.config.mappings[action],
                          let parsed = self.parseKeySpec(m.key) else { continue }
                    let code = parsed.key
                    let flags = parsed.flags
                    switch m.mode {
                    case "tap":
                        if flags != [] { postKey(code, down: true, flags: flags) }
                        else { postKey(code, down: true) }
                        postKey(code, down: false)
                    case "toggle":
                        if self.toggledActions.contains(action) {
                            postKey(code, down: false)
                            self.toggledActions.remove(action)
                        } else {
                            if flags != [] { postKey(code, down: true, flags: flags) }
                            else { postKey(code, down: true) }
                            self.toggledActions.insert(action)
                        }
                    case "release":
                        break
                    case "auto":
                        if flags != [] { postKey(code, down: true, flags: flags) }
                        else { postKey(code, down: true) }
                        self.autoPressTimes[action] = Date()
                    default:
                        if flags != [] { postKey(code, down: true, flags: flags) }
                        else { postKey(code, down: true) }
                        self.heldActions.insert(action)
                    }
                }

                for action in ended {
                    guard let m = self.config.mappings[action],
                          let parsed = self.parseKeySpec(m.key) else { continue }
                    let code = parsed.key
                    if m.mode == "release" {
                        if parsed.flags != [] { postKey(code, down: true, flags: parsed.flags) }
                        else { postKey(code, down: true) }
                        postKey(code, down: false)
                    } else if m.mode == "auto" {
                        if let start = self.autoPressTimes[action],
                           Date().timeIntervalSince(start) < self.autoHoldThreshold {
                            postKey(code, down: false)
                        }
                        self.autoPressTimes.removeValue(forKey: action)
                    }
                }

                // Auto mode: promote long holds to hold behavior
                for (action, startTime) in self.autoPressTimes {
                    if Date().timeIntervalSince(startTime) >= self.autoHoldThreshold {
                        self.autoPressTimes.removeValue(forKey: action)
                        self.heldActions.insert(action)
                    }
                }

                // Recalculate which hold keys are still active
                var stillHeld = Set<String>()
                for action in actions {
                    guard let m = self.config.mappings[action],
                          self.parseKeySpec(m.key) != nil else { continue }
                    if m.mode == "hold" || m.mode == "auto" { stillHeld.insert(action) }
                }
                for action in self.heldActions.subtracting(stillHeld) {
                    if let m = self.config.mappings[action],
                       let parsed = self.parseKeySpec(m.key) {
                        postKey(parsed.key, down: false)
                    }
                }
                self.heldActions = stillHeld

                if actions != self.previousActions {
                    self.appendLog("\(actions.sorted())")
                }
                self.previousActions = actions
            }
            Darwin.close(self.sock)
            self.sock = -1
        }
        listenThread?.start()
    }

    func stop() {
        running = false
        listenThread?.cancel()
        listenThread = nil
        for action in heldActions {
            if let m = config.mappings[action],
               let parsed = parseKeySpec(m.key) {
                postKey(parsed.key, down: false)
            }
        }
        for action in toggledActions {
            if let m = config.mappings[action],
               let parsed = parseKeySpec(m.key) {
                postKey(parsed.key, down: false)
            }
        }
        heldActions = []
        toggledActions = []
        autoPressTimes = [:]
        appendLog("已停止")
    }

    func revealConfig() {
        NSWorkspace.shared.selectFile(configPath, inFileViewerRootedAtPath: "")
    }

    private func appendLog(_ s: String) {
        DispatchQueue.main.async {
            self.log.append(s)
            if self.log.count > 100 { self.log.removeFirst(self.log.count - 100) }
        }
    }

    private func postKey(_ code: CGKeyCode, down: Bool, flags: CGEventFlags = []) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    func parseKeySpec(_ spec: String) -> (key: CGKeyCode, flags: CGEventFlags)? {
        let parts = spec.split(separator: "+").map(String.init)
        guard !parts.isEmpty else { return nil }
        var flags = CGEventFlags()
        let keyPart: String
        if parts.count > 1 {
            keyPart = parts.last!.lowercased()
            for mod in parts.dropLast() {
                switch mod.lowercased() {
                case "ctrl", "ctl": flags.insert(.maskControl)
                case "alt", "option": flags.insert(.maskAlternate)
                case "shift": flags.insert(.maskShift)
                case "cmd", "command": flags.insert(.maskCommand)
                default: break
                }
            }
        } else {
            keyPart = parts[0].lowercased()
        }
        guard let code = keyCodeMap[keyPart] else { return nil }
        return (code, flags)
    }
}
