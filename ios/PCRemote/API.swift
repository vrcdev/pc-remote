import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum API {
    private static let cacheKey = "cachedCommandNames"

    private static func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        let d = UserDefaults.standard
        let host = (d.string(forKey: "host") ?? "").trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { throw APIError(message: "Set your PC address in the app first.") }
        let port = d.string(forKey: "port") ?? "8765"
        guard let url = URL(string: "http://\(host):\(port)\(path)") else {
            throw APIError(message: "Bad PC address.")
        }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = method
        req.setValue(d.string(forKey: "token") ?? "", forHTTPHeaderField: "X-Token")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { throw APIError(message: "Wrong token.") }
            if !(200..<300).contains(code) {
                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                throw APIError(message: msg ?? "PC returned error \(code).")
            }
            return data
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError(message: "Can't reach your PC. Is Tailscale on and the server running?")
        }
    }

    private static func encodedName(_ name: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        return name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
    }

    static func ping() async throws {
        _ = try await request("/ping")
    }

    static func list() async throws -> [Command] {
        struct Resp: Decodable { let commands: [String: [Step]] }
        let data = try await request("/commands")
        let r = try JSONDecoder().decode(Resp.self, from: data)
        let cmds = r.commands.map { Command(name: $0.key, steps: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        UserDefaults.standard.set(cmds.map(\.name), forKey: cacheKey)
        return cmds
    }

    private struct AppsResp: Decodable { let apps: [InstalledApp] }

    static func installedApps() async throws -> [InstalledApp] {
        try JSONDecoder().decode(AppsResp.self, from: try await request("/apps")).apps
    }

    static func runningApps() async throws -> [InstalledApp] {
        try JSONDecoder().decode(AppsResp.self, from: try await request("/running")).apps
    }

    static func cachedNames() -> [String] {
        UserDefaults.standard.stringArray(forKey: cacheKey) ?? []
    }

    static func save(_ c: Command) async throws {
        struct Body: Encodable { let steps: [Step] }
        let body = try JSONEncoder().encode(Body(steps: c.steps))
        _ = try await request("/commands/\(encodedName(c.name))", method: "PUT", body: body)
    }

    static func delete(_ name: String) async throws {
        _ = try await request("/commands/\(encodedName(name))", method: "DELETE")
    }

    static func run(_ name: String) async throws {
        _ = try await request("/run/\(encodedName(name))", method: "POST")
    }
}
