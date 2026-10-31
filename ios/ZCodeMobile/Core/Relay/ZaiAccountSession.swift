import Foundation
import Security

/// 桌面版 ≥3.16 的账号令牌配对：手机端用与电脑相同的 z.ai / BigModel 账号
/// 完成 OAuth 设备码登录，换取账号 JWT，再在线换取 60 秒短时终端令牌。
/// JWT 存钥匙串；终端令牌不落盘，每次连接现取。
public enum ZaiAccountSession {
    public static let baseURL = URL(string: "https://zcode.z.ai")!
    private static let keychainService = "dev.paco.zcode.mobile.account"
    private static let keychainAccount = "zcode-jwt"

    public struct LoginFlow: Sendable {
        public let flowID: String
        public let authorizeURL: URL
        public let proof: String
        public let expiresAt: Date
        public let pollInterval: TimeInterval
    }

    public struct LoginPoll: Sendable {
        public enum Status: Sendable { case pending, ready, failed }
        public let status: Status
        public let jwt: String?
        public let userName: String?
    }

    // MARK: - 钥匙串

    public static var isLoggedIn: Bool { loadJWT() != nil }

    public static func loadJWT() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func saveJWT(_ jwt: String) {
        guard !jwt.isEmpty else { return }
        var query = baseQuery()
        let update: [String: Any] = [kSecValueData as String: Data(jwt.utf8)]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            query[kSecValueData as String] = Data(jwt.utf8)
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    public static func clearJWT() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: keychainAccount]
    }

    // MARK: - OAuth 设备码登录（与桌面版 / CLI 同链路）

    public static func beginLogin(provider: String) async throws -> LoginFlow {
        let proof = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/oauth/cli/init"), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(proof)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["provider": provider])
        let object = try await fetchJSON(request)
        guard object["code"].integer == 0, let data = object["data"].object,
              let flowID = data["flow_id"]?.string, flowID.count <= 256,
              let authorize = data["authorize_url"]?.string, let authorizeURL = URL(string: authorize),
              authorizeURL.scheme == "https",
              let expiresAt = data["expires_at"]?.number, expiresAt > 0,
              let interval = data["poll_interval_sec"]?.number, interval >= 1 else {
            throw RelayFailure("account_login_init_failed", "无法发起账号登录，请稍后重试。")
        }
        return LoginFlow(flowID: flowID, authorizeURL: authorizeURL, proof: proof,
                         expiresAt: Date(timeIntervalSince1970: expiresAt),
                         pollInterval: max(2, interval))
    }

    public static func pollLogin(_ flow: LoginFlow) async throws -> LoginPoll {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/oauth/cli/poll/\(flow.flowID)"), timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("Bearer \(flow.proof)", forHTTPHeaderField: "Authorization")
        let object = try await fetchJSON(request)
        guard object["code"].integer == 0, let data = object["data"].object else {
            throw RelayFailure("account_login_poll_failed", "账号登录查询失败，请重试。")
        }
        let status = data["status"]?.string ?? "pending"
        if status == "ready" {
            let jwt = data["token"]?.string ?? ""
            guard !jwt.isEmpty, jwt.utf8.count <= 8192 else {
                throw RelayFailure("account_login_failed", "登录响应无效，请重试。")
            }
            saveJWT(jwt)
            let name = data["user"]?.object?["name"]?.string ?? data["user"]?.object?["email"]?.string
            return LoginPoll(status: .ready, jwt: jwt, userName: name)
        }
        if status == "failed" { return LoginPoll(status: .failed, jwt: nil, userName: nil) }
        return LoginPoll(status: .pending, jwt: nil, userName: nil)
    }

    // MARK: - 终端令牌（60 秒有效，连接前现取）

    public static func terminalToken(jwt: String) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/remote/token"), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["role": "terminal"])
        let object = try await fetchJSON(request)
        guard object["code"].integer == 0, let data = object["data"].object, let token = data["token"]?.string, !token.isEmpty else {
            throw RelayFailure("account_token_failed", "无法获取连接令牌，请重新登录账号。")
        }
        return token
    }

    public static func terminalToken() async throws -> String {
        guard let jwt = loadJWT() else {
            throw RelayFailure("account_login_required", "此二维码来自新版桌面端，需要先登录与电脑相同的 z.ai / BigModel 账号。")
        }
        return try await terminalToken(jwt: jwt)
    }

    private static func fetchJSON(_ request: URLRequest) async throws -> RelayJSON {
        let (data, _) = try await URLSession.shared.data(for: request)
        return try RelayJSON(data: data)
    }
}
