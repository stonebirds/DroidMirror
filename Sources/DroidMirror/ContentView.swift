import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsWirelessSheet = false
    @State private var selectedADBPath = ToolLocator.customADBURL?.path ?? ""

    var body: some View {
        NavigationSplitView {
            deviceSidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("刷新设备", systemImage: "arrow.clockwise")
                }
                .help("刷新设备")
                .disabled(model.isRefreshing)

                Button {
                    showsWirelessSheet = true
                } label: {
                    Label("无线连接", systemImage: "wifi")
                }
                .help("通过 IP 地址连接")
            }
        }
        .sheet(isPresented: $showsWirelessSheet) {
            WirelessConnectionView(isPresented: $showsWirelessSheet)
                .environmentObject(model)
        }
        .alert("DroidMirror", isPresented: Binding(
            get: { model.message != nil },
            set: { if !$0 { model.dismissMessage() } }
        )) {
            Button("好") { model.dismissMessage() }
        } message: {
            Text(model.message ?? "")
        }
    }

    private var deviceSidebar: some View {
        VStack(spacing: 0) {
            List(selection: $model.selectedDeviceID) {
                Section("Android 设备") {
                    ForEach(model.devices) { device in
                        DeviceRow(device: device)
                            .tag(device.id)
                    }
                }
            }
            .listStyle(.sidebar)

            if model.devices.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "cable.connector")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("未发现设备")
                        .font(.headline)
                    Text("连接 USB 并在手机上开启 USB 调试")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                ToolStatusRow(
                    isAvailable: ToolLocator.executable(named: "scrcpy") != nil,
                    availableText: "scrcpy 已就绪",
                    missingText: "scrcpy 未找到"
                )
                HStack(spacing: 8) {
                    ToolStatusRow(
                        isAvailable: ToolLocator.executable(named: "adb") != nil,
                        availableText: "adb 已就绪",
                        missingText: "adb 未找到"
                    )
                    Button {
                        chooseADB()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("选择 adb 可执行文件")
                }
                if !selectedADBPath.isEmpty {
                    Text(selectedADBPath)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(selectedADBPath)
                }
                Text("DroidMirror v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
        }
    }

    private func chooseADB() {
        let panel = NSOpenPanel()
        panel.title = "选择 adb 可执行文件"
        panel.message = "请选择 Android SDK platform-tools 文件夹中的 adb。"
        panel.prompt = "选择"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            model.message = "所选文件不可执行，请选择 platform-tools 文件夹中的 adb。"
            return
        }
        ToolLocator.setCustomADB(url)
        selectedADBPath = url.path
        Task { await model.refresh() }
    }

    @ViewBuilder
    private var detail: some View {
        if let device = model.selectedDevice {
            DeviceDetailView(mirror: model.mirror, device: device)
                .environmentObject(model)
        } else {
            SetupGuideView()
        }
    }
}

