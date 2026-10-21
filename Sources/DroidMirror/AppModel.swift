import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var devices: [AndroidDevice] = []
    @Published var selectedDeviceID: String?
    @Published var settings = MirrorSettings()
    @Published private(set) var isRefreshing = false
    @Published private(set) var isConnecting = false
    @Published var message: String?

    let mirror = ScrcpyService()
    private var refreshTask: Task<Void, Never>?

    var selectedDevice: AndroidDevice? {
        devices.first { $0.id == selectedDeviceID }
    }

    init() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let latest = try await DeviceService.devices()
            devices = latest
            if selectedDeviceID == nil || !latest.contains(where: { $0.id == selectedDeviceID }) {
                selectedDeviceID = latest.first(where: { $0.state == .device })?.id ?? latest.first?.id
            }
        } catch {
            devices = []
            message = error.localizedDescription
        }
    }

    func connectWirelessly(to rawAddress: String) async -> Bool {
        let address = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            message = "请输入手机的 IP 地址和端口。"
            return false
        }

        isConnecting = true
        defer { isConnecting = false }
        do {
            message = try await DeviceService.connect(address: address)
            await refresh()
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func startMirror(recordingURL: URL? = nil) {
        guard let device = selectedDevice else {
            message = "请先连接并选择一台 Android 设备。"
            return
        }
        guard device.state == .device else {
            message = device.state == .unauthorized
                ? "请解锁手机，并允许这台 Mac 进行 USB 调试。"
                : "当前设备不可用，请重新连接。"
            return
        }
        do {
            try mirror.start(device: device, settings: settings, recordingURL: recordingURL)
        } catch {
            message = error.localizedDescription
        }
    }

    func dismissMessage() {
        message = nil
        mirror.clearError()
    }

    deinit {
        refreshTask?.cancel()
    }
}
