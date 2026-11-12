import Foundation

/// Client for the hosted FastAPI template. Its HttpOnly session cookie is kept
/// in the shared cookie store, so no password or raw session value is persisted.
@MainActor
final class Authentication: ObservableObject {
    struct SessionUser: Equatable {
        let email: String
        /// The FastAPI account type for this app. The public `/me` response
        /// only guarantees an email, so we also check the protected user list
        /// when the signed-in person is an administrator.
        let isAdmin: Bool
    }

    struct OnboardingProfile: Codable, Equatable {
        let role: MemberRole
        let name: String
        let age: Int
        let phone: String
        let organization: String
        /// Head Coach access cannot be granted by the public sign-up endpoint.
        /// It remains a request until an authorized backend approval changes
        /// the account role to `.admin`.
        let requestedHeadCoach: Bool?
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
    @Published private(set) var sharedProfile: SharedProfile?
    /// The role chosen during account creation. The hosted authentication API
    /// does not accept a role on `/register`, so the app retains it locally
    /// for the profile-onboarding flow after email verification.
    @Published private(set) var onboardingRole: MemberRole?
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
        do {
            let user = try await fetchCurrentUser()
            currentUser = user
            onboardingRole = savedRole(for: user.email)
            try await SharedDataSync.shared.restoreSession()
            sharedProfile = try? await SharedDataSync.shared.fetchMyProfile()
        }
        catch {
            currentUser = nil
            sharedProfile = nil
        }
    }

    func startSignUp(email: String, password: String) async throws {
        try await submit("/register", fields: ["email": email.trimmed, "password": password, "app_name": appName])
    }

    func verifySignUp(email: String, code: String) async throws {
        try await submit("/verify_email", fields: ["email": email.trimmed, "code": code, "app_name": appName])
    }

    func signIn(email: String, password: String) async throws {
        try await submit("/login", fields: ["email": email.trimmed, "password": password, "app_name": appName])
        let user = try await fetchCurrentUser()
        try await SharedDataSync.shared.signInOrCreate(email: user.email, password: password)
        currentUser = user
        onboardingRole = savedRole(for: user.email)
        sharedProfile = try? await SharedDataSync.shared.fetchMyProfile()
    }

    func saveOnboardingRole(_ role: MemberRole, for email: String) {
        UserDefaults.standard.set(role.rawValue, forKey: roleKey(for: email))
        onboardingRole = role
    }

    func saveOnboardingProfile(_ profile: OnboardingProfile, for email: String) async throws -> SharedProfile {
        saveOnboardingRole(profile.role, for: email)
        let encoded = try? JSONEncoder().encode(profile)
        UserDefaults.standard.set(encoded, forKey: profileKey(for: email))
        let remote = try await SharedDataSync.shared.saveProfile(
            name: profile.name,
            phone: profile.phone,
            age: profile.age,
            role: profile.role
        )
        sharedProfile = remote
        return remote
    }

    func savedOnboardingProfile(for email: String) -> OnboardingProfile? {
        guard let data = UserDefaults.standard.data(forKey: profileKey(for: email)) else { return nil }
        return try? JSONDecoder().decode(OnboardingProfile.self, from: data)
    }

    /// Removes only the profile stored on this device. The real 212so account
    /// and its active session remain intact so the user can immediately enter
    /// corrected role and contact information.
    func resetOnboardingProfile(for email: String) {
        UserDefaults.standard.removeObject(forKey: profileKey(for: email))
        UserDefaults.standard.removeObject(forKey: roleKey(for: email))
        onboardingRole = nil
    }

    func requestPasswordReset(email: String) async throws {
        try await submit("/reset_password", fields: ["email": email.trimmed])
    }

    func confirmPasswordReset(email: String, code: String, newPassword: String) async throws {
        try await submit("/confirm_reset_password", fields: [
            "email": email.trimmed,
            "code": code,
            "new_password": newPassword
        ])
    }

