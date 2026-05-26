import Foundation
import Darwin

class UDPSender {
    private var socket_fd: Int32 = -1
    private var dest_addr = sockaddr_in()
    private var isReady = false

    var host = ""
    var port: UInt16 = 54321
    var isConnected = false

    var onStatusChange: ((Bool) -> Void)?

    func connect() {
        disconnect()

        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16HostToBig(port)

        if host.withCString({ cstr in
            inet_pton(AF_INET, cstr, &addr.sin_addr) == 1
        }) {
            socket_fd = fd
            dest_addr = addr
            isReady = true
            isConnected = true
            onStatusChange?(true)
        } else {
            close(fd)
        }
    }

    func disconnect() {
        if socket_fd >= 0 {
            close(socket_fd)
            socket_fd = -1
        }
        isReady = false
        isConnected = false
        onStatusChange?(false)
    }

    func send(landmarks: [Landmark], actions: [String], debugInfo: String = "") {
        guard isReady else { return }
        let points = landmarks.map { LandmarkPoint(n: $0.joint.rawValue, x: $0.x, y: $0.y, c: $0.confidence) }
        let data = PoseData(t: Date().timeIntervalSince1970, l: points, h: nil, f: nil, a: actions,
                            ab: actions, ah: nil, af: nil, d: debugInfo)
        sendData(data)
    }

    func send(result: DetectionResult, actions: [String],
              bodyActions: [String] = [], handActions: [String] = [], faceActions: [String] = []) {
        guard isReady else { return }

        let bodyPoints = result.body.map { LandmarkPoint(n: $0.joint.rawValue, x: $0.x, y: $0.y, c: $0.confidence) }

        var handDict: [String: [HandPoint]] = [:]
        for hand in result.hands {
            let pts = hand.joints.map { HandPoint(n: $0.n, x: $0.x, y: $0.y, c: $0.c) }
            handDict[hand.chirality.rawValue] = pts
        }

        let facePoints = result.face.map { FacePoint(n: $0.n.rawValue, x: $0.x, y: $0.y, c: $0.c) }

        let data = PoseData(
            t: Date().timeIntervalSince1970,
            l: bodyPoints,
            h: handDict.isEmpty ? nil : handDict,
            f: facePoints.isEmpty ? nil : facePoints,
            a: actions,
            ab: bodyActions.isEmpty ? nil : bodyActions,
            ah: handActions.isEmpty ? nil : handActions,
            af: faceActions.isEmpty ? nil : faceActions,
            d: result.debug
        )
        sendData(data)
    }

    private func sendData(_ data: PoseData) {
        guard let json = try? JSONEncoder().encode(data) else { return }
        json.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            _ = withUnsafePointer(to: dest_addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    sendto(socket_fd, base, json.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    func sendConfig(_ mappings: [String: ActionMapping], threshold: Double = 0.3,
                    bodyNames: [String] = [], handNames: [String] = [], faceNames: [String] = []) {
        guard isReady else { return }
        let packet = ConfigPacket(type: "config", mappings: mappings, threshold: threshold,
                                  ab: bodyNames.isEmpty ? nil : bodyNames,
                                  ah: handNames.isEmpty ? nil : handNames,
                                  af: faceNames.isEmpty ? nil : faceNames)
        guard let json = try? JSONEncoder().encode(packet) else { return }
        json.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            _ = withUnsafePointer(to: &dest_addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    sendto(socket_fd, base, json.count, 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}
