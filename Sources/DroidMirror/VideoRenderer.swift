import AVFoundation
import AppKit
import CoreMedia
import QuartzCore
import SwiftUI

enum ScrcpyVideoCodec: UInt32, Sendable {
    case h264 = 0x68323634
    case h265 = 0x68323635
}

enum VideoRendererError: LocalizedError {
    case invalidConfiguration
    case formatCreation(OSStatus)
    case sampleCreation(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "手机返回了无效的视频编码配置。"
        case .formatCreation(let status): return "无法创建视频格式（\(status)）。"
        case .sampleCreation(let status): return "无法创建视频帧（\(status)）。"
        }
    }
}

final class CompressedVideoSampleBuilder {
    private let codec: ScrcpyVideoCodec
    private var formatDescription: CMVideoFormatDescription?

    init(codec: ScrcpyVideoCodec) {
        self.codec = codec
    }

    func configure(with annexBData: Data) throws {
        let units = Self.nalUnits(in: annexBData)
        switch codec {
        case .h264:
            guard let sps = units.first(where: { !$0.isEmpty && ($0[0] & 0x1f) == 7 }),
                  let pps = units.first(where: { !$0.isEmpty && ($0[0] & 0x1f) == 8 }) else {
                throw VideoRendererError.invalidConfiguration
            }
            var description: CMFormatDescription?
            let status = sps.withUnsafeBytes { spsBytes in
                pps.withUnsafeBytes { ppsBytes in
                    let pointers = [
                        spsBytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        ppsBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    ]
                    let sizes = [sps.count, pps.count]
                    return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: 2,
                        parameterSetPointers: pointers,
                        parameterSetSizes: sizes,
                        nalUnitHeaderLength: 4,
                        formatDescriptionOut: &description
                    )
                }
            }
            guard status == noErr, let description else {
                throw VideoRendererError.formatCreation(status)
            }
            formatDescription = description

        case .h265:
            guard let vps = units.first(where: { !$0.isEmpty && (($0[0] >> 1) & 0x3f) == 32 }),
                  let sps = units.first(where: { !$0.isEmpty && (($0[0] >> 1) & 0x3f) == 33 }),
                  let pps = units.first(where: { !$0.isEmpty && (($0[0] >> 1) & 0x3f) == 34 }) else {
                throw VideoRendererError.invalidConfiguration
            }
            var description: CMFormatDescription?
            let status = vps.withUnsafeBytes { vpsBytes in
                sps.withUnsafeBytes { spsBytes in
                    pps.withUnsafeBytes { ppsBytes in
                        let pointers = [
                            vpsBytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
                            spsBytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
                            ppsBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
                        ]
                        let sizes = [vps.count, sps.count, pps.count]
                        return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: 3,
                            parameterSetPointers: pointers,
                            parameterSetSizes: sizes,
                            nalUnitHeaderLength: 4,
                            extensions: nil,
                            formatDescriptionOut: &description
                        )
                    }
                }
            }
            guard status == noErr, let description else {
                throw VideoRendererError.formatCreation(status)
            }
            formatDescription = description
        }
    }

    func makeSample(from annexBData: Data, presentationTimeUs: UInt64) throws -> CMSampleBuffer {
        guard let formatDescription else { throw VideoRendererError.invalidConfiguration }
        let payload = Self.lengthPrefixedData(from: annexBData)
        guard !payload.isEmpty else { throw VideoRendererError.invalidConfiguration }

        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: payload.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: payload.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == kCMBlockBufferNoErr, let blockBuffer else {
            throw VideoRendererError.sampleCreation(status)
        }
        status = payload.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(
                with: bytes.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: payload.count
            )
        }
        guard status == kCMBlockBufferNoErr else {
            throw VideoRendererError.sampleCreation(status)
        }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: CMTimeValue(presentationTimeUs), timescale: 1_000_000),
            decodeTimeStamp: .invalid
        )
        var sampleSize = payload.count
        var sampleBuffer: CMSampleBuffer?
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else {
            throw VideoRendererError.sampleCreation(status)
        }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        return sampleBuffer
    }

    private static func nalUnits(in data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var starts: [(offset: Int, prefix: Int)] = []
        var index = 0
        while index + 3 <= bytes.count {
            if index + 4 <= bytes.count,
               bytes[index] == 0, bytes[index + 1] == 0,
               bytes[index + 2] == 0, bytes[index + 3] == 1 {
                starts.append((index, 4))
                index += 4
            } else if bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 1 {
                starts.append((index, 3))
                index += 3
            } else {
                index += 1
            }
        }
        guard !starts.isEmpty else { return data.isEmpty ? [] : [data] }
        return starts.enumerated().compactMap { item in
            let start = item.element.offset + item.element.prefix
            let end = item.offset + 1 < starts.count ? starts[item.offset + 1].offset : bytes.count
            guard start < end else { return nil }
            return Data(bytes[start..<end])
        }
    }

    private static func lengthPrefixedData(from data: Data) -> Data {
        var result = Data()
        for unit in nalUnits(in: data) where !unit.isEmpty {
            result.appendBigEndian(UInt32(unit.count))
            result.append(unit)
        }
        return result
    }
}

