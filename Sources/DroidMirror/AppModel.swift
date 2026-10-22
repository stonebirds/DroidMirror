import Foundation

@MainActor
final class AppModel: ObservableObject {
    private static let settingsKey = "MirrorSettings.v2"

    @Published private(set) var devices: [AndroidDevice] = []
    @Published private(set) var recentDevices = DeviceHistoryStore.load()
    @Published var selectedDeviceID: String?
    @Published var settings: MirrorSettings {
        didSet {
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: Self.settingsKey)
            }
        }
    }
    @Published private(set) var isRefreshing = false
    @Published private(set) var isConnecting = false
    @Published private(set) var isSwitchingWireless = false
    @Published private(set) var isInstallingAPK = false
    @Published var message: String?

    let mirror = MirrorCoordinator()
    private var refreshTask: Task<Void, Never>?

    var selectedDevice: AndroidDevice? {
        devices.first { $0.id == selectedDeviceID }
    }

    var offlineRecentDevices: [RecentDevice] {
        let currentSerials = Set(devices.map(\.serial))
        return recentDevices.filter { !currentSerials.contains($0.serial) }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(MirrorSettings.self, from: data) {
            settings = saved
        } else {
            settings = MirrorSettings()
        }
        AppLogger.shared.log("App", "DroidMirror started")
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
            let previouslyConnected = Set(devices.filter { $0.state == .device }.map(\.serial))
            let newlyConnected = latest.filter {
                $0.state == .device && !previouslyConnected.contains($0.serial)
            }
            if !newlyConnected.isEmpty {
                recentDevices = DeviceHistoryStore.record(newlyConnected, in: recentDevices)
                AppLogger.shared.log(
                    "Device",
                    "Connected: \(newlyConnected.map(\.serial).joined(separator: ", "))"
                )
            }
            devices = latest
            if selectedDeviceID == nil || !latest.contains(where: { $0.id == selectedDeviceID }) {
                selectedDeviceID = latest.first(where: { $0.state == .device })?.id ?? latest.first?.id
            }
        } catch {
            message = error.localizedDescription
            AppLogger.shared.log("Device", "Refresh failed: \(error.localizedDescription)")
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
            selectedDeviceID = address
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
        Task {
            do {
                try await mirror.start(device: device, settings: settings, recordingURL: recordingURL)
                recentDevices = DeviceHistoryStore.record([device], in: recentDevices)
                AppLogger.shared.log("Mirror", "Started \(device.serial)")
            } catch {
                message = error.localizedDescription
                AppLogger.shared.log("Mirror", "Start failed: \(error.localizedDescription)")
            }
        }
    }

    func stopMirror() {
        Task {
            await mirror.stop()
            AppLogger.shared.log("Mirror", "Stopped")
        }
    }

    func installAPK(from url: URL) async -> Bool {
        guard let device = selectedDevice, device.state == .device else {
            message = "请先连接并选择一台可用的 Android 设备。"
            return false
        }
        guard !isInstallingAPK else { return false }

        isInstallingAPK = true
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
            isInstallingAPK = false
        }
        AppLogger.shared.log("APK", "Installing \(url.lastPathComponent) on \(device.serial)")
        do {
            _ = try await DeviceService.installAPK(at: url, on: device)
            message = "\(url.lastPathComponent) 安装成功。"
            AppLogger.shared.log("APK", "Installed \(url.lastPathComponent)")
            return true
        } catch {
            message = error.localizedDescription
            AppLogger.shared.log("APK", "Install failed: \(error.localizedDescription)")
            return false
        }
    }

    func reconnect(_ recentDevice: RecentDevice) async {
        guard recentDevice.isWireless else {
            message = "请通过 USB 数据线重新连接 \(recentDevice.name)。"
            return
        }
        _ = await connectWirelessly(to: recentDevice.serial)
    }

    func forget(_ recentDevice: RecentDevice) {
        recentDevices = DeviceHistoryStore.remove(serial: recentDevice.serial, from: recentDevices)
        AppLogger.shared.log("Device", "Forgot history for \(recentDevice.serial)")
    }

    func enableWirelessFromUSB() async -> Bool {
        guard let device = selectedDevice else {
            message = "请先选择一台 USB 设备。"
            return false
        }
        isSwitchingWireless = true
        defer { isSwitchingWireless = false }
        do {
            let result = try await DeviceService.enableWirelessADB(for: device)
            message = "\(result.message) 可以拔掉 USB 数据线。"
            await refresh()
            selectedDeviceID = result.address
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func disableWirelessADB() async -> Bool {
        guard let device = selectedDevice else {
            message = "请先选择无线设备。"
            return false
        }
        isSwitchingWireless = true
        defer { isSwitchingWireless = false }
        do {
            message = try await DeviceService.disableWirelessADB(for: device)
            await refresh()
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func dismissMessage() {
        message = nil
        mirror.clearMessages()
    }

    deinit {
        refreshTask?.cancel()
    }
}
