import Foundation

enum BodyJoint: String, Codable, CaseIterable {
    case nose, leftEye, rightEye, leftEar, rightEar
    case neck, root
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
}

struct Landmark: Codable {
    let joint: BodyJoint
    let x: Double
    let y: Double
    let confidence: Double
}

// MARK: - 手部 21 点
enum HandJoint: String, Codable, CaseIterable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip
}

enum HandChirality: String, Codable {
    case left, right
}

struct HandLandmark: Codable {
    let chirality: HandChirality
    let joints: [HandJointPoint]
}

struct HandJointPoint: Codable {
    let n: String
    let x: Double
    let y: Double
    let c: Double
}

// MARK: - 面部关键点
enum FaceLandmarkKey: String, Codable {
    case leftEye, rightEye
    case noseTip
    case mouthLeft, mouthRight
    case leftEyebrow, rightEyebrow
    case leftEar, rightEar
}

struct FaceLandmark: Codable {
    let n: FaceLandmarkKey
    let x: Double
    let y: Double
    let c: Double
}

struct PoseData: Codable {
    let t: Double
    let l: [LandmarkPoint]
    let h: [String: [HandPoint]]?
    let f: [FacePoint]?
    let a: [String]       // 合并后的全部动作
    let ab: [String]?     // 身体动作
    let ah: [String]?     // 手势动作
    let af: [String]?     // 脸部动作
    let d: String
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

struct ActionMapping: Codable {
    var key: String
    var mode: String = "hold"
    var enabled: Bool = true
}

struct ConfigPacket: Codable {
    let type: String
    let mappings: [String: ActionMapping]
    let threshold: Double?
    let ab: [String]?   // 全部身体动作名
    let ah: [String]?   // 全部手势动作名
    let af: [String]?   // 全部脸部动作名
}

struct LandmarkPoint: Codable {
    let n: String
    let x: Double
    let y: Double
    let c: Double
}

struct PoseTemplate: Identifiable, Codable {
    let id: UUID
    var name: String
    var actionKey: String
    var joints: [String: [Double]]
    var baseJoints: [String: [Double]]?  // 放松姿势关节角度（手势用）
    var threshold: Double
    var keyboardKey: String = ""
    var pressMode: String = "auto"
}

let pressModeNames: [(String, String)] = [
    ("auto", "智能 — 放松→动作→放松=点按，放松→动作并持续=按住"),
    ("tap", "点按 — 识别到即按下并释放"),
    ("hold", "按住 — 识别到即按住，松开姿势才释放"),
    ("release", "松开 — 姿势从有到无触发点击"),
    ("toggle", "开关 — 每次识别切换状态"),
]

struct CombinationRule: Identifiable, Codable {
    let id: UUID
    var name: String
    var actionKey: String
    var requires: [String]
}

struct SequenceRule: Identifiable, Codable {
    let id: UUID
    var name: String
    var actionKey: String
    var steps: [String]
    var timeout: Double = 3.0
}


struct SkeletonConnection: Hashable {
    let from: BodyJoint
    let to: BodyJoint
}

let handSkeletonConnections: [(String, String)] = [
    ("wrist", "thumbCMC"),
    ("thumbCMC", "thumbMP"),
    ("thumbMP", "thumbIP"),
    ("thumbIP", "thumbTip"),
    ("wrist", "indexMCP"),
    ("indexMCP", "indexPIP"),
    ("indexPIP", "indexDIP"),
    ("indexDIP", "indexTip"),
    ("wrist", "middleMCP"),
    ("middleMCP", "middlePIP"),
    ("middlePIP", "middleDIP"),
    ("middleDIP", "middleTip"),
    ("wrist", "ringMCP"),
    ("ringMCP", "ringPIP"),
    ("ringPIP", "ringDIP"),
    ("ringDIP", "ringTip"),
    ("wrist", "littleMCP"),
    ("littleMCP", "littlePIP"),
    ("littlePIP", "littleDIP"),
    ("littleDIP", "littleTip"),
]

let skeletonConnections: [SkeletonConnection] = [
    .init(from: .leftEar, to: .leftEye),
    .init(from: .leftEye, to: .nose),
    .init(from: .rightEar, to: .rightEye),
    .init(from: .rightEye, to: .nose),
    .init(from: .nose, to: .neck),
    .init(from: .neck, to: .leftShoulder),
    .init(from: .neck, to: .rightShoulder),
    .init(from: .neck, to: .root),
    .init(from: .root, to: .leftHip),
    .init(from: .root, to: .rightHip),
    .init(from: .leftShoulder, to: .leftElbow),
    .init(from: .leftElbow, to: .leftWrist),
    .init(from: .rightShoulder, to: .rightElbow),
    .init(from: .rightElbow, to: .rightWrist),
    .init(from: .leftHip, to: .leftKnee),
    .init(from: .leftKnee, to: .leftAnkle),
    .init(from: .rightHip, to: .rightKnee),
    .init(from: .rightKnee, to: .rightAnkle),
]
