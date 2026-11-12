import Foundation
import Security

struct ChatMessage: Identifiable, Encodable {
    let id = UUID()
    let role: String
    let content: String

    enum CodingKeys: String, CodingKey { case role, content }
}

enum ChatKeychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "local.yecatz.chat.openrouter",
        kSecAttrAccount as String: "API key"
    ]

    static func read() -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) -> Bool {
        let value = [kSecValueData as String: Data(key.utf8)]
        let updated = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        return SecItemAdd(query.merging(value) { old, _ in old } as CFDictionary, nil) == errSecSuccess
    }

    static func remove() -> Bool {
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

enum ChatAPI {
    static let keysPage = URL(string: "https://openrouter.ai/settings/keys")!
    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private static let session = URLSession(configuration: .ephemeral)

    private struct Body: Encodable {
        let model = "openrouter/free"
        let stream = true
        let temperature = 0.7
        let max_tokens = 280
        let messages: [ChatMessage]
    }

    private struct Event: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta?
            let finish_reason: String?
        }

        struct APIError: Decodable { let code: Int? }
        let error: APIError?
        let choices: [Choice]?
    }

    enum Failure: LocalizedError {
        case http(Int), incomplete, empty

        var errorDescription: String? {
            switch self {
            case .http(401), .http(403): return "API 密钥无效或没有权限，请检查设置。"
            case .http(402): return "OpenRouter 拒绝了此次请求，请检查账号状态。"
            case .http(429): return "免费额度已用完或请求太频繁，过一会儿再试。"
            case .http(404), .http(502), .http(503):
                return "免费模型暂时不可用，请稍后重试。"
            case .http(let code): return "API 请求失败（\(code)），请稍后重试。"
            case .incomplete: return "回复中断了，请重试。"
            case .empty: return "Yecatz 没有回话，再试一次。"
            }
        }
    }

    static func request(key: String, messages: [ChatMessage]) throws -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(Body(messages: messages))
        return request
    }

    static func stream(key: String, messages: [ChatMessage], onText: (String) -> Void) async throws {
        let (bytes, response) = try await session.bytes(for: request(key: key, messages: messages))
        guard let http = response as? HTTPURLResponse else { throw Failure.incomplete }
        guard (200..<300).contains(http.statusCode) else { throw Failure.http(http.statusCode) }
        try await consume(bytes.lines, onText: onText)
    }

    static func consume<Lines: AsyncSequence>(_ lines: Lines, onText: (String) -> Void) async throws where Lines.Element == String {
        var wroteText = false
        var finished = false
        for try await line in lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload == "[DONE]" {
                finished = true
                break
            }
            guard !payload.isEmpty else { continue }
            let event = try JSONDecoder().decode(Event.self, from: Data(payload.utf8))
            if let error = event.error {
                if let code = error.code { throw Failure.http(code) }
                throw Failure.incomplete
            }
            for choice in event.choices ?? [] {
                if choice.finish_reason == "error" { throw Failure.incomplete }
                if choice.finish_reason != nil { finished = true }
                if let text = choice.delta?.content, !text.isEmpty {
                    wroteText = wroteText || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    onText(text)
                }
            }
        }
        guard finished else { throw Failure.incomplete }
        guard wroteText else { throw Failure.empty }
    }
}
