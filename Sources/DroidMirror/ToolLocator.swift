import Foundation

enum ToolLocator {
    private static let customADBPathKey = "CustomADBPath"

    private static var runtimeArchitecture: String {
#if arch(arm64)
        return "arm64"
#elseif arch(x86_64)
        return "x86_64"
#else
        return "unknown"
#endif
    }

    static func executable(named name: String) -> URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        if name == "adb",
           let customPath = UserDefaults.standard.string(forKey: customADBPathKey),
           !customPath.isEmpty {
            candidates.append(URL(fileURLWithPath: customPath))
        }

        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("bin/\(runtimeArchitecture)/\(name)"))
            candidates.append(resources.appendingPathComponent("bin/\(name)"))
            candidates.append(resources.appendingPathComponent(name))
        }

        if name == "adb" {
            candidates.append(fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Android/sdk/platform-tools/adb"))
        }

        candidates.append(contentsOf: [
            URL(fileURLWithPath: "/opt/homebrew/bin/\(name)"),
            URL(fileURLWithPath: "/usr/local/bin/\(name)"),
            URL(fileURLWithPath: "/usr/bin/\(name)")
        ])

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                URL(fileURLWithPath: String($0)).appendingPathComponent(name)
            })
        }

        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    static func setCustomADB(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: customADBPathKey)
    }

    static var customADBURL: URL? {
        guard let path = UserDefaults.standard.string(forKey: customADBPathKey),
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}
