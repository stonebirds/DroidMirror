import Foundation

enum ScrcpyServiceError: LocalizedError {
    case executableMissing
    case alreadyRunning

    var errorDescription: String? {
        switch self {
        case .executableMissing:
            return "未找到 scrcpy。请使用完整安装包，或先运行 brew install scrcpy。"
        case .alreadyRunning:
            return "镜像窗口已经在运行。"
        }
    }
}

@MainActor
final class ScrcpyService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    private var process: Process?

    func start(device: AndroidDevice, settings: MirrorSettings, recordingURL: URL? = nil) throws {
        guard process == nil else { throw ScrcpyServiceError.alreadyRunning }
        guard let executable = ToolLocator.executable(named: "scrcpy") else {
            throw ScrcpyServiceError.executableMissing
        }

        let task = Process()
        let errorPipe = Pipe()
        task.executableURL = executable
        task.arguments = settings.arguments(serial: device.serial, recordingURL: recordingURL)
        task.standardError = errorPipe
        task.standardOutput = Pipe()
        task.currentDirectoryURL = executable.deletingLastPathComponent()

        var environment = ProcessInfo.processInfo.environment
        if let adb = ToolLocator.executable(named: "adb") {
            let directory = adb.deletingLastPathComponent().path
            environment["PATH"] = directory + ":" + (environment["PATH"] ?? "")
            environment["ADB"] = adb.path
        }
        task.environment = environment

        task.terminationHandler = { [weak self] finished in
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let status = finished.terminationStatus
            let reason = finished.terminationReason
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.process = nil
                self.isRunning = false
                FloatingControlsController.shared.hide()
                if status != 0 && reason != .uncaughtSignal {
                    self.lastError = message.isEmpty ? "scrcpy 异常退出。" : message
                }
            }
        }

        lastError = nil
        try task.run()
        process = task
        isRunning = true
        FloatingControlsController.shared.show(for: device)
    }

    func stop() {
        guard let process else { return }
        process.terminate()
        self.process = nil
        isRunning = false
        FloatingControlsController.shared.hide()
    }

    func clearError() {
        lastError = nil
    }

    deinit {
        process?.terminate()
    }
}
