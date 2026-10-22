import AppKit
import Foundation

enum EmbeddedMirrorError: LocalizedError {
    case serverMissing
    case invalidForwardPort(String)
    case unsupportedVideoCodec(UInt32)
    case invalidDeviceMetadata
    case invalidVideoHeader
    case packetTooLarge(Int)
    case serverExited(String)

    var errorDescription: String? {
        switch self {
        case .serverMissing:
            return "未找到 scrcpy-server。请使用完整安装包或重新选择 scrcpy。"
        case .invalidForwardPort(let value):
            return "adb 未返回有效的本地端口：\(value)"
        case .unsupportedVideoCodec(let codec):
            return String(format: "不支持手机返回的视频编码 0x%08x。", codec)
        case .invalidDeviceMetadata:
            return "无法读取 Android 设备信息。"
        case .invalidVideoHeader:
            return "手机返回了无效的视频流头。"
        case .packetTooLarge(let size):
            return "手机返回的视频包异常（\(size) 字节）。"
        case .serverExited(let message):
            return message.isEmpty ? "手机端镜像服务提前退出。" : message
        }
    }
}

private final class ProcessLogCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        storage += String(decoding: data, as: UTF8.self)
        if storage.count > 32_000 {
            storage = String(storage.suffix(32_000))
        }
        lock.unlock()
    }

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return storage.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class ProcessReference: @unchecked Sendable {
    let process: Process

    init(_ process: Process) {
        self.process = process
    }
}

final class EmbeddedRuntime: @unchecked Sendable {
    static let serverVersion = "5.0.1"
    static let maxPacketSize = 32 * 1024 * 1024

    let device: AndroidDevice
    let localPort: UInt16
    let codec: ScrcpyVideoCodec
    let deviceName: String
    let initialWidth: Int
    let initialHeight: Int
    let control: ScrcpyControlChannel

    private let videoSocket: TCPSocket
    private let audioSocket: TCPSocket?
    private let controlSocket: TCPSocket
    private let serverProcess: Process
    private let logCollector: ProcessLogCollector
    private let audioPlayer: RawAudioPlayer?
    private let lifecycleLock = NSLock()
    private var stopped = false
    private var workerTasks: [Task<Void, Never>] = []

    private init(
        device: AndroidDevice,
        localPort: UInt16,
        codec: ScrcpyVideoCodec,
        deviceName: String,
        initialWidth: Int,
        initialHeight: Int,
        videoSocket: TCPSocket,
        audioSocket: TCPSocket?,
        controlSocket: TCPSocket,
        serverProcess: Process,
        logCollector: ProcessLogCollector,
        audioPlayer: RawAudioPlayer?
    ) {
        self.device = device
        self.localPort = localPort
        self.codec = codec
        self.deviceName = deviceName
        self.initialWidth = initialWidth
        self.initialHeight = initialHeight
        self.videoSocket = videoSocket
        self.audioSocket = audioSocket
        self.controlSocket = controlSocket
        self.serverProcess = serverProcess
        self.logCollector = logCollector
        self.audioPlayer = audioPlayer
        control = ScrcpyControlChannel(socket: controlSocket)
    }

