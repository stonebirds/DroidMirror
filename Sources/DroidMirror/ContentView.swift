import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsWirelessSheet = false
    @State private var showsLogSheet = false
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
                .help("无线连接或 USB 转无线")

                Button {
                    exportDiagnostics()
                } label: {
                    Label("导出诊断", systemImage: "stethoscope")
                }
                .help("导出诊断信息")

                Button {
                    showsLogSheet = true
                } label: {
                    Label("运行日志", systemImage: "text.alignleft")
                }
                .help("查看运行日志")
            }
        }
        .sheet(isPresented: $showsWirelessSheet) {
            WirelessConnectionView(isPresented: $showsWirelessSheet)
                .environmentObject(model)
        }
        .sheet(isPresented: $showsLogSheet) {
            LogViewer(isPresented: $showsLogSheet)
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
                if !model.offlineRecentDevices.isEmpty {
                    Section("最近连接") {
                        ForEach(model.offlineRecentDevices) { device in
                            RecentDeviceRow(device: device)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Task { await model.reconnect(device) }
                                }
                                .contextMenu {
                                    Button("删除记录", role: .destructive) {
                                        model.forget(device)
                                    }
                                }
                        }
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

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "DroidMirror-diagnostics.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let report = await DiagnosticsService.report(model: model)
                try report.write(to: url, atomically: true, encoding: .utf8)
                model.message = "诊断信息已导出。"
            } catch {
                model.message = error.localizedDescription
            }
        }
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

private struct RecentDeviceRow: View {
    let device: RecentDevice

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.isWireless ? "wifi" : "iphone.gen3")
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .lineLimit(1)
                Text(device.lastConnectedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if device.isWireless {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .help(device.isWireless ? "重新连接 \(device.serial)" : "等待 USB 重新连接")
    }
}

