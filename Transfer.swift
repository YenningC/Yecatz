import AppKit
import CryptoKit
import Darwin
import Foundation
import Network
import SystemConfiguration

/// A one-use LAN invitation. The secret authenticates and encrypts the session.
struct TransferCode {
    let host: String
    let port: UInt16
    let secret: Data
    let digits: String?

    var text: String? {
        let octets = host.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4, secret.count == 16 else { return nil }
        var payload = Data([1] + octets + [UInt8(port >> 8), UInt8(port & 255)])
        payload.append(secret)
        return "YZ1-" + payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init(host: String, port: UInt16, secret: Data) {
        self.host = host
        self.port = port
        self.secret = secret
        self.digits = nil
    }

    init?(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.utf8.count == 8 && text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) {
            self.host = ""
            self.port = 0
            self.secret = Data(SHA256.hash(data: Data(("yecatz-short-v2:" + text).utf8)))
            self.digits = text
            return
        }
        guard text.hasPrefix("YZ1-") else { return nil }
        let raw = String(text.dropFirst(4)).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: raw + String(repeating: "=", count: (4 - raw.count % 4) % 4)),
              data.count == 23, data[0] == 1 else { return nil }
        let address = Array(data[1...4])
        guard address[0] != 0, address[0] < 224 else { return nil }
        let port = UInt16(data[5]) << 8 | UInt16(data[6])
        guard port > 0 else { return nil }
        self.host = address.map(String.init).joined(separator: ".")
        self.port = port
        self.secret = data.subdata(in: 7..<23)
        self.digits = nil
    }

    static func localIPv4() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var candidates: [(String, String)] = []
        var node = list
        while let current = node {
            defer { node = current.pointee.ifa_next }
            let item = current.pointee
            guard let address = item.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  item.ifa_flags & UInt32(IFF_UP) != 0,
                  item.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            let name = String(cString: item.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var addr = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
            guard inet_ntop(AF_INET, &addr, &buffer, socklen_t(buffer.count)) != nil else { continue }
            let ip = String(cString: buffer)
            guard !ip.hasPrefix("169.254.") else { continue }
            candidates.append((name, ip))
        }
        let state = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        if let primary = state?["PrimaryInterface"] as? String,
           let address = candidates.first(where: { $0.0 == primary })?.1 {
            return address
        }
        return candidates.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }.first?.1
    }
}

/// Discovery is local only; the short code is never sent directly.
private final class ShortCodeDiscovery {
    static let port: UInt16 = 47857
    private let lock = NSLock()
    private var stopped = false

    func stop() { lock.lock(); stopped = true; lock.unlock() }
    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    static func socketAddress(_ host: in_addr_t, _ port: UInt16) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: host)
        return address
    }

    static func digest(_ nonce: Data, _ code: String) -> Data {
        Data(SHA256.hash(data: Data("yecatz-discovery-v2:".utf8) + nonce + Data(code.utf8)))
    }

    func serve(code: String, port: UInt16, ready: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let fd = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
            guard fd >= 0 else { ready(false); return }
            defer { Darwin.close(fd) }
            var reuse: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))
            var timeout = timeval(tv_sec: 1, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
            var bindAddress = Self.socketAddress(in_addr_t(0), Self.port)
            let bound = withUnsafePointer(to: &bindAddress) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
            guard bound == 0 else { ready(false); return }
            ready(true)
            while !self.isStopped {
                var buffer = [UInt8](repeating: 0, count: 128)
                var source = sockaddr_in()
                var length = socklen_t(MemoryLayout<sockaddr_in>.size)
                let count = withUnsafeMutablePointer(to: &source) { p in
                    p.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buffer, buffer.count, 0, $0, &length) }
                }
                guard count == 52, Data(buffer[0..<4]) == Data("YZD2".utf8) else { continue }
                let nonce = Data(buffer[4..<20])
                guard Data(buffer[20..<52]) == Self.digest(nonce, code) else { continue }
                let response = Data("YZR2".utf8) + nonce + Data([UInt8(port >> 8), UInt8(port & 255)])
                response.withUnsafeBytes { bytes in
                    withUnsafePointer(to: &source) { p in
                        p.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = sendto(fd, bytes.baseAddress, bytes.count, 0, $0, length) }
                    }
                }
            }
        }
    }

    static func find(code: String) -> (String, UInt16)? {
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }
        var enabled: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout.size(ofValue: enabled)))
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        var nonce = Data(count: 16)
        guard nonce.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }) == errSecSuccess else { return nil }
        let query = Data("YZD2".utf8) + nonce + digest(nonce, code)
        var target = socketAddress(in_addr_t(INADDR_BROADCAST).bigEndian, port)
        for _ in 0..<5 {
            query.withUnsafeBytes { bytes in
                withUnsafePointer(to: &target) { p in
                    p.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
                }
            }
            var buffer = [UInt8](repeating: 0, count: 64)
            var source = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &source) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buffer, buffer.count, 0, $0, &length) }
            }
            guard count == 22, Data(buffer[0..<4]) == Data("YZR2".utf8), Data(buffer[4..<20]) == nonce else { continue }
            let tcpPort = UInt16(buffer[20]) << 8 | UInt16(buffer[21])
            var addr = source.sin_addr
            var output = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard tcpPort > 0, inet_ntop(AF_INET, &addr, &output, socklen_t(output.count)) != nil else { continue }
            return (String(cString: output), tcpPort)
        }
        return nil
    }
}

