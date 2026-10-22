import AppKit
import SwiftUI

@MainActor
final class MirrorWindowController: NSObject, NSWindowDelegate {
    static let shared = MirrorWindowController()

    private var window: NSWindow?
    private weak var coordinator: MirrorCoordinator?
    private var isProgrammaticClose = false

    func show(presentation: MirrorPresentation, coordinator: MirrorCoordinator) {
        hide()
        self.coordinator = coordinator

        let content = NSHostingView(rootView: MirrorStageView(coordinator: coordinator))
        let newWindow: NSWindow
        switch presentation {
        case .floating:
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 430, height: 760),
                styleMask: [.titled, .closable, .resizable, .miniaturizable, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.title = coordinator.currentDevice?.name ?? "DroidMirror"
            newWindow = panel

        case .fullScreen:
            let fullScreenWindow = NSWindow(
                contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            fullScreenWindow.title = coordinator.currentDevice?.name ?? "DroidMirror"
            fullScreenWindow.collectionBehavior = [.fullScreenPrimary]
            newWindow = fullScreenWindow

        case .embedded:
            return
        }

        newWindow.contentView = content
        newWindow.minSize = NSSize(width: 300, height: 480)
        newWindow.delegate = self
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        window = newWindow

        if presentation == .fullScreen {
            DispatchQueue.main.async { [weak newWindow] in
                newWindow?.toggleFullScreen(nil)
            }
        }
    }

    func hide() {
        guard let window else { return }
        isProgrammaticClose = true
        window.delegate = nil
        window.orderOut(nil)
        window.close()
        self.window = nil
        isProgrammaticClose = false
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        guard !isProgrammaticClose else { return }
        coordinator?.windowWasClosed()
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

            Divider()
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        HStack(spacing: 6) {
                            controlButton(.key(.back), symbol: "chevron.backward", help: "返回")
                            controlButton(.key(.home), symbol: "circle", help: "桌面")
                            controlButton(.key(.appSwitch), symbol: "square.on.square", help: "最近任务")
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
                        HStack(spacing: 6) {
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
                            Button {
                                saveScreenshot()
                            } label: {
                                Image(systemName: "camera")
                                    .frame(width: 28, height: 24)
                            }
                            .buttonStyle(.borderless)
                            .help("保存截图")
                        }
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
