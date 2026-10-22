import Foundation

enum MirrorEngine: String, CaseIterable, Codable, Identifiable {
    case embedded
    case external

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .embedded: return "应用内镜像"
        case .external: return "兼容模式"
        }
    }
}

enum VideoCodecPreference: String, CaseIterable, Codable, Identifiable {
    case h264
    case h265

    var id: String { rawValue }
    var displayName: String { rawValue.uppercased() }
}

enum MirrorPresentation: String, CaseIterable, Codable, Identifiable {
    case embedded
    case floating
    case fullScreen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .embedded: return "内嵌"
        case .floating: return "悬浮"
        case .fullScreen: return "全屏"
        }
    }
}

enum MirrorSessionState: Equatable {
    case idle
    case preparing
    case connecting
    case streaming
    case reconnecting
    case stopping
    case failed(String)

    var isRunning: Bool {
        switch self {
        case .preparing, .connecting, .streaming, .reconnecting, .stopping:
            return true
        case .idle, .failed:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .idle: return "未启动"
        case .preparing: return "正在准备"
        case .connecting: return "正在连接"
        case .streaming: return "镜像中"
        case .reconnecting: return "正在恢复连接"
        case .stopping: return "正在停止"
        case .failed: return "连接失败"
        }
    }
}

enum AndroidControlEvent: Sendable {
    case key(AndroidKeyCode)
    case text(String)
    case touch(action: TouchAction, x: Int32, y: Int32, width: UInt16, height: UInt16)
    case scroll(x: Int32, y: Int32, width: UInt16, height: UInt16, horizontal: Float, vertical: Float)
    case setDisplayPower(Bool)
    case rotate
    case pasteClipboard(String)
}

enum TouchAction: UInt8, Sendable {
    case down = 0
    case up = 1
    case move = 2
    case cancel = 3
}

enum AndroidKeyCode: Int32, Sendable {
    case home = 3
    case back = 4
    case dpadUp = 19
    case dpadDown = 20
    case dpadLeft = 21
    case dpadRight = 22
    case dpadCenter = 23
    case volumeUp = 24
    case volumeDown = 25
    case power = 26
    case enter = 66
    case delete = 67
    case appSwitch = 187
    case wakeUp = 224
}

@MainActor
protocol MirrorSession: AnyObject {
    var state: MirrorSessionState { get }
    func start(device: AndroidDevice, settings: MirrorSettings, recordingURL: URL?) async throws
    func stop() async
    func send(_ event: AndroidControlEvent) async throws
}