private struct TransferMessage: Codable {
    let type: String
    var name: String?
    var size: Int64?
    var data: String?
    var digest: String?
}

private enum TransferError: Error { case invalid, disconnected }

/// Each direction has a separate key and strictly increasing nonces.
struct TransferCipher {
    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    private let sendLabel: String
    private let receiveLabel: String
    private var sent: UInt64 = 0
    private var received: UInt64 = 0

    init(secret: Data, sessionNonce: Data, initiator: Bool) {
        let input = SymmetricKey(data: secret)
        let salt = Data("yecatz-lan-v1".utf8) + sessionNonce
        func derive(_ label: String) -> SymmetricKey {
            HKDF<SHA256>.deriveKey(inputKeyMaterial: input, salt: salt, info: Data(label.utf8), outputByteCount: 32)
        }
        sendLabel = initiator ? "client" : "host"
        receiveLabel = initiator ? "host" : "client"
        sendKey = derive(sendLabel)
        receiveKey = derive(initiator ? "host" : "client")
    }


    private func nonce(_ number: UInt64) throws -> ChaChaPoly.Nonce {
        var big = number.bigEndian
        return try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 4) + withUnsafeBytes(of: &big) { Data($0) })
    }

    mutating func seal(_ data: Data) throws -> Data {
        guard sent < UInt64.max else { throw TransferError.invalid }
        let box = try ChaChaPoly.seal(data, using: sendKey, nonce: nonce(sent),
                                     authenticating: Data(sendLabel.utf8))
        sent += 1
        return box.ciphertext + box.tag
    }

    mutating func open(_ data: Data) throws -> Data {
        guard data.count >= 16, received < UInt64.max else { throw TransferError.invalid }
        let box = try ChaChaPoly.SealedBox(nonce: nonce(received),
                                           ciphertext: data.dropLast(16), tag: data.suffix(16))
        let plain = try ChaChaPoly.open(box, using: receiveKey, authenticating: Data(receiveLabel.utf8))
        received += 1
        return plain
    }
}

final class TransferSession {
    enum State { case idle, waiting, connecting, connected }
    private let queue = DispatchQueue(label: "local.yecatz.transfer")
    private let maxFrame = 131_072
    private let maxFile: Int64 = 1_073_741_824
    private var listener: NWListener?
    private var discovery: ShortCodeDiscovery?
    private var connection: NWConnection?
    private var cipher: TransferCipher?
    private var handshakeSecret: Data?
    private var buffer = Data()
    private var state: State = .idle
    private var expiry: DispatchWorkItem?
    private var timeout: DispatchWorkItem?
    private var sender: FileHandle?
    private var senderName = ""
    private var sentSize: Int64 = 0
    private var senderHash = SHA256()
    private var receiver: FileHandle?
    private var destination: URL?
    private var temporary: URL?
    private var expectedSize: Int64 = 0
    private var receivedSize: Int64 = 0
    private var receiverHash = SHA256()
    private var offerPending = false
    private var isHost = false
    private var attempt = UUID()

    var onState: ((State) -> Void)?
    var onMessage: ((String) -> Void)?
    var onCode: ((String) -> Void)?
    var confirmPair: ((String, @escaping (Bool) -> Void) -> Void)?
    var chooseDestination: ((String, Int64, @escaping (URL?) -> Void) -> Void)?

