import Combine
import Foundation

@MainActor
final class MirrorCoordinator: ObservableObject {
    private static let showsControlsKey = "MirrorControlsVisible.v1"

    @Published private(set) var state: MirrorSessionState = .idle
    @Published private(set) var activeEngine: MirrorEngine?
    @Published private(set) var currentDevice: AndroidDevice?
    @Published var presentation: MirrorPresentation = .embedded
    @Published var showsControls: Bool {
        didSet {
            UserDefaults.standard.set(showsControls, forKey: Self.showsControlsKey)
            if activeEngine == .external, let currentDevice {
                external.setControlsVisible(showsControls, for: currentDevice)
            }
        }
    }
    @Published var lastError: String?
    @Published var notice: String?

    let embedded = EmbeddedScrcpySession()
    private let external = ScrcpyService()
    private var subscriptions: Set<AnyCancellable> = []

    var isRunning: Bool { state.isRunning }
    var renderer: VideoRenderer { embedded.renderer }
    var activeCodec: VideoCodecPreference { embedded.activeCodec }

    init() {
        showsControls = UserDefaults.standard.object(forKey: Self.showsControlsKey) as? Bool ?? true
        embedded.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] newState in
                guard let self, self.activeEngine == .embedded else { return }
                self.state = newState
                if case .failed(let message) = newState {
                    self.lastError = message
                    MirrorWindowController.shared.endSession()
                    AppLogger.shared.log("Mirror", "Embedded session failed: \(message)")
                }
            }
            .store(in: &subscriptions)

        embedded.$didFallbackCodec
            .dropFirst()
            .filter { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.notice = "该设备或电脑无法继续使用 H.265，已自动切换到 H.264。"
            }
            .store(in: &subscriptions)

        external.$isRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] running in
                guard let self, self.activeEngine == .external else { return }
                self.state = running ? .streaming : .idle
                if !running {
                    self.activeEngine = nil
                    self.currentDevice = nil
                }
            }
            .store(in: &subscriptions)

        external.$lastError
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                self?.lastError = message
                self?.state = .failed(message)
            }
            .store(in: &subscriptions)
    }

    func start(device: AndroidDevice, settings: MirrorSettings, recordingURL: URL? = nil) async throws {
        guard !isRunning else { throw ScrcpyServiceError.alreadyRunning }
        lastError = nil
        notice = nil
        currentDevice = device

        let engine: MirrorEngine = recordingURL == nil ? settings.engine : .external
        activeEngine = engine
        presentation = settings.presentation

        switch engine {
        case .embedded:
            do {
                try await embedded.start(device: device, settings: settings, recordingURL: nil)
                state = embedded.state
                if embedded.didFallbackCodec {
                    notice = "该设备无法启动 H.265，已自动切换到 H.264。"
                }
                showSelectedPresentation()
            } catch {
                activeEngine = nil
                currentDevice = nil
                state = .failed(error.localizedDescription)
                lastError = error.localizedDescription
                throw error
            }

        case .external:
            do {
                try external.start(
                    device: device,
                    settings: settings,
                    recordingURL: recordingURL,
                    showsControls: showsControls
                )
                state = .streaming
                if recordingURL != nil, settings.engine == .embedded {
                    notice = "录制期间使用 scrcpy 兼容模式，以保证 MP4 音视频同步。"
                }
            } catch {
                activeEngine = nil
                currentDevice = nil
                state = .failed(error.localizedDescription)
                lastError = error.localizedDescription
                throw error
            }
        }
    }

    func stop() async {
        guard activeEngine != nil else { return }
        state = .stopping
        MirrorWindowController.shared.endSession()
        if activeEngine == .embedded {
            await embedded.stop()
        } else {
            external.stop()
        }
        activeEngine = nil
        currentDevice = nil
        state = .idle
    }

    func send(_ event: AndroidControlEvent) async throws {
        guard let device = currentDevice else { throw TCPSocketError.closed }
        if case .key(.wakeUp) = event {
            if activeEngine == .embedded {
                try await embedded.send(.setDisplayPower(true))
                try await embedded.send(.key(.wakeUp))
            } else {
                try await DeviceService.send(.wakeUp, to: device)
            }
            return
        }
        if case .rotate = event {
            try await DeviceService.rotateDisplay(on: device)
            AppLogger.shared.log("Control", "Rotated display for \(device.serial)")
            return
        }
        if activeEngine == .embedded {
            try await embedded.send(event)
            return
        }

        guard case .key(let key) = event, let legacy = AndroidKeyEvent(key) else { return }
        try await DeviceService.send(legacy, to: device)
    }

    func captureScreenshot() async throws -> Data {
        guard let device = currentDevice else { throw TCPSocketError.closed }
        return try await DeviceService.captureScreenshot(from: device)
    }

    func changePresentation(to newValue: MirrorPresentation) {
        guard activeEngine == .embedded, isRunning else { return }
        presentation = newValue
        AppLogger.shared.log("Window", "Presentation changed to \(newValue.rawValue)")
        showSelectedPresentation()
    }

    func windowWasClosed() {
        guard activeEngine == .embedded, isRunning else { return }
        presentation = .embedded
    }

    func clearMessages() {
        lastError = nil
        notice = nil
        external.clearError()
    }

    func report(_ error: Error) {
        lastError = error.localizedDescription
        AppLogger.shared.log("Error", error.localizedDescription)
    }

    private func showSelectedPresentation() {
        switch presentation {
        case .embedded:
            MirrorWindowController.shared.hide()
        case .floating, .fullScreen:
            MirrorWindowController.shared.show(presentation: presentation, coordinator: self)
        }
    }
}

private extension AndroidKeyEvent {
    init?(_ key: AndroidKeyCode) {
        switch key {
        case .back: self = .back
        case .home: self = .home
        case .appSwitch: self = .appSwitch
        case .wakeUp: self = .wakeUp
        default: return nil
        }
    }
}
