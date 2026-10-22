import AppKit
import Foundation

final class ScrcpyControlChannel: @unchecked Sendable {
    private let socket: TCPSocket
    private let writeLock = NSLock()

    init(socket: TCPSocket) {
        self.socket = socket
    }

    func send(_ event: AndroidControlEvent) throws {
        let payload = ScrcpyControlMessageEncoder.encode(event)
        writeLock.lock()
        defer { writeLock.unlock() }
        try socket.writeAll(payload)
    }

    func receiveDeviceMessages(onClipboard: @escaping @Sendable (String) -> Void) {
        do {
            while true {
                let type = try socket.readExactly(1)[0]
                switch type {
                case 0:
                    let lengthData = try socket.readExactly(4)
                    let length = Int(lengthData.bigEndianUInt32(at: 0))
                    guard length <= 1 << 18 else { throw TCPSocketError.readFailed("剪贴板数据过大") }
                    let textData = try socket.readExactly(length)
                    if let text = String(data: textData, encoding: .utf8) {
                        onClipboard(text)
                    }
                case 1:
                    _ = try socket.readExactly(8)
                case 2:
                    let header = try socket.readExactly(4)
                    let size = Int(header.bigEndianUInt16(at: 2))
                    _ = try socket.readExactly(size)
                default:
                    throw TCPSocketError.readFailed("未知控制响应 \(type)")
                }
            }
        } catch {
            // Closing the socket is the normal way to stop this receiver.
        }
    }

}

enum ScrcpyControlMessageEncoder {
    static func encode(_ event: AndroidControlEvent) -> Data {
        var data = Data()
        switch event {
        case .key(let keyCode):
            appendKey(action: 0, keyCode: keyCode, to: &data)
            var release = Data()
            appendKey(action: 1, keyCode: keyCode, to: &release)
            data.append(release)

        case .text(let text):
            let utf8 = Data(text.utf8.prefix(300))
            data.append(1)
            data.appendBigEndian(UInt32(utf8.count))
            data.append(utf8)

        case let .touch(action, x, y, width, height):
            data.append(2)
            data.append(action.rawValue)
            data.appendBigEndian(UInt64.max)
            data.appendBigEndian(UInt32(bitPattern: x))
            data.appendBigEndian(UInt32(bitPattern: y))
            data.appendBigEndian(width)
            data.appendBigEndian(height)
            data.appendBigEndian(action == .up || action == .cancel ? UInt16(0) : UInt16.max)
            data.appendBigEndian(UInt32(1))
            data.appendBigEndian(action == .up || action == .cancel ? UInt32(0) : UInt32(1))

        case let .scroll(x, y, width, height, horizontal, vertical):
            data.append(3)
            data.appendBigEndian(UInt32(bitPattern: x))
            data.appendBigEndian(UInt32(bitPattern: y))
            data.appendBigEndian(width)
            data.appendBigEndian(height)
            data.appendBigEndian(scrollFixedPoint(horizontal))
            data.appendBigEndian(scrollFixedPoint(vertical))
            data.appendBigEndian(UInt32(0))

        case .setDisplayPower(let on):
            data.append(10)
            data.append(on ? 1 : 0)

        case .rotate:
            data.append(11)

        case .pasteClipboard(let text):
            let utf8 = Data(text.utf8.prefix((1 << 18) - 14))
            data.append(9)
            data.appendBigEndian(UInt64(0))
            data.append(1)
            data.appendBigEndian(UInt32(utf8.count))
            data.append(utf8)
        }
        return data
    }

    private static func appendKey(action: UInt8, keyCode: AndroidKeyCode, to data: inout Data) {
        data.append(0)
        data.append(action)
        data.appendBigEndian(UInt32(bitPattern: keyCode.rawValue))
        data.appendBigEndian(UInt32(0))
        data.appendBigEndian(UInt32(0))
    }

    private static func scrollFixedPoint(_ value: Float) -> UInt16 {
        let normalized = max(-1, min(1, value / 16))
        var result = Int32(normalized * 32768)
        result = min(32767, max(-32768, result))
        return UInt16(bitPattern: Int16(result))
    }
}