    private func update(_ state: State) {
        self.state = state
        DispatchQueue.main.async { self.onState?(state) }
    }

    private func message(_ text: String) {
        DispatchQueue.main.async { self.onMessage?(text) }
    }

    func startHosting() {
        queue.async {
            self.reset()
            guard TransferCode.localIPv4() != nil else {
                self.message("没有找到可用的局域网地址。")
                return
            }
            let codeText = String(format: "%08u", arc4random_uniform(100_000_000))
            guard let code = TransferCode(codeText) else { return }
            let secret = code.secret
            do {
                let listener = try NWListener(using: .tcp)
                let token = UUID()
                self.attempt = token
                self.listener = listener
                self.isHost = true
                self.update(.waiting)
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self, self.attempt == token else { return }
                    switch state {
                    case .ready:
                        guard let port = listener?.port?.rawValue else {
                            self.fail("无法生成连接码。"); return
                        }
                        let discovery = ShortCodeDiscovery()
                        self.discovery = discovery
                        discovery.serve(code: codeText, port: port) { ready in
                            self.queue.async {
                                guard self.attempt == token else { discovery.stop(); return }
                                guard ready else { self.fail("无法开启局域网发现，请检查防火墙。"); return }
                                DispatchQueue.main.async { self.onCode?(codeText) }
                            }
                        }
                    case .failed:
                        self.fail("局域网连接不可用，请检查权限。")
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    guard let self, self.attempt == token, self.connection == nil else {
                        connection.cancel(); return
                    }
                    self.attach(connection, secret: secret, initiator: false, token: token)
                }
                listener.start(queue: self.queue)
                let expiration = DispatchWorkItem { [weak self] in
                    guard let self, self.attempt == token, self.state != .connected else { return }
                    self.fail("连接码已过期，请重新生成。")
                }
                self.expiry = expiration
                self.queue.asyncAfter(deadline: .now() + 300, execute: expiration)
            } catch {
                self.fail("无法开启局域网连接。")
            }
        }
    }

