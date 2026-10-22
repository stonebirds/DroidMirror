import AppKit
import SwiftUI

@MainActor
final class MirrorWindowController: NSObject, NSWindowDelegate {
    static let shared = MirrorWindowController()

    private var window: NSWindow?
    private weak var coordinator: MirrorCoordinator?
    private var desiredPresentation: MirrorPresentation = .embedded
    private var isFullScreenTransition = false
    private var shouldReleaseWhenSettled = false

    func show(presentation: MirrorPresentation, coordinator: MirrorCoordinator) {
        self.coordinator = coordinator
        desiredPresentation = presentation
        shouldReleaseWhenSettled = false
        ensureWindow(coordinator: coordinator)
        ensureWindowContent(coordinator: coordinator)
        applyDesiredPresentation()
    }

    func hide() {
        desiredPresentation = .embedded
        applyDesiredPresentation()
    }

    func endSession() {
        desiredPresentation = .embedded
        shouldReleaseWhenSettled = true
        applyDesiredPresentation()
    }

    private func ensureWindow(coordinator: MirrorCoordinator) {
        guard window == nil else { return }
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 760),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newWindow.isReleasedWhenClosed = false
        newWindow.title = coordinator.currentDevice?.name ?? "DroidMirror"
        newWindow.minSize = NSSize(width: 300, height: 480)
        newWindow.delegate = self
        newWindow.center()
        window = newWindow
    }

    private func ensureWindowContent(coordinator: MirrorCoordinator) {
        guard let window, window.contentView == nil else { return }
        window.title = coordinator.currentDevice?.name ?? "DroidMirror"
        window.contentView = NSHostingView(rootView: MirrorStageView(coordinator: coordinator))
    }

    private func applyDesiredPresentation() {
        guard let window, !isFullScreenTransition else { return }
        let isFullScreen = window.styleMask.contains(.fullScreen)

        switch desiredPresentation {
        case .embedded:
            if isFullScreen {
                isFullScreenTransition = true
                window.toggleFullScreen(nil)
            } else {
                window.orderOut(nil)
                window.contentView = nil
                releaseWindowIfNeeded()
            }

        case .floating:
            if isFullScreen {
                isFullScreenTransition = true
                window.toggleFullScreen(nil)
                return
            }
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.makeKeyAndOrderFront(nil)

        case .fullScreen:
            guard !isFullScreen else {
                window.makeKeyAndOrderFront(nil)
                return
            }
            window.level = .normal
            window.collectionBehavior = [.fullScreenPrimary]
            window.makeKeyAndOrderFront(nil)
            isFullScreenTransition = true
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.desiredPresentation == .fullScreen else {
                    self?.isFullScreenTransition = false
                    self?.applyDesiredPresentation()
                    return
                }
                window.toggleFullScreen(nil)
            }
        }
    }

    private func releaseWindowIfNeeded() {
        guard shouldReleaseWhenSettled, let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window,
                  self.shouldReleaseWhenSettled,
                  self.window === window else { return }
            window.delegate = nil
            window.contentView = nil
            self.window = nil
            self.coordinator = nil
            self.shouldReleaseWhenSettled = false
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        desiredPresentation = .embedded
        coordinator?.windowWasClosed()
        applyDesiredPresentation()
        return false
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        isFullScreenTransition = false
        applyDesiredPresentation()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        isFullScreenTransition = false
        applyDesiredPresentation()
    }
}

struct MirrorStageView: View {
    @ObservedObject var coordinator: MirrorCoordinator

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text(coordinator.currentDevice?.name ?? "Android")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(coordinator.activeCodec.displayName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    coordinator.showsControls.toggle()
                } label: {
                    Image(systemName: coordinator.showsControls ? "eye.slash" : "eye")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.borderless)
                .help(coordinator.showsControls ? "隐藏控制栏" : "显示控制栏")
                modeButton(.embedded, symbol: "rectangle.inset.filled")
                modeButton(.floating, symbol: "macwindow")
                modeButton(.fullScreen, symbol: "arrow.up.left.and.arrow.down.right")
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(.bar)

            MirrorSurfaceView(renderer: coordinator.renderer) { event in
                Task {
                    do {
                        try await coordinator.send(event)
                    } catch {
                        coordinator.report(error)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)

            if coordinator.showsControls {
                Divider()
                HStack(spacing: 6) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            HStack(spacing: 6) {
                                controlButton(.key(.back), symbol: "chevron.backward", help: "返回")
                                controlButton(.key(.appSwitch), symbol: "square.on.square", help: "最近任务")
                                controlButton(.key(.home), symbol: "circle", help: "返回桌面")
                                Button {
                                    saveScreenshot()
                                } label: {
                                    Image(systemName: "camera")
                                        .frame(width: 28, height: 24)
                                }
                                .buttonStyle(.borderless)
                                .help("保存截图")
                            }
                            Divider().frame(height: 22)
                            HStack(spacing: 6) {
                                controlButton(.key(.volumeDown), symbol: "speaker.minus", help: "降低音量")
                                controlButton(.key(.volumeUp), symbol: "speaker.plus", help: "提高音量")
                                controlButton(.rotate, symbol: "rotate.right", help: "旋转屏幕")
                                controlButton(.key(.power), symbol: "lock", help: "锁屏")
                                controlButton(.setDisplayPower(false), symbol: "display", help: "关闭手机屏幕")
                                controlButton(.key(.wakeUp), symbol: "sun.max", help: "唤醒手机")
                            }
                            Button {
                                if let value = NSPasteboard.general.string(forType: .string) {
                                    send(.pasteClipboard(value))
                                }
                            } label: {
                                Image(systemName: "doc.on.clipboard")
                                    .frame(width: 28, height: 24)
                            }
                            .buttonStyle(.borderless)
                            .help("粘贴 Mac 剪贴板")
                        }
                    }
                    Spacer(minLength: 4)
                    Button(role: .destructive) {
                        Task { await coordinator.stop() }
                    } label: {
                        Image(systemName: "stop.fill")
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .help("停止镜像")
                }
                .padding(.horizontal, 10)
                .frame(height: 46)
                .background(.bar)
            }
        }
    }

    private func modeButton(_ presentation: MirrorPresentation, symbol: String) -> some View {
        Button {
            coordinator.changePresentation(to: presentation)
        } label: {
            Image(systemName: symbol)
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(coordinator.presentation == presentation ? Color.accentColor : Color.secondary)
        .help(presentation.displayName)
    }

    private func controlButton(_ event: AndroidControlEvent, symbol: String, help: String) -> some View {
        Button { send(event) } label: {
            Image(systemName: symbol)
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func send(_ event: AndroidControlEvent) {
        Task {
            do {
                try await coordinator.send(event)
            } catch {
                coordinator.report(error)
            }
        }
    }

    private func saveScreenshot() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "DroidMirror-\(Self.timestamp()).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let data = try await coordinator.captureScreenshot()
                try data.write(to: url, options: .atomic)
            } catch {
                coordinator.report(error)
            }
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
