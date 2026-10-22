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
        littleEndianPCM.withUnsafeBytes { source in
            guard let destination = buffer.mutableAudioBufferList.pointee.mBuffers.mData,
                  let sourceAddress = source.baseAddress else { return }
            memcpy(destination, sourceAddress, alignedSize)
            buffer.mutableAudioBufferList.pointee.mBuffers.mDataByteSize = UInt32(alignedSize)
        }
        player.scheduleBuffer(buffer) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.scheduledFrames = self.scheduledFrames > frameCount ? self.scheduledFrames - frameCount : 0
            self.lock.unlock()
        }
    }

    func stop() {
        player.stop()
        engine.stop()
        lock.lock()
        scheduledFrames = 0
        lock.unlock()
    }

    private static var format: AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 48_000,
            channels: 2,
            interleaved: true
        )
    }
}