    func connect(_ code: TransferCode) {
        queue.async {
            self.reset()
            let token = UUID()
            self.attempt = token
            self.isHost = false
            self.update(.connecting)
            if let digits = code.digits {
                DispatchQueue.global(qos: .utility).async {
                    let found = ShortCodeDiscovery.find(code: digits)
                    self.queue.async {
                        guard self.attempt == token else { return }
                        guard let (host, number) = found, let port = NWEndpoint.Port(rawValue: number) else {
                            self.fail("找不到对方，请检查连接码、网络和防火墙。"); return
                        }
                        self.attach(NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp),
                                    secret: code.secret, initiator: true, token: token)
                    }
                }
            } else if let port = NWEndpoint.Port(rawValue: code.port) {
                self.attach(NWConnection(host: NWEndpoint.Host(code.host), port: port, using: .tcp),
                            secret: code.secret, initiator: true, token: token)
            }
        }
    }

    func disconnect() { queue.async { self.reset() } }

    func shutdown() { queue.sync { self.reset() } }

    private func attach(_ connection: NWConnection, secret: Data, initiator: Bool, token: UUID) {
        self.connection = connection
        self.handshakeSecret = initiator ? nil : secret
        var sessionNonce = Data(count: 16)
        if initiator {
            let status = sessionNonce.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
            guard status == errSecSuccess else { fail("无法建立安全连接。"); return }
            self.cipher = TransferCipher(secret: secret, sessionNonce: sessionNonce, initiator: true)
        } else {
            self.cipher = nil
        }
        self.buffer = Data()
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.attempt == token, self.state != .connected else { return }
            self.fail("连接超时。请确认两台设备能互访。")
        }
        timeout?.cancel()
        timeout = deadline
        queue.asyncAfter(deadline: .now() + 30, execute: deadline)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, self.attempt == token else { return }
            switch state {
            case .ready:
                self.receive(token)
                if initiator {
                    connection.send(content: Data("YH1".utf8) + sessionNonce, completion: .contentProcessed { error in
                        guard self.attempt == token else { return }
                        if error != nil { self.fail("无法建立安全连接。") }
                        else { self.send(.init(type: "hello", name: String((Host.current().localizedName ?? "另一台设备").prefix(100)))) }
                    })
                }
            case .failed, .cancelled:
                self.fail("连接已断开。")
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(_ token: UUID) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, finished, error in
            guard let self, self.attempt == token else { return }
            if let data { self.buffer.append(data) }
            do {
                if let secret = self.handshakeSecret, self.buffer.count >= 19 {
                    guard self.buffer.prefix(3) == Data("YH1".utf8) else { throw TransferError.invalid }
                    let nonce = Data(self.buffer[3..<19])
                    self.buffer.removeSubrange(0..<19)
                    self.cipher = TransferCipher(secret: secret, sessionNonce: nonce, initiator: false)
                    self.handshakeSecret = nil
                }
                if self.handshakeSecret != nil {
                    if finished || error != nil { self.fail("连接已断开。"); return }
                    self.receive(token)
                    return
                }
                while self.buffer.count >= 4 {
                    let count = self.buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
                    guard count >= 16, count <= self.maxFrame else { throw TransferError.invalid }
                    guard self.buffer.count >= 4 + count else { break }
                    let packet = Data(self.buffer[4..<(4 + count)])
                    self.buffer.removeSubrange(0..<(4 + count))
                    guard var cipher = self.cipher else { throw TransferError.invalid }
                    let plain = try cipher.open(packet)
                    self.cipher = cipher
                    let message = try JSONDecoder().decode(TransferMessage.self, from: plain)
                    try self.handle(message, token: token)
                }
                guard self.buffer.count <= self.maxFrame + 4 else { throw TransferError.invalid }
                if finished || error != nil { self.fail("连接已断开。"); return }
                self.receive(token)
            } catch {
                self.fail("连接验证失败或数据不完整。")
            }
        }
    }

    private func send(_ message: TransferMessage, completion: (() -> Void)? = nil) {
        do {
            guard var cipher, let connection else { throw TransferError.disconnected }
            let encrypted = try cipher.seal(JSONEncoder().encode(message))
            guard encrypted.count <= maxFrame else { throw TransferError.invalid }
            self.cipher = cipher
            var length = UInt32(encrypted.count).bigEndian
            let frame = withUnsafeBytes(of: &length) { Data($0) } + encrypted
            let token = attempt
            connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                guard let self, self.attempt == token else { return }
                if error != nil { self.fail("发送失败，连接已断开。") }
                else { completion?() }
            })
        } catch {
            fail("发送失败。")
        }
    }

    private func handle(_ message: TransferMessage, token: UUID) throws {
        switch message.type {
        case "hello":
            guard isHost, state == .waiting, let name = message.name, name.count <= 100 else { throw TransferError.invalid }
            update(.connecting)
            DispatchQueue.main.async {
                self.confirmPair?(name) { accepted in
                    self.queue.async {
                        guard self.attempt == token, self.state == .connecting else { return }
                        if accepted {
                            self.expiry?.cancel()
                            self.timeout?.cancel()
                            self.listener?.cancel()
                            self.listener = nil
                            self.discovery?.stop()
                            self.discovery = nil
                            self.send(.init(type: "paired"))
                            self.update(.connected)
                            self.message("已连接，可以把文件放进纸箱。")
                        } else {
                            self.send(.init(type: "pairRejected")) { self.reset() }
                        }
                    }
                }
            }
        case "paired":
            guard !isHost, state == .connecting else { throw TransferError.invalid }
            timeout?.cancel()
            update(.connected)
            self.message("已连接，可以把文件放进纸箱。")
        case "pairRejected":
            guard !isHost, state == .connecting else { throw TransferError.invalid }
            fail("对方没有接受连接。")
        case "offer":
            guard state == .connected,
                  let rawName = message.name, !rawName.isEmpty, rawName.utf8.count <= 255,
                  rawName != ".", rawName != "..", !rawName.contains("/"), !rawName.contains("\\"),
                  rawName.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }),
                  let size = message.size, size >= 0, size <= maxFile else { throw TransferError.invalid }
            if receiver != nil || sender != nil || offerPending {
                send(.init(type: "reject"))
                return
            }
            offerPending = true
            DispatchQueue.main.async {
                self.chooseDestination?(rawName, size) { url in
                    self.queue.async {
                        guard self.attempt == token, self.state == .connected, self.offerPending else { return }
                        self.offerPending = false
                        guard let url else { self.send(.init(type: "reject")); return }
                        do {
                            guard !FileManager.default.fileExists(atPath: url.path) else {
                                self.send(.init(type: "reject"))
                                self.message("目标文件已存在，请选择其他名称。")
                                return
                            }
                            let temp = url.deletingLastPathComponent().appendingPathComponent(".yecatz-\(UUID().uuidString).part")
                            guard FileManager.default.createFile(atPath: temp.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                                throw TransferError.invalid
                            }
                            self.temporary = temp
                            self.destination = url
                            self.receiver = try FileHandle(forWritingTo: temp)
                            self.expectedSize = size
                            self.receivedSize = 0
                            self.receiverHash = SHA256()
                            self.send(.init(type: "accept"))
                            self.message("正在接收 \(rawName)…")
                        } catch {
                            self.cleanupReceive()
                            self.send(.init(type: "reject"))
                            self.message("无法保存文件。")
                        }
                    }
                }
            }
        case "accept":
            guard state == .connected, sender != nil else { throw TransferError.invalid }
            messageText("正在发送 \(senderName)…")
            sendNextChunk()
        case "reject":
            guard sender != nil else { throw TransferError.invalid }
            cleanupSend()
            messageText("对方没有接收文件。")
        case "chunk":
            guard let file = receiver, let encoded = message.data,
                  let bytes = Data(base64Encoded: encoded), !bytes.isEmpty, bytes.count <= 32_768,
                  receivedSize + Int64(bytes.count) <= expectedSize else { throw TransferError.invalid }
            try file.write(contentsOf: bytes)
            receiverHash.update(data: bytes)
            receivedSize += Int64(bytes.count)
        case "done":
            guard let file = receiver, let destination, let temporary,
                  receivedSize == expectedSize, let digest = message.digest else { throw TransferError.invalid }
            try file.close()
            receiver = nil
            let actual = receiverHash.finalize().map { String(format: "%02x", $0) }.joined()
            guard actual == digest else { throw TransferError.invalid }
            try FileManager.default.moveItem(at: temporary, to: destination)
            self.temporary = nil
            self.destination = nil
            send(.init(type: "complete"))
            messageText("文件已接收。")
        case "complete":
            guard sender != nil else { throw TransferError.invalid }
            cleanupSend()
            messageText("文件已送达。")
        default:
            throw TransferError.invalid
        }
    }

    private func messageText(_ text: String) { message(text) }

    func sendFile(_ url: URL) {
        queue.async {
            guard self.state == .connected, self.sender == nil, self.receiver == nil, !self.offerPending else {
                self.message("正在传输，请稍等。"); return
            }
            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, let size = values.fileSize,
                      size >= 0, Int64(size) <= self.maxFile,
                      url.lastPathComponent.utf8.count <= 255 else {
                    self.message("请选择不超过 1 GB 的单个文件。"); return
                }
                self.sender = try FileHandle(forReadingFrom: url)
                self.senderName = url.lastPathComponent
                self.sentSize = Int64(size)
                self.senderHash = SHA256()
                self.send(.init(type: "offer", name: self.senderName, size: Int64(size)))
                self.message("等待对方接收…")
            } catch {
                self.cleanupSend()
                self.message("无法读取这个文件。")
            }
        }
    }

    private func sendNextChunk() {
        guard let sender else { return }
        do {
            let data = try sender.read(upToCount: 32_768) ?? Data()
            if data.isEmpty {
                let hash = senderHash.finalize().map { String(format: "%02x", $0) }.joined()
                send(.init(type: "done", digest: hash))
            } else {
                senderHash.update(data: data)
                send(.init(type: "chunk", data: data.base64EncodedString())) { [weak self] in self?.sendNextChunk() }
            }
        } catch {
            fail("读取文件失败，传输已取消。")
        }
    }

    private func cleanupSend() {
        try? sender?.close()
        sender = nil
        senderName = ""
        sentSize = 0
    }

    private func cleanupReceive() {
        try? receiver?.close()
        receiver = nil
        if let temporary { try? FileManager.default.removeItem(at: temporary) }
        temporary = nil
        destination = nil
        offerPending = false
    }

    private func fail(_ reason: String) {
        reset()
        message(reason)
    }

    private func reset() {
        attempt = UUID()
        expiry?.cancel()
        timeout?.cancel()
        expiry = nil
        timeout = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
        discovery?.stop()
        discovery = nil
        cipher = nil
        handshakeSecret = nil
        buffer.removeAll()
        cleanupSend()
        cleanupReceive()
        isHost = false
        update(.idle)
    }
}