    static func create(
        device: AndroidDevice,
        settings: MirrorSettings,
        codecPreference: VideoCodecPreference
    ) async throws -> EmbeddedRuntime {
        guard let serverURL = ToolLocator.scrcpyServerURL() else {
            throw EmbeddedMirrorError.serverMissing
        }

        _ = try await ADBService.run(
            ADBService.arguments(
                for: device,
                command: ["push", serverURL.path, "/data/local/tmp/scrcpy-server.jar"]
            )
        )

        let scid = UInt32.random(in: 1...0x7fff_ffff)
        let socketName = String(format: "scrcpy_%08x", scid)
        let forward = try await ADBService.run(
            ADBService.arguments(
                for: device,
                command: ["forward", "tcp:0", "localabstract:\(socketName)"]
            )
        )
        guard let port = UInt16(forward.output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw EmbeddedMirrorError.invalidForwardPort(forward.output)
        }

        let process: Process
        let collector: ProcessLogCollector
        do {
            (process, collector) = try startServerProcess(
                device: device,
                settings: settings,
                codecPreference: codecPreference,
                scid: scid
            )
        } catch {
            _ = try? await ADBService.run(
                ADBService.arguments(for: device, command: ["forward", "--remove", "tcp:\(port)"]),
                acceptFailure: true
            )
            throw error
        }

        do {
            let processReference = ProcessReference(process)
            let connectionTask = Task.detached(priority: .userInitiated) { () throws -> (
                TCPSocket, TCPSocket?, TCPSocket, ScrcpyVideoCodec, String, Int, Int
            ) in
                func read(_ socket: TCPSocket, count: Int, phase: String) throws -> Data {
                    do {
                        return try socket.readExactly(count)
                    } catch {
                        let log = collector.value
                        let details = log.isEmpty ? error.localizedDescription : log
                        throw EmbeddedMirrorError.serverExited("\(phase)：\(details)")
                    }
                }

                let process = processReference.process
                let video = try connectFirstSocketWithRetry(
                    port: port,
                    process: process,
                    collector: collector
                )
                let audio = settings.audioEnabled
                    ? try connectWithRetry(port: port, process: process, collector: collector)
                    : nil
                let control = try connectWithRetry(port: port, process: process, collector: collector)

                let metadata = try read(video, count: 64, phase: "读取设备信息")
                guard let zero = metadata.firstIndex(of: 0) else {
                    throw EmbeddedMirrorError.invalidDeviceMetadata
                }
                let deviceName = String(data: metadata.prefix(upTo: zero), encoding: .utf8) ?? device.name

                let rawCodec = try read(video, count: 4, phase: "读取视频编码").bigEndianUInt32(at: 0)
                guard let codec = ScrcpyVideoCodec(rawValue: rawCodec) else {
                    throw EmbeddedMirrorError.unsupportedVideoCodec(rawCodec)
                }
                let header = try read(video, count: 12, phase: "读取视频会话信息")
                guard header[0] & 0x80 != 0 else {
                    throw EmbeddedMirrorError.invalidVideoHeader
                }
                let width = Int(header.bigEndianUInt32(at: 4))
                let height = Int(header.bigEndianUInt32(at: 8))
                guard width > 0, height > 0 else {
                    throw EmbeddedMirrorError.invalidVideoHeader
                }
                return (video, audio, control, codec, deviceName, width, height)
            }
            let sockets = try await connectionTask.value

            return EmbeddedRuntime(
                device: device,
                localPort: port,
                codec: sockets.3,
                deviceName: sockets.4,
                initialWidth: sockets.5,
                initialHeight: sockets.6,
                videoSocket: sockets.0,
                audioSocket: sockets.1,
                controlSocket: sockets.2,
                serverProcess: process,
                logCollector: collector,
                audioPlayer: settings.audioEnabled ? RawAudioPlayer() : nil
            )
        } catch {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            _ = try? await ADBService.run(
                ADBService.arguments(for: device, command: ["forward", "--remove", "tcp:\(port)"]),
                acceptFailure: true
            )
            if !collector.value.isEmpty {
                throw EmbeddedMirrorError.serverExited(collector.value)
            }
            throw error
        }
    }