private struct DeviceDetailView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var mirror: MirrorCoordinator
    let device: AndroidDevice
    @State private var isAPKDropTarget = false
    @State private var pendingAPKURL: URL?
    @State private var showsAPKConfirmation = false

    var body: some View {
        Group {
            if mirror.activeEngine == .embedded,
               mirror.isRunning,
               mirror.presentation == .embedded {
                MirrorStageView(coordinator: mirror)
            } else {
                configurationView
            }
        }
        .alert("DroidMirror", isPresented: Binding(
            get: { mirror.lastError != nil },
            set: { if !$0 { mirror.clearMessages() } }
        )) {
            Button("好") { mirror.clearMessages() }
        } message: {
            Text(mirror.lastError ?? "")
        }
        .sheet(isPresented: $showsAPKConfirmation) {
            APKInstallConfirmationView(
                device: device,
                selectedURL: $pendingAPKURL,
                isPresented: $showsAPKConfirmation
            )
            .environmentObject(model)
        }
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $isAPKDropTarget,
            perform: acceptAPKDrop
        )
        .overlay {
            if isAPKDropTarget {
                ZStack {
                    Color.accentColor.opacity(0.12)
                    Label("安装 APK", systemImage: "shippingbox.and.arrow.backward")
                        .font(.title2.weight(.semibold))
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .allowsHitTesting(false)
            }
        }
    }

    private var configurationView: some View {
        VStack(spacing: 0) {
            deviceHeader
            Divider()

            if mirror.isRunning {
                runningSummary
            } else {
                settingsForm
            }

            if let notice = mirror.notice {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                    Text(notice)
                        .font(.caption)
                    Spacer()
                    Button {
                        mirror.notice = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.quaternary)
            }

            Divider()
            actionBar
        }
    }

    private var deviceHeader: some View {
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
            Button {
                pendingAPKURL = nil
                showsAPKConfirmation = true
            } label: {
                if model.isInstallingAPK {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("安装 APK", systemImage: "shippingbox.and.arrow.backward")
                }
            }
            .disabled(device.state != .device || model.isInstallingAPK)
            .help("选择或拖放 Android APK 安装包")
        }
        .padding(24)
    }

    private var settingsForm: some View {
        Form {
            Section("镜像") {
                Picker("镜像引擎", selection: $model.settings.engine) {
                    ForEach(MirrorEngine.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                Picker("视频编码", selection: $model.settings.videoCodec) {
                    ForEach(VideoCodecPreference.allCases) { codec in
                        Text(codec.displayName).tag(codec)
                    }
                }
                Picker("打开方式", selection: $model.settings.presentation) {
                    ForEach(MirrorPresentation.allCases) { presentation in
                        Text(presentation.displayName).tag(presentation)
                    }
                }
                .disabled(model.settings.engine == .external)
            }

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
                Toggle("显示镜像控制栏", isOn: $mirror.showsControls)
            }
        }
        .formStyle(.grouped)
    }

    private var runningSummary: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: mirror.activeEngine == .embedded ? "rectangle.inset.filled" : "macwindow")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            Text(mirror.state.displayName)
                .font(.title2.weight(.semibold))
            Text(mirror.activeEngine?.displayName ?? "")
                .foregroundStyle(.secondary)
            if mirror.activeEngine == .embedded {
                HStack(spacing: 10) {
                    ForEach(MirrorPresentation.allCases) { presentation in
                        Button {
                            mirror.changePresentation(to: presentation)
                        } label: {
                            Text(presentation.displayName)
                                .frame(minWidth: 56)
                        }
                        .buttonStyle(.bordered)
                        .tint(mirror.presentation == presentation ? Color.accentColor : nil)
                    }
                }
            }
            Button {
                mirror.showsControls.toggle()
            } label: {
                Label(
                    mirror.showsControls ? "隐藏控制栏" : "显示控制栏",
                    systemImage: mirror.showsControls ? "eye.slash" : "eye"
                )
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var actionBar: some View {
        HStack {
            if mirror.isRunning {
                HStack(spacing: 6) {
                    navigationButton(event: .key(.back), symbol: "chevron.backward", help: "返回")
                    navigationButton(event: .key(.appSwitch), symbol: "square.on.square", help: "最近任务")
                    navigationButton(event: .key(.home), symbol: "circle", help: "返回桌面")
                    navigationButton(event: .rotate, symbol: "rotate.right", help: "旋转屏幕")
                    Button {
                        saveScreenshot()
                    } label: {
                        Image(systemName: "camera")
                            .frame(width: 24, height: 18)
                    }
                    .buttonStyle(.bordered)
                    .help("保存截图")
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

            if mirror.isRunning {
                Button(role: .destructive) {
                    model.stopMirror()
                } label: {
                    Label("停止镜像", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    model.startMirror()
                } label: {
                    if mirror.state == .preparing || mirror.state == .connecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("开始镜像", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(device.state != .device || mirror.state == .preparing || mirror.state == .connecting)
            }
        }
        .padding(20)
    }

    private func acceptAPKDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else { return false }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
            guard error == nil, let data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                AppLogger.shared.log("APK", "Unable to read dropped file URL")
                return
            }
            Task { @MainActor in
                guard url.pathExtension.lowercased() == "apk" else {
                    model.message = "请选择扩展名为 .apk 的 Android 安装包。"
                    return
                }
                pendingAPKURL = url
                showsAPKConfirmation = true
            }
        }
        return true
    }

    private func saveScreenshot() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "DroidMirror-\(formattedTimestamp()).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let data = try await mirror.captureScreenshot()
                try data.write(to: url, options: .atomic)
                AppLogger.shared.log("Screenshot", "Saved \(url.lastPathComponent)")
            } catch {
                model.message = error.localizedDescription
                AppLogger.shared.log("Screenshot", "Save failed: \(error.localizedDescription)")
            }
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
        event: AndroidControlEvent,
        symbol: String,
        help: String
    ) -> some View {
        Button {
            Task {
                do {
                    try await mirror.send(event)
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

private struct APKInstallConfirmationView: View {
    @EnvironmentObject private var model: AppModel
    let device: AndroidDevice
    @Binding var selectedURL: URL?
    @Binding var isPresented: Bool
    @State private var isDropTarget = false
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox.and.arrow.backward")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("安装 Android APK")
                        .font(.title2.weight(.semibold))
                    Text("目标设备：\(device.name)（\(device.serial)）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 10) {
                Image(systemName: selectedURL == nil ? "doc.badge.plus" : "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(selectedURL == nil ? Color.secondary : Color.green)
                if let selectedURL {
                    Text(selectedURL.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                    Text(selectedURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                } else {
                    Text("将 APK 拖到这里")
                        .font(.headline)
                    Text("或者点击下方按钮选择文件路径")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 140)
            .background(isDropTarget ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isDropTarget ? Color.accentColor : Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: isDropTarget ? 2 : 1, dash: [6])
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onDrop(
                of: [UTType.fileURL.identifier],
                isTargeted: $isDropTarget,
                perform: acceptDrop
            )

            HStack {
                Button(selectedURL == nil ? "选择 APK…" : "重新选择…") {
                    chooseAPK()
                }
                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
            }

            Divider()

            HStack {
                Button("取消") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .disabled(model.isInstallingAPK)
                Spacer()
                Button {
                    installSelectedAPK()
                } label: {
                    if model.isInstallingAPK {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text("正在安装…")
                        }
                    } else {
                        Text("确认安装")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedURL == nil || model.isInstallingAPK)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private func chooseAPK() {
        let panel = NSOpenPanel()
        panel.title = "选择 Android APK"
        panel.prompt = "选择"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "apk") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        select(url)
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else { return false }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
            guard error == nil, let data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                Task { @MainActor in validationMessage = "无法读取拖入的文件。" }
                return
            }
            Task { @MainActor in select(url) }
        }
        return true
    }

    private func select(_ url: URL) {
        guard url.pathExtension.lowercased() == "apk" else {
            validationMessage = "请选择扩展名为 .apk 的文件。"
            return
        }
        selectedURL = url
        validationMessage = nil
    }

    private func installSelectedAPK() {
        guard let selectedURL else { return }
        Task {
            if await model.installAPK(from: selectedURL) {
                isPresented = false
            }
        }
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
    private enum ConnectionMode: String, CaseIterable, Identifiable {
        case address
        case usb

        var id: String { rawValue }
        var title: String { self == .address ? "输入地址" : "USB 转无线" }
    }

    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var address = ""
    @State private var mode: ConnectionMode = .usb

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "wifi")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text("无线连接")
                    .font(.title2.weight(.semibold))
            }
            Picker("连接方式", selection: $mode) {
                ForEach(ConnectionMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if mode == .address {
                Text("输入 Android 无线调试页面显示的 IP 地址和端口。")
                    .foregroundStyle(.secondary)
                TextField("例如 192.168.1.20:37123", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { connect() }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label(model.selectedDevice?.name ?? "未选择设备", systemImage: "cable.connector")
                        .font(.headline)
                    Text(usbModeDescription)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
            HStack {
                Button("取消") { isPresented = false }
                Spacer()
                Button {
                    mode == .address ? connect() : switchWirelessMode()
                } label: {
                    if model.isConnecting || model.isSwitchingWireless {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(actionTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(actionDisabled)
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

    private func switchWirelessMode() {
        Task {
            let success: Bool
            if model.selectedDevice?.isWireless == true {
                success = await model.disableWirelessADB()
            } else {
                success = await model.enableWirelessFromUSB()
            }
            if success { isPresented = false }
        }
    }

    private var usbModeDescription: String {
        guard let device = model.selectedDevice else {
            return "请先在侧栏选择一台已授权的 USB 设备。"
        }
        if device.isWireless {
            return "关闭该设备的 TCP ADB，并恢复为仅 USB 调试。"
        }
        return "通过 USB 临时开启 TCP ADB。手机重启后需要重新操作。"
    }

    private var actionTitle: String {
        if mode == .address { return "连接" }
        return model.selectedDevice?.isWireless == true ? "关闭无线 ADB" : "启用并连接"
    }

    private var actionDisabled: Bool {
        if model.isConnecting || model.isSwitchingWireless { return true }
        if mode == .address {
            return address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let device = model.selectedDevice else { return true }
        return device.state != .device
    }
}

private struct LogViewer: View {
    @Binding var isPresented: Bool
    @State private var content = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("运行日志")
                    .font(.headline)
                Spacer()
                Button {
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新")
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("复制全部日志")
                Button(role: .destructive) {
                    AppLogger.shared.clear()
                    refresh()
                } label: {
                    Image(systemName: "trash")
                }
                .help("清空日志")
            }
            .padding(14)

            Divider()
            ScrollView([.horizontal, .vertical]) {
                Text(content.isEmpty ? "暂无日志" : content)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()
            HStack {
                Text(AppLogger.shared.fileURL?.path ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("完成") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(minWidth: 680, minHeight: 440)
        .onAppear { refresh() }
    }

    private func refresh() {
        content = AppLogger.shared.snapshot()
    }
}