private struct ToolStatusRow: View {
    let isAvailable: Bool
    let availableText: String
    let missingText: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isAvailable ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(isAvailable ? availableText : missingText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

private struct DeviceRow: View {
    let device: AndroidDevice

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.isWireless ? "wifi" : "iphone.gen3")
                .frame(width: 20)
                .foregroundStyle(device.state == .device ? Color.accentColor : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .lineLimit(1)
                Text(device.state.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct DeviceDetailView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var mirror: ScrcpyService
    let device: AndroidDevice

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 52, height: 52)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.title2.weight(.semibold))
                    HStack(spacing: 6) {
                        Circle()
                            .fill(device.state == .device ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(device.state.displayName)
                        Text("·")
                        Text(device.isWireless ? "无线" : "USB")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)

            Divider()

            Form {
                Section("画面") {
                    Picker("最大分辨率", selection: $model.settings.maxSize) {
                        Text("1280p").tag(1280)
                        Text("1920p").tag(1920)
                        Text("2560p").tag(2560)
                    }
                    Picker("视频码率", selection: $model.settings.bitRateMbps) {
                        Text("4 Mbps").tag(4)
                        Text("8 Mbps").tag(8)
                        Text("16 Mbps").tag(16)
                    }
                    Picker("最大帧率", selection: $model.settings.maxFPS) {
                        Text("30 FPS").tag(30)
                        Text("60 FPS").tag(60)
                        Text("90 FPS").tag(90)
                    }
                }

                Section("设备") {
                    Toggle("传输手机音频", isOn: $model.settings.audioEnabled)
                    Toggle("镜像时关闭手机屏幕", isOn: $model.settings.turnScreenOff)
                    Toggle("连接期间保持手机唤醒", isOn: $model.settings.stayAwake)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if model.mirror.isRunning {
                    HStack(spacing: 6) {
                        navigationButton(event: .back, symbol: "chevron.backward", help: "返回")
                        navigationButton(event: .home, symbol: "circle", help: "返回桌面")
                        navigationButton(event: .appSwitch, symbol: "square.on.square", help: "最近任务")
                    }
                } else {
                    Button {
                        chooseRecordingLocation()
                    } label: {
                        Label("录制并镜像", systemImage: "record.circle")
                    }
                    .disabled(device.state != .device)
                }

                Spacer()

                if model.mirror.isRunning {
                    Button(role: .destructive) {
                        model.mirror.stop()
                    } label: {
                        Label("停止镜像", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        model.startMirror()
                    } label: {
                        Label("开始镜像", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(device.state != .device)
                }
            }
            .padding(20)
        }
        .alert("镜像已停止", isPresented: Binding(
            get: { mirror.lastError != nil },
            set: { if !$0 { mirror.clearError() } }
        )) {
            Button("好") { mirror.clearError() }
        } message: {
            Text(mirror.lastError ?? "")
        }
    }

    private func chooseRecordingLocation() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "DroidMirror-\(formattedTimestamp()).mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.startMirror(recordingURL: url)
    }

    private func navigationButton(
        event: AndroidKeyEvent,
        symbol: String,
        help: String
    ) -> some View {
        Button {
            Task {
                do {
                    try await DeviceService.send(event, to: device)
                } catch {
                    model.message = error.localizedDescription
                }
            }
        } label: {
            Image(systemName: symbol)
                .frame(width: 24, height: 18)
        }
        .buttonStyle(.bordered)
        .help(help)
    }

    private func formattedTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

private struct SetupGuideView: View {
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "rectangle.connected.to.line.below")
                .font(.system(size: 54))
                .foregroundStyle(Color.accentColor)
            Text("连接 Android 手机")
                .font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 14) {
                GuideStep(number: 1, text: "在手机设置中开启开发者选项和 USB 调试")
                GuideStep(number: 2, text: "使用数据线连接手机与 Mac")
                GuideStep(number: 3, text: "解锁手机并允许 USB 调试授权")
            }
            .frame(maxWidth: 390)
        }
        .padding(40)
    }
}

private struct GuideStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(String(number))
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor, in: Circle())
            Text(text)
            Spacer()
        }
    }
}

private struct WirelessConnectionView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var address = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "wifi")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text("无线连接")
                    .font(.title2.weight(.semibold))
            }
            Text("输入 Android 无线调试页面显示的 IP 地址和端口。手机与 Mac 必须处于同一网络。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("例如 192.168.1.20:37123", text: $address)
                .textFieldStyle(.roundedBorder)
                .onSubmit { connect() }
            HStack {
                Button("取消") { isPresented = false }
                Spacer()
                Button {
                    connect()
                } label: {
                    if model.isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("连接")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isConnecting)
            }
        }
        .padding(24)
        .frame(width: 430)
    }

    private func connect() {
        Task {
            if await model.connectWirelessly(to: address) {
                isPresented = false
            }
        }
    }
}