@MainActor
final class VideoRenderer: ObservableObject {
    let displayLayer = AVSampleBufferDisplayLayer()
    @Published private(set) var videoSize = CGSize(width: 1, height: 1)

    init() {
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
    }

    func updateVideoSize(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        videoSize = CGSize(width: width, height: height)
    }

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        if displayLayer.status == .failed {
            displayLayer.flushAndRemoveImage()
        }
        displayLayer.enqueue(sampleBuffer)
    }

    func attach(to hostLayer: CALayer, frame: CGRect) {
        if displayLayer.superlayer !== hostLayer {
            displayLayer.removeFromSuperlayer()
            hostLayer.addSublayer(displayLayer)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = frame
        CATransaction.commit()
    }

    func reset() {
        displayLayer.flushAndRemoveImage()
        videoSize = CGSize(width: 1, height: 1)
    }

    var renderingError: Error? {
        displayLayer.status == .failed ? displayLayer.error : nil
    }
}

struct MirrorSurfaceView: NSViewRepresentable {
    @ObservedObject var renderer: VideoRenderer
    let onEvent: (AndroidControlEvent) -> Void

    func makeNSView(context: Context) -> MirrorInputView {
        MirrorInputView(renderer: renderer, onEvent: onEvent)
    }

    func updateNSView(_ nsView: MirrorInputView, context: Context) {
        nsView.renderer = renderer
        nsView.onEvent = onEvent
        nsView.needsLayout = true
    }

    static func dismantleNSView(_ nsView: MirrorInputView, coordinator: ()) {
        guard nsView.renderer.displayLayer.superlayer === nsView.layer else { return }
        nsView.renderer.displayLayer.removeFromSuperlayer()
    }
}

final class MirrorInputView: NSView {
    var renderer: VideoRenderer
    var onEvent: (AndroidControlEvent) -> Void

    init(renderer: VideoRenderer, onEvent: @escaping (AndroidControlEvent) -> Void) {
        self.renderer = renderer
        self.onEvent = onEvent
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        guard let layer else { return }
        renderer.attach(to: layer, frame: bounds)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendTouch(.down, event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        sendTouch(.move, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        sendTouch(.up, event: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let position = devicePosition(for: event) else { return }
        onEvent(.scroll(
            x: position.x,
            y: position.y,
            width: position.width,
            height: position.height,
            horizontal: Float(event.scrollingDeltaX),
            vertical: Float(event.scrollingDeltaY)
        ))
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
            if let value = NSPasteboard.general.string(forType: .string) {
                onEvent(.pasteClipboard(value))
            }
            return
        }
        if let keyCode = androidKeyCode(for: event) {
            onEvent(.key(keyCode))
        } else if !event.modifierFlags.contains(.command), let text = event.characters, !text.isEmpty {
            onEvent(.text(text))
        } else {
            super.keyDown(with: event)
        }
    }

    private func sendTouch(_ action: TouchAction, event: NSEvent) {
        guard let position = devicePosition(for: event) else { return }
        onEvent(.touch(
            action: action,
            x: position.x,
            y: position.y,
            width: position.width,
            height: position.height
        ))
    }

    private func devicePosition(for event: NSEvent) -> (x: Int32, y: Int32, width: UInt16, height: UInt16)? {
        let size = renderer.videoSize
        guard size.width > 1, size.height > 1, bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let contentWidth = size.width * scale
        let contentHeight = size.height * scale
        let originX = (bounds.width - contentWidth) / 2
        let originY = (bounds.height - contentHeight) / 2
        let location = convert(event.locationInWindow, from: nil)
        guard location.x >= originX, location.x <= originX + contentWidth,
              location.y >= originY, location.y <= originY + contentHeight else { return nil }

        let x = Int32(max(0, min(size.width - 1, (location.x - originX) / scale)))
        let y = Int32(max(0, min(size.height - 1, size.height - ((location.y - originY) / scale))))
        return (x, y, UInt16(min(size.width, Double(UInt16.max))), UInt16(min(size.height, Double(UInt16.max))))
    }

    private func androidKeyCode(for event: NSEvent) -> AndroidKeyCode? {
        switch event.keyCode {
        case 36, 76: return .enter
        case 51, 117: return .delete
        case 53: return .back
        case 123: return .dpadLeft
        case 124: return .dpadRight
        case 125: return .dpadDown
        case 126: return .dpadUp
        default: return nil
        }
    }
}
