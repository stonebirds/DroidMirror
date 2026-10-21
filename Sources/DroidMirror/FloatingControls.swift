import AppKit
import SwiftUI

@MainActor
final class FloatingControlsController {
    static let shared = FloatingControlsController()

    private var panel: NSPanel?

    func show(for device: AndroidDevice) {
        hide()

        let size = NSSize(width: 176, height: 52)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: FloatingControlsView(device: device))

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.maxX - size.width - 24,
                y: frame.maxY - size.height - 24
            ))
        } else {
            panel.center()
        }

        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct FloatingControlsView: View {
    let device: AndroidDevice

    var body: some View {
        HStack(spacing: 6) {
            controlButton(event: .back, symbol: "chevron.backward", help: "返回")
            controlButton(event: .home, symbol: "circle", help: "返回桌面")
            controlButton(event: .appSwitch, symbol: "square.on.square", help: "最近任务")
        }
        .padding(6)
        .frame(width: 176, height: 52)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator.opacity(0.7), lineWidth: 1)
        }
    }

    private func controlButton(
        event: AndroidKeyEvent,
        symbol: String,
        help: String
    ) -> some View {
        Button {
            Task {
                do {
                    try await DeviceService.send(event, to: device)
                } catch {
                    NSSound.beep()
                }
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
