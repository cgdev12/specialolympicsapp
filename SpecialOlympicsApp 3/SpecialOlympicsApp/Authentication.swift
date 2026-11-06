import Foundation

/// Client for the hosted FastAPI template. Its HttpOnly session cookie is kept
/// in the shared cookie store, so no password or raw session value is persisted.
@MainActor
final class Authentication: ObservableObject {
    struct SessionUser: Equatable {
        let email: String
    }

    enum AuthenticationError: LocalizedError {
        case invalidResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "The server sent an unexpected response."
            case .server(let message): return message
            }
        }
    }

    @Published private(set) var currentUser: SessionUser?
    @Published private(set) var isWorking = false

    private let baseURL = URL(string: "https://fastapi-template-app-entxr.ondigitalocean.app")!
    private let appName = "212so"
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = true
        configuration.httpCookieStorage = .shared
        session = URLSession(configuration: configuration)
    }

    func restoreSession() async {
        do { currentUser = try await fetchCurrentUser() }
        catch { currentUser = nil }
    }

    func startSignUp(email: String, password: String) async throws {
        try await submit("/register", fields: ["email": email.trimmed, "password": password, "app_name": appName])
    }

    func verifySignUp(email: String, code: String) async throws {
        try await submit("/verify_email", fields: ["email": email.trimmed, "code": code, "app_name": appName])
    }

    func signIn(email: String, password: String) async throws {
        try await submit("/login", fields: ["email": email.trimmed, "password": password, "app_name": appName])
        currentUser = try await fetchCurrentUser()
    }

    func signOut() async {
        _ = try? await submit("/logout", fields: [:])
        currentUser = nil
    }

    private func fetchCurrentUser() async throws -> SessionUser {
        let (data, response) = try await session.data(from: baseURL.appending(path: "/me"))
        try validate(response: response, data: data)
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let email = payload?["email"] as? String else { throw AuthenticationError.invalidResponse }
        return SessionUser(email: email)
    }

    private func submit(_ path: String, fields: [String: String]) async throws {
        isWorking = true
        defer { isWorking = false }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(fields)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
    }

    private func formBody(_ fields: [String: String]) -> Data? {
        fields.map { "\(escape($0.key))=\(escape($0.value))" }.joined(separator: "&").data(using: .utf8)
    }

    private func escape(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else { throw AuthenticationError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw AuthenticationError.server(json?["detail"] as? String ?? "Unable to complete that request.")
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