    func signOut() async {
        _ = try? await submit("/logout", fields: [:])
        await SharedDataSync.shared.signOut()
        clearSessionCookies()
        currentUser = nil
        sharedProfile = nil
        onboardingRole = nil
    }

    private func clearSessionCookies() {
        guard let host = baseURL.host else { return }
        for cookie in session.configuration.httpCookieStorage?.cookies ?? [] where cookie.domain.contains(host) {
            session.configuration.httpCookieStorage?.deleteCookie(cookie)
        }
    }

    private func roleKey(for email: String) -> String {
        "212so.onboarding-role.\(email.trimmed.lowercased())"
    }

    private func profileKey(for email: String) -> String {
        "212so.onboarding-profile.\(email.trimmed.lowercased())"
    }

    private func savedRole(for email: String) -> MemberRole? {
        UserDefaults.standard.string(forKey: roleKey(for: email)).flatMap(MemberRole.init(rawValue:))
    }

    private func fetchCurrentUser() async throws -> SessionUser {
        let (data, response) = try await session.data(from: baseURL.appending(path: "/me"))
        try validate(response: response, data: data)
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let email = payload?["email"] as? String else { throw AuthenticationError.invalidResponse }
        let role = (payload?["role"] as? String ?? payload?["user_type"] as? String ?? payload?["type"] as? String ?? "").lowercased()
        let isAdmin: Bool
        if role == "admin" {
            isAdmin = true
        } else {
            isAdmin = await hasAdminRole(email: email)
        }
        return SessionUser(email: email, isAdmin: isAdmin)
    }

    /// The current backend does not return an app role from `/me`. An admin is
    /// allowed to read the app's user list, so use that protected route to
    /// recognize a Head Coach account on every sign-in. Non-admins receive a
    /// forbidden response and safely remain in their selected app role.
    private func hasAdminRole(email: String) async -> Bool {
        var components = URLComponents(url: baseURL.appending(path: "/admin/users"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "app_name", value: appName)]
        guard let url = components?.url else { return false }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else { return false }
            let json = try JSONSerialization.jsonObject(with: data)
            return roleIsAdmin(for: email, in: json)
        } catch {
            return false
        }
    }

    private func roleIsAdmin(for email: String, in value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            let storedEmail = (dictionary["email"] as? String ?? dictionary["target_email"] as? String ?? "").trimmed.lowercased()
            if storedEmail == email.trimmed.lowercased() {
                let role = (dictionary["role"] as? String ?? dictionary["user_type"] as? String ?? dictionary["type"] as? String ?? "").lowercased()
                if role == "admin" { return true }
            }
            return dictionary.values.contains { roleIsAdmin(for: email, in: $0) }
        }
        if let array = value as? [Any] {
            return array.contains { roleIsAdmin(for: email, in: $0) }
        }
        return false
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

// MARK: - Shared 212so data

/// Shared 212SO data returned by the authenticated FastAPI service.
struct SharedProfile: Codable, Equatable {
    let id: UUID
    let email: String
    let displayName: String
    let phone: String
    let age: Int
    let role: String

    enum CodingKeys: String, CodingKey {
        case id, email, phone, age, role
        case displayName = "display_name"
    }

    var memberRole: MemberRole {
        switch role.lowercased() {
        case "admin": return .admin
        case "athlete": return .athlete
        default: return .volunteer
        }
    }
}

struct SharedEvent: Codable {
    let id: UUID
    let title: String
    let startsAt: Date
    let location: String
    let sport: String?
    let reminderMinutes: Int

    enum CodingKeys: String, CodingKey {
        case id, title, location, sport
        case startsAt = "starts_at"
        case reminderMinutes = "reminder_minutes"
    }
}

struct SharedUpdate: Codable {
    let id: UUID
    let title: String
    let body: String
    let sport: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, body, sport
        case createdAt = "created_at"
    }
}

