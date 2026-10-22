import AVFoundation
import Foundation

final class RawAudioPlayer: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let lock = NSLock()
    private var scheduledFrames: AVAudioFrameCount = 0
    private let maxScheduledFrames: AVAudioFrameCount = 96_000

    init?() {
        guard let format = Self.format else { return nil }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do {
            try engine.start()
            player.play()
        } catch {
            return nil
        }
    }

    func enqueue(_ littleEndianPCM: Data) {
        guard let format = Self.format else { return }
        let alignedSize = littleEndianPCM.count - littleEndianPCM.count % 4
        guard alignedSize > 0 else { return }
        let frameCount = AVAudioFrameCount(alignedSize / 4)

        lock.lock()
        guard scheduledFrames + frameCount <= maxScheduledFrames else {
            lock.unlock()
            return
        }
        scheduledFrames += frameCount
        lock.unlock()

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            lock.lock()
            scheduledFrames = scheduledFrames > frameCount ? scheduledFrames - frameCount : 0
            lock.unlock()
            return
        }
        buffer.frameLength = frameCount
        guard let channels = buffer.floatChannelData else {
            releaseScheduledFrames(frameCount)
            return
        }
        littleEndianPCM.withUnsafeBytes { source in
            let bytes = source.bindMemory(to: UInt8.self)
            for frame in 0..<Int(frameCount) {
                let offset = frame * 4
                let left = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
                let right = UInt16(bytes[offset + 2]) | (UInt16(bytes[offset + 3]) << 8)
                channels[0][frame] = Float(Int16(bitPattern: left)) / 32_768
                channels[1][frame] = Float(Int16(bitPattern: right)) / 32_768
            }
        }
        player.scheduleBuffer(buffer) { [weak self] in
            self?.releaseScheduledFrames(frameCount)
        }
    }

    func stop() {
        player.stop()
        engine.stop()
        lock.lock()
        scheduledFrames = 0
        lock.unlock()
    }

    private func releaseScheduledFrames(_ frameCount: AVAudioFrameCount) {
        lock.lock()
        scheduledFrames = scheduledFrames > frameCount ? scheduledFrames - frameCount : 0
        lock.unlock()
    }

    private static let format = AVAudioFormat(
        standardFormatWithSampleRate: 48_000,
        channels: 2
    )
}
