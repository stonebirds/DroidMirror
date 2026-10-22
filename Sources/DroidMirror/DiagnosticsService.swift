import Foundation

enum DiagnosticsService {
    @MainActor
    static func report(model: AppModel) async -> String {
        let adbVersion = try? await ADBService.run(["version"], acceptFailure: true)
        let devices = (try? await DeviceService.devices()) ?? []
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        let runtimeLog = AppLogger.shared.snapshot()
        let crashReport = latestCrashReport()

        let deviceLines = devices.map {
            "- \($0.serial) | \($0.name) | \($0.state.displayName) | \($0.isWireless ? "wireless" : "usb")"
        }.joined(separator: "\n")
        let recentDeviceLines = model.recentDevices.map {
            "- \($0.serial) | \($0.name) | \($0.isWireless ? "wireless" : "usb") | \(ISO8601DateFormatter().string(from: $0.lastConnectedAt))"
        }.joined(separator: "\n")

        return """
        DroidMirror diagnostics
        Generated: \(ISO8601DateFormatter().string(from: Date()))

        App version: \(appVersion)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Architecture: \(architecture)
        Session state: \(model.mirror.state.displayName)
        Mirror engine: \(model.mirror.activeEngine?.rawValue ?? "none")
        Selected device: \(model.selectedDeviceID ?? "none")

        adb path: \(ToolLocator.executable(named: "adb")?.path ?? "missing")
        scrcpy path: \(ToolLocator.executable(named: "scrcpy")?.path ?? "missing")
        scrcpy-server path: \(ToolLocator.scrcpyServerURL()?.path ?? "missing")
        runtime log path: \(AppLogger.shared.fileURL?.path ?? "unavailable")

        adb version:
        \(adbVersion?.output ?? adbVersion?.errorOutput ?? "unavailable")

        Devices:
        \(deviceLines.isEmpty ? "- none" : deviceLines)

        Recent devices:
        \(recentDeviceLines.isEmpty ? "- none" : recentDeviceLines)

        Settings:
        - max size: \(model.settings.maxSize)
        - bit rate: \(model.settings.bitRateMbps) Mbps
        - max FPS: \(model.settings.maxFPS)
        - video codec: \(model.settings.videoCodec.rawValue)
        - audio: \(model.settings.audioEnabled)
        - presentation: \(model.settings.presentation.rawValue)

        Runtime log:
        \(runtimeLog.isEmpty ? "- empty" : runtimeLog)

        Latest macOS crash report:
        \(crashReport ?? "- none")
        """
    }

    private static var architecture: String {
#if arch(arm64)
        return "arm64"
#elseif arch(x86_64)
        return "x86_64"
#else
        return "unknown"
#endif
    }

    private static func latestCrashReport() -> String? {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let candidates = files.filter {
            $0.lastPathComponent.hasPrefix("DroidMirror-")
                && ["ips", "crash"].contains($0.pathExtension.lowercased())
        }
        let latest = candidates.max {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }
        guard let latest, let data = try? Data(contentsOf: latest) else { return nil }
        let tail = data.suffix(200 * 1024)
        return "File: \(latest.lastPathComponent)\n" + String(decoding: tail, as: UTF8.self)
    }
}