    func startReaders(
        renderer: VideoRenderer,
        onFailure: @escaping @Sendable (Error) -> Void,
        onClipboard: @escaping @Sendable (String) -> Void
    ) {
        let videoTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.readVideo(renderer: renderer)
                if !self.isStopped { onFailure(TCPSocketError.closed) }
            } catch {
                if !self.isStopped { onFailure(error) }
            }
        }
        var tasks = [videoTask]

        if audioSocket != nil {
            tasks.append(Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                do {
                    try self.readAudio()
                } catch {
                    // Audio is optional; video continues when capture is unavailable.
                }
            })
        }

        tasks.append(Task.detached(priority: .utility) { [weak self] in
            self?.control.receiveDeviceMessages(onClipboard: onClipboard)
        })

        lifecycleLock.lock()
        workerTasks = tasks
        lifecycleLock.unlock()
    }

    func close() {
        lifecycleLock.lock()
        guard !stopped else {
            lifecycleLock.unlock()
            return
        }
        stopped = true
        let tasks = workerTasks
        workerTasks.removeAll()
        lifecycleLock.unlock()

        videoSocket.close()
        audioSocket?.close()
        controlSocket.close()
        tasks.forEach { $0.cancel() }
        audioPlayer?.stop()
        if serverProcess.isRunning { serverProcess.terminate() }
    }

    var isStopped: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return stopped
    }

    private func readVideo(renderer: VideoRenderer) async throws {
        let builder = CompressedVideoSampleBuilder(codec: codec)
        while !isStopped {
            let header = try videoSocket.readExactly(12)
            if header[0] & 0x80 != 0 {
                let width = Int(header.bigEndianUInt32(at: 4))
                let height = Int(header.bigEndianUInt32(at: 8))
                await renderer.updateVideoSize(width: width, height: height)
                continue
            }

            let flagsAndPTS = header.bigEndianUInt64(at: 0)
            let length = Int(header.bigEndianUInt32(at: 8))
            guard length > 0, length <= Self.maxPacketSize else {
                throw EmbeddedMirrorError.packetTooLarge(length)
            }
            let packet = try videoSocket.readExactly(length)
            let isConfiguration = flagsAndPTS & (UInt64(1) << 62) != 0
            if isConfiguration {
                try builder.configure(with: packet)
                continue
            }
            let pts = flagsAndPTS & ((UInt64(1) << 61) - 1)
            let sample = try builder.makeSample(from: packet, presentationTimeUs: pts)
            await renderer.enqueue(sample)
        }
    }

    private func readAudio() throws {
        guard let audioSocket else { return }
        let codecID = try audioSocket.readExactly(4).bigEndianUInt32(at: 0)
        if codecID == 0 { return }
        guard codecID == 0x00726177 else {
            throw EmbeddedMirrorError.unsupportedVideoCodec(codecID)
        }
        while !isStopped {
            let header = try audioSocket.readExactly(12)
            let length = Int(header.bigEndianUInt32(at: 8))
            guard length > 0, length <= Self.maxPacketSize else {
                throw EmbeddedMirrorError.packetTooLarge(length)
            }
            audioPlayer?.enqueue(try audioSocket.readExactly(length))
        }
    }

    private static func connectWithRetry(
        port: UInt16,
        process: Process,
        collector: ProcessLogCollector
    ) throws -> TCPSocket {
        var lastError: Error?
        for _ in 0..<100 {
            if !process.isRunning {
                throw EmbeddedMirrorError.serverExited(collector.value)
            }
            do {
                return try TCPSocket(localPort: port)
            } catch {
                lastError = error
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        throw lastError ?? TCPSocketError.connectionFailed("连接超时")
    }

    private static func connectFirstSocketWithRetry(
        port: UInt16,
        process: Process,
        collector: ProcessLogCollector
    ) throws -> TCPSocket {
        var lastError: Error?
        for _ in 0..<100 {
            if !process.isRunning {
                throw EmbeddedMirrorError.serverExited(collector.value)
            }
            do {
                let socket = try TCPSocket(localPort: port)
                do {
                    _ = try socket.readExactly(1)
                    return socket
                } catch {
                    socket.close()
                    throw error
                }
            } catch {
                lastError = error
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        let details = collector.value
        if !details.isEmpty { throw EmbeddedMirrorError.serverExited(details) }
        throw lastError ?? TCPSocketError.connectionFailed("等待 server 握手超时")
    }

    private static func startServerProcess(
        device: AndroidDevice,
        settings: MirrorSettings,
        codecPreference: VideoCodecPreference,
        scid: UInt32
    ) throws -> (Process, ProcessLogCollector) {
        guard let adb = ToolLocator.executable(named: "adb") else {
            throw ADBServiceError.executableMissing
        }
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        let collector = ProcessLogCollector()
        Task.detached(priority: .utility) {
            collector.append(output.fileHandleForReading.readDataToEndOfFile())
        }
        Task.detached(priority: .utility) {
            collector.append(error.fileHandleForReading.readDataToEndOfFile())
        }

        var serverArguments = [
            Self.serverVersion,
            String(format: "scid=%08x", scid),
            "log_level=info",
            "tunnel_forward=true",
            "video_codec=\(codecPreference.rawValue)",
            "video_bit_rate=\(settings.bitRateMbps * 1_000_000)",
            "max_size=\(settings.maxSize)",
            "max_fps=\(settings.maxFPS)",
            "audio=\(settings.audioEnabled)",
            "control=true",
            "stay_awake=\(settings.stayAwake)",
            "cleanup=true",
            "power_on=true",
            "send_device_meta=true",
            "send_frame_meta=true",
            "send_dummy_byte=true",
            "send_stream_meta=true"
        ]
        if settings.audioEnabled {
            serverArguments.append("audio_codec=raw")
        }

        process.executableURL = adb
        process.arguments = [
            "-s", device.serial,
            "shell",
            "CLASSPATH=/data/local/tmp/scrcpy-server.jar",
            "app_process", "/", "com.genymobile.scrcpy.Server"
        ] + serverArguments
        if ProcessInfo.processInfo.environment["DROIDMIRROR_SERVER_LOG_STDERR"] == "1" {
            process.standardOutput = FileHandle.standardError
            process.standardError = FileHandle.standardError
        } else {
            process.standardOutput = output
            process.standardError = error
        }
        try process.run()
        return (process, collector)
    }
}

@MainActor
final class EmbeddedScrcpySession: ObservableObject, MirrorSession {
    @Published private(set) var state: MirrorSessionState = .idle
    @Published private(set) var activeCodec: VideoCodecPreference = .h264
    @Published private(set) var deviceName = "Android"
    @Published private(set) var didFallbackCodec = false

    let renderer = VideoRenderer()
    private var runtime: EmbeddedRuntime?
    private var reconnectTask: Task<Void, Never>?
    private var rendererMonitorTask: Task<Void, Never>?
    private var lastDevice: AndroidDevice?
    private var lastSettings: MirrorSettings?
    private var manualStop = false

    func start(device: AndroidDevice, settings: MirrorSettings, recordingURL: URL?) async throws {
        guard runtime == nil else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        rendererMonitorTask?.cancel()
        rendererMonitorTask = nil
        manualStop = false
        lastDevice = device
        lastSettings = settings
        state = .preparing
        didFallbackCodec = false

        let runtime: EmbeddedRuntime
        do {
            runtime = try await EmbeddedRuntime.create(
                device: device,
                settings: settings,
                codecPreference: settings.videoCodec
            )
            activeCodec = settings.videoCodec
        } catch {
            guard settings.videoCodec == .h265 else {
                state = .failed(error.localizedDescription)
                throw error
            }
            state = .reconnecting
            do {
                runtime = try await EmbeddedRuntime.create(
                    device: device,
                    settings: settings,
                    codecPreference: .h264
                )
            } catch {
                state = .failed(error.localizedDescription)
                throw error
            }
            activeCodec = .h264
            didFallbackCodec = true
        }

        activate(runtime, settings: settings)
    }

    func stop() async {
        manualStop = true
        reconnectTask?.cancel()
        reconnectTask = nil
        rendererMonitorTask?.cancel()
        rendererMonitorTask = nil
        state = .stopping
        guard let runtime else {
            renderer.reset()
            lastDevice = nil
            lastSettings = nil
            state = .idle
            return
        }
        self.runtime = nil
        runtime.close()
        _ = try? await ADBService.run(
            ADBService.arguments(
                for: runtime.device,
                command: ["forward", "--remove", "tcp:\(runtime.localPort)"]
            ),
            acceptFailure: true
        )
        renderer.reset()
        lastDevice = nil
        lastSettings = nil
        state = .idle
    }

    func send(_ event: AndroidControlEvent) async throws {
        guard let runtime else { throw TCPSocketError.closed }
        try runtime.control.send(event)
    }

    private func handleFailure(_ error: Error) {
        guard !manualStop, state.isRunning, let runtime,
              let device = lastDevice, let settings = lastSettings else { return }
        self.runtime = nil
        runtime.close()
        renderer.reset()
        state = .reconnecting
        let codec: VideoCodecPreference
        if activeCodec == .h265, !didFallbackCodec {
            codec = .h264
            activeCodec = .h264
            didFallbackCodec = true
        } else {
            codec = activeCodec
        }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            _ = try? await ADBService.run(
                ADBService.arguments(
                    for: runtime.device,
                    command: ["forward", "--remove", "tcp:\(runtime.localPort)"]
                ),
                acceptFailure: true
            )
            var lastError = error
            for attempt in 1...3 {
                guard !Task.isCancelled, !self.manualStop else { return }
                if attempt > 1 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                }
                do {
                    let devices = try await DeviceService.devices()
                    guard devices.contains(where: { $0.serial == device.serial && $0.state == .device }) else {
                        throw TCPSocketError.connectionFailed("设备尚未重新上线")
                    }
                    let newRuntime = try await EmbeddedRuntime.create(
                        device: device,
                        settings: settings,
                        codecPreference: codec
                    )
                    guard !Task.isCancelled, !self.manualStop else {
                        newRuntime.close()
                        _ = try? await ADBService.run(
                            ADBService.arguments(
                                for: device,
                                command: ["forward", "--remove", "tcp:\(newRuntime.localPort)"]
                            ),
                            acceptFailure: true
                        )
                        return
                    }
                    self.activate(newRuntime, settings: settings)
                    self.reconnectTask = nil
                    return
                } catch {
                    lastError = error
                }
            }
            self.reconnectTask = nil
            self.state = .failed(lastError.localizedDescription)
        }
    }

    private func activate(_ runtime: EmbeddedRuntime, settings: MirrorSettings) {
        self.runtime = runtime
        deviceName = runtime.deviceName
        renderer.updateVideoSize(width: runtime.initialWidth, height: runtime.initialHeight)
        state = .streaming
        let session = self
        runtime.startReaders(
            renderer: renderer,
            onFailure: { error in
                Task { @MainActor in session.handleFailure(error) }
            },
            onClipboard: { text in
                Task { @MainActor in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
        )
        if settings.turnScreenOff {
            try? runtime.control.send(.setDisplayPower(false))
        }
        rendererMonitorTask?.cancel()
        rendererMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, self.state == .streaming else { return }
                if let error = self.renderer.renderingError {
                    self.handleFailure(error)
                    return
                }
            }
        }
    }

    deinit {
        reconnectTask?.cancel()
        rendererMonitorTask?.cancel()
        runtime?.close()
    }
}
