import Foundation

/// Hermes Web Dashboard HTTP 客户端 — 用于调用仪表盘管理端点。
///
/// 管理端点族（/api/config、/api/env、/api/skills、/api/tools/toolsets 等）
/// 由 `hermes dashboard` 在本地 Web 服务器上提供，默认端口 9119。
/// 认证使用与 Gateway 相同的 `API_SERVER_KEY`（Bearer）。
final class DashboardClient {

    /// 全局共享实例。
    static let shared = DashboardClient()

    private let host: String
    private let port: Int
    private let session: URLSession

    init(
        host: String = "127.0.0.1",
        port: Int = 9119,
        session: URLSession = .shared
    ) {
        self.host = host
        self.port = port
        self.session = session
    }

    /// Dashboard base URL，例如 `http://127.0.0.1:9119`。
    var baseUrl: String { "http://\(host):\(port)" }

    // MARK: - Skills

    /// 拉取所有技能（`GET /api/skills`）。
    ///
    /// 返回解析后的技能字典数组，每个字典包含 `name`、`description`、
    /// `category`、`enabled` 等字段；若请求失败返回 `nil`。
    func getSkills() async -> [[String: Any]]? {
        guard let json = await getJson("/api/skills") else { return nil }
        if let dict = json as? [String: Any], let skills = dict["skills"] as? [[String: Any]] {
            return skills
        }
        // 兼容直接返回数组的情况。
        if let skills = json as? [[String: Any]] {
            return skills
        }
        let diagnostic: String
        if let dict = json as? [String: Any] {
            diagnostic = "keys=\(dict.keys.sorted())"
        } else if let arr = json as? [Any] {
            diagnostic = "array.count=\(arr.count)"
        } else {
            diagnostic = "type=\(type(of: json))"
        }
        DMLogger.log(
            "DashboardClient: /api/skills 响应中没有 skills 数组，\(diagnostic)",
            name: "DashboardClient"
        )
        return nil
    }

    /// 启用或禁用技能（`PUT /api/skills/toggle`）。
    ///
    /// - Parameters:
    ///   - name: 技能名称。
    ///   - enabled: 目标启用状态。
    /// - Returns: 是否成功（HTTP 2xx）。
    func toggleSkill(name: String, enabled: Bool) async -> Bool {
        guard let url = URL(string: baseUrl + "/api/skills/toggle") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        applyAuth(&req)

        let body: [String: Any] = ["name": name, "enabled": enabled]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        DMLogger.log(
            "DashboardClient: PUT /api/skills/toggle name=\(name) enabled=\(enabled)",
            name: "DashboardClient"
        )

        do {
            let (_, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return false }
            let ok = (200..<300).contains(http.statusCode)
            if !ok {
                DMLogger.log(
                    "DashboardClient: toggleSkill HTTP \(http.statusCode)",
                    name: "DashboardClient"
                )
            }
            return ok
        } catch {
            DMLogger.error(
                "DashboardClient: toggleSkill failed \(error.localizedDescription)",
                name: "DashboardClient"
            )
            return false
        }
    }

    // MARK: - Private

    /// GET 一个 JSON 端点并返回原始对象（字典或数组）。
    private func getJson(_ path: String) async -> Any? {
        guard let url = URL(string: baseUrl + path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyAuth(&req)

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return nil }
            guard (200..<300).contains(http.statusCode) else {
                DMLogger.log("DashboardClient: GET \(path) → HTTP \(http.statusCode)", name: "DashboardClient")
                return nil
            }
            return try? JSONSerialization.jsonObject(with: data)
        } catch {
            DMLogger.error("DashboardClient: GET \(path) failed \(error.localizedDescription)", name: "DashboardClient")
            return nil
        }
    }

    private func applyAuth(_ req: inout URLRequest) {
        // Hermes Dashboard / serve 在 loopback 模式下使用 HERMES_DASHBOARD_SESSION_TOKEN
        // 作为 Bearer token；该 token 由 HermesDashboardService 生成并注入子进程。
        if let token = HermesDashboardService.shared.sessionToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return
        }
        // 兜底：若 session token 未生成，仍尝试 Gateway 的 API_SERVER_KEY。
        if let key = HermesGatewayService.shared.apiServerKey, !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
    }
}
