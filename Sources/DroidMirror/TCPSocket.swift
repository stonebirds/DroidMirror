import Darwin
import Foundation

enum TCPSocketError: LocalizedError {
    case creationFailed(String)
    case connectionFailed(String)
    case closed
    case readFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .creationFailed(let message): return "无法创建镜像连接：\(message)"
        case .connectionFailed(let message): return "无法连接镜像服务：\(message)"
        case .closed: return "镜像连接已关闭。"
        case .readFailed(let message): return "读取镜像数据失败：\(message)"
        case .writeFailed(let message): return "发送控制指令失败：\(message)"
        }
    }
}

final class TCPSocket: @unchecked Sendable {
    private let descriptor: Int32
    private let stateLock = NSLock()
    private var isClosed = false

    init(localPort: UInt16) throws {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw TCPSocketError.creationFailed(Self.lastError)
        }

        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))

        var noDelay: Int32 = 1
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &noDelay, socklen_t(MemoryLayout.size(ofValue: noDelay)))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = localPort.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            let message = Self.lastError
            Darwin.close(fd)
            throw TCPSocketError.connectionFailed(message)
        }
        descriptor = fd
    }

    func readExactly(_ count: Int) throws -> Data {
        guard count >= 0 else { return Data() }
        var data = Data(count: count)
        var offset = 0
        try data.withUnsafeMutableBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            while offset < count {
                let received = Darwin.recv(descriptor, base.advanced(by: offset), count - offset, 0)
                if received == 0 { throw TCPSocketError.closed }
                if received < 0 {
                    if errno == EINTR { continue }
                    throw TCPSocketError.readFailed(Self.lastError)
                }
                offset += received
            }
        }
        return data
    }

    func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let written = Darwin.send(descriptor, base.advanced(by: offset), data.count - offset, 0)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw TCPSocketError.writeFailed(Self.lastError)
                }
                if written == 0 { throw TCPSocketError.closed }
                offset += written
            }
        }
    }

    func close() {
        stateLock.lock()
        guard !isClosed else {
            stateLock.unlock()
            return
        }
        isClosed = true
        stateLock.unlock()
        Darwin.shutdown(descriptor, SHUT_RDWR)
        Darwin.close(descriptor)
    }

    deinit {
        close()
    }

    private static var lastError: String {
        String(cString: strerror(errno))
    }
}

extension Data {
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    func bigEndianUInt16(at offset: Int) -> UInt16 {
        (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }

    func bigEndianUInt32(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }

    func bigEndianUInt64(at offset: Int) -> UInt64 {
        (UInt64(bigEndianUInt32(at: offset)) << 32) | UInt64(bigEndianUInt32(at: offset + 4))
    }
}
