import Foundation

struct MirrorSettings: Codable, Equatable {
    var maxSize = 1920
    var bitRateMbps = 8
    var maxFPS = 60
    var audioEnabled = true
    var turnScreenOff = false
    var stayAwake = true
    var engine: MirrorEngine = .embedded
    var videoCodec: VideoCodecPreference = .h264
    var presentation: MirrorPresentation = .embedded

    func arguments(serial: String, recordingURL: URL? = nil) -> [String] {
        var values = [
            "--serial", serial,
            "--max-size", String(maxSize),
            "--video-bit-rate", "\(bitRateMbps)M",
            "--max-fps", String(maxFPS),
            "--window-title", "DroidMirror"
        ]
        if !audioEnabled { values.append("--no-audio") }
        if turnScreenOff { values.append("--turn-screen-off") }
        if stayAwake { values.append("--stay-awake") }
        values.append(contentsOf: ["--video-codec", videoCodec.rawValue])
        if let recordingURL {
            values.append(contentsOf: ["--record", recordingURL.path])
        }
        return values
    }
}