struct SharedResponse: Codable {
    let eventID: UUID
    let userID: UUID
    let response: String

    enum CodingKeys: String, CodingKey {
        case response
        case eventID = "event_id"
        case userID = "user_id"
    }
}

actor SharedDataSync {
    static let shared = SharedDataSync()

    private let baseURL = URL(string: "https://fastapi-template-app-entxr.ondigitalocean.app")!

    struct SyncError: LocalizedError {
        let message: String
        let statusCode: Int?
        var errorDescription: String? { message }
    }

    func restoreSession() async throws {
        // The FastAPI HttpOnly cookie is the single session to restore.
    }

    func signOut() {
        // Authentication.signOut clears the FastAPI cookie.
    }

    func signInOrCreate(email: String, password: String) async throws {
        // Authentication.signIn has already set the FastAPI cookie.
    }

    func fetchMyProfile() async throws -> SharedProfile? {
        do { return try await request("/212so/profile", method: "GET", body: nil, as: SharedProfile.self) }
        catch let error as SyncError where error.statusCode == 404 { return nil }
    }

    func saveProfile(name: String, phone: String, age: Int, role: MemberRole) async throws -> SharedProfile {
        let roleValue = role == .athlete ? "Athlete" : "Volunteer"
        return try await request("/212so/profile", method: "PUT", body: jsonData([
            "display_name": name, "phone": phone, "age": age, "role": roleValue
        ]), as: SharedProfile.self)
    }

    func loadEvents() async throws -> [SharedEvent] {
        try await request("/212so/events", method: "GET", body: nil, as: [SharedEvent].self)
    }

    func loadProfiles() async throws -> [SharedProfile] {
        try await request("/212so/profiles", method: "GET", body: nil, as: [SharedProfile].self)
    }

    func loadUpdates() async throws -> [SharedUpdate] {
        try await request("/212so/updates", method: "GET", body: nil, as: [SharedUpdate].self)
    }

    func loadResponses() async throws -> [SharedResponse] {
        try await request("/212so/responses", method: "GET", body: nil, as: [SharedResponse].self)
    }

    func createEvent(_ event: Event) async throws {
        let payload: [String: Any] = [
            "id": event.id.uuidString,
            "title": event.title,
            "starts_at": ISO8601DateFormatter().string(from: event.date),
            "location": event.location,
            "sport": event.sport?.rawValue ?? NSNull(),
            "reminder_minutes": event.reminderMinutes
        ]
        _ = try await request("/212so/events", method: "POST", body: jsonData(payload), as: SharedEvent.self)
    }

    func createUpdate(_ update: CommunityMessage) async throws {
        let payload: [String: Any] = [
            "id": update.id.uuidString,
            "title": update.title,
            "body": update.body,
            "sport": update.sport?.rawValue ?? NSNull()
        ]
        _ = try await request("/212so/updates", method: "POST", body: jsonData(payload), as: SharedUpdate.self)
    }

    func setResponse(eventID: UUID, response: String) async throws {
        _ = try await request("/212so/responses", method: "PUT", body: jsonData([
            "event_id": eventID.uuidString,
            "response": response
        ]), as: SharedResponse.self)
    }

    private func request<T: Decodable>(_ path: String, method: String, body: Data?, as: T.Type) async throws -> T {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) ?? Date()
        }
        return decoder
    }

    private func endpoint(_ path: String) -> URL {
        URL(string: path, relativeTo: baseURL)!
    }

    private func jsonData(_ object: [String: Any]) -> Data { (try? JSONSerialization.data(withJSONObject: object)) ?? Data() }

    private func validate(_ response: URLResponse, data: Data) throws {
        let statusCode = (response as? HTTPURLResponse)?.statusCode
        guard let statusCode, (200..<300).contains(statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
                ?? (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
                ?? "Could not sync shared data."
            throw SyncError(message: message, statusCode: statusCode)
        }
    }
}
