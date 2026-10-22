import Foundation

struct RecentDevice: Codable, Identifiable, Equatable, Sendable {
    let serial: String
    var name: String
    var isWireless: Bool
    var lastConnectedAt: Date

    var id: String { serial }
}

enum DeviceHistoryStore {
    private static let defaultsKey = "RecentDevices.v1"
    private static let maximumCount = 20

    static func load() -> [RecentDevice] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let records = try? JSONDecoder().decode([RecentDevice].self, from: data) else {
            return []
        }
        return records.sorted { $0.lastConnectedAt > $1.lastConnectedAt }
    }

    static func record(_ devices: [AndroidDevice], in existing: [RecentDevice]) -> [RecentDevice] {
        let now = Date()
        var records = existing
        for device in devices where device.state == .device {
            let record = RecentDevice(
                serial: device.serial,
                name: device.name,
                isWireless: device.isWireless,
                lastConnectedAt: now
            )
            records.removeAll { $0.serial == device.serial }
            records.append(record)
        }
        records.sort { $0.lastConnectedAt > $1.lastConnectedAt }
        let result = Array(records.prefix(maximumCount))
        save(result)
        return result
    }

    static func remove(serial: String, from existing: [RecentDevice]) -> [RecentDevice] {
        let result = existing.filter { $0.serial != serial }
        save(result)
        return result
    }

    private static func save(_ records: [RecentDevice]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
