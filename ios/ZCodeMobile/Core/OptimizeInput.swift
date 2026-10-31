import Foundation

/// 「优化输入」模型配置——对应桌面端 ~\.optimize-input.json 的手机版本。
/// 手机端保存在本机 UserDefaults，不与电脑共享文件。
struct OptimizeInputConfig: Codable, Equatable {
    var apiProtocol: String = "openai"      // "openai" | "anthropic"
    var baseURL: String = ""
    var apiKey: String = ""
    var model: String = ""
    var timeoutMs: Int = 60000
    var enabled: Bool = false

    static let storageKey = "optimizeInputConfig"

    static func load() -> OptimizeInputConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return OptimizeInputConfig() }
        return (try? JSONDecoder().decode(OptimizeInputConfig.self, from: data)) ?? OptimizeInputConfig()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    var isValid: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var timeoutInterval: TimeInterval { max(5, TimeInterval(timeoutMs) / 1000) }

    /// 规整：去掉末尾斜杠；用户把完整接口路径粘进来时不重复拼接。
    private var normalizedBase: String {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }

    var endpoint: String {
        let base = normalizedBase
        if apiProtocol == "anthropic" {
            return base.hasSuffix("/v1/messages") ? base : base + "/v1/messages"
        }
        return base.hasSuffix("/chat/completions") ? base : base + "/chat/completions"
    }
}

enum OptimizeInputError: LocalizedError {
    case invalidConfig
    case http(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidConfig: return "模型配置不完整"
        case .http(let code, let body): return "HTTP \(code)：\(body.prefix(120))"
        case .emptyResponse: return "模型没有返回内容"
        }
    }
}

/// 调用用户配置的模型，把草稿润色成更高质量的提示词。
struct OptimizeInputService {
    let config: OptimizeInputConfig

    private static let systemPrompt = """
    你是聊天输入优化助手。把用户发来的消息改写成更清晰、具体、结构化的提示词：
    - 保留原始意图与全部关键细节，不新增虚构需求
    - 修正口语化、含糊或重复的表述，可适当分点
    - 不要回答消息里的问题本身，只做改写
    只输出改写后的消息正文，不要任何解释、前缀或引号。
    """

    func optimize(_ text: String) async throws -> String {
        let output = try await complete(systemPrompt: Self.systemPrompt, userContent: text, maxTokens: 2048)
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OptimizeInputError.emptyResponse }
        return trimmed
    }

    /// 配置页的连通性测试。
    func testConnection() async throws -> String {
        try await complete(systemPrompt: "你是连通性测试助手。收到任何内容都只回复：连接正常",
                           userContent: "ping", maxTokens: 32)
    }

    private func complete(systemPrompt: String, userContent: String, maxTokens: Int) async throws -> String {
        guard config.isValid else { throw OptimizeInputError.invalidConfig }
        guard let url = URL(string: config.endpoint) else { throw OptimizeInputError.invalidConfig }
        var request = URLRequest(url: url, timeoutInterval: config.timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any]
        if config.apiProtocol == "anthropic" {
            request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = ["model": config.model,
                    "max_tokens": maxTokens,
                    "system": systemPrompt,
                    "messages": [["role": "user", "content": userContent]]]
        } else {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            body = ["model": config.model,
                    "temperature": 0.4,
                    "messages": [["role": "system", "content": systemPrompt],
                                 ["role": "user", "content": userContent]]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw OptimizeInputError.http(statusCode, detail)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OptimizeInputError.emptyResponse
        }
        // openai: choices[0].message.content
        if let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String, !content.isEmpty {
            return content
        }
        // anthropic: content[].text
        if let content = json["content"] as? [[String: Any]] {
            let text = content.compactMap { $0["text"] as? String }.joined()
            if !text.isEmpty { return text }
        }
        throw OptimizeInputError.emptyResponse
    }
}
