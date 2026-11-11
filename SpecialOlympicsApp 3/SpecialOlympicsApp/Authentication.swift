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
            try await SupabaseSync.shared.restoreSession()
            sharedProfile = try? await SupabaseSync.shared.fetchMyProfile()
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
        try await SupabaseSync.shared.signInOrCreate(email: user.email, password: password)
        currentUser = user
        onboardingRole = savedRole(for: user.email)
        sharedProfile = try? await SupabaseSync.shared.fetchMyProfile()
    }

    func saveOnboardingRole(_ role: MemberRole, for email: String) {
        UserDefaults.standard.set(role.rawValue, forKey: roleKey(for: email))
        onboardingRole = role
    }

    func saveOnboardingProfile(_ profile: OnboardingProfile, for email: String) async throws -> SharedProfile {
        saveOnboardingRole(profile.role, for: email)
        let encoded = try? JSONEncoder().encode(profile)
        UserDefaults.standard.set(encoded, forKey: profileKey(for: email))
        let remote = try await SupabaseSync.shared.saveProfile(
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
        await SupabaseSync.shared.signOut()
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
        let role = (payload?["role"] as? String ?? payload?["user_type"] as? String ?? "").lowercased()
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

/// This is deliberately the *publishable* Supabase key. Row-level security on
/// the database, rather than a secret embedded in the app, controls access.
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

actor SupabaseSync {
    static let shared = SupabaseSync()

    private let projectURL = URL(string: "https://oluzrysceqqcdyupuwhh.supabase.co")!
    private let publishableKey = "sb_publishable_Ze0IA7xGHtfnnxugkTsCHA_kMdwqhjm"
    private let sessionKey = "212so.supabase.session"
    private var auth: AuthSession?

    struct SyncError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct AuthSession: Codable {
        let accessToken: String
        let refreshToken: String
        let user: AuthUser

        enum CodingKeys: String, CodingKey {
            case user
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
        }
    }

    private struct AuthUser: Codable { let id: UUID }

    func restoreSession() async throws {
        guard let data = UserDefaults.standard.data(forKey: sessionKey) else { return }
        let saved = try JSONDecoder().decode(AuthSession.self, from: data)
        auth = try await authenticate(path: "/auth/v1/token?grant_type=refresh_token", body: ["refresh_token": saved.refreshToken])
        if let auth { UserDefaults.standard.set(try JSONEncoder().encode(auth), forKey: sessionKey) }
    }

    func signOut() {
        auth = nil
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

    func signInOrCreate(email: String, password: String) async throws {
        do {
            auth = try await authenticate(path: "/auth/v1/token?grant_type=password", body: ["email": email, "password": password])
        } catch {
            auth = try await authenticate(path: "/auth/v1/signup", body: ["email": email, "password": password])
        }
        guard let auth else { throw SyncError(message: "Could not start shared data sync.") }
        UserDefaults.standard.set(try JSONEncoder().encode(auth), forKey: sessionKey)
    }

    func fetchMyProfile() async throws -> SharedProfile? {
        guard let auth else { return nil }
        let items = try await rest("/rest/v1/profiles?select=*&id=eq.\(auth.user.id.uuidString)", method: "GET", body: Optional<Data>.none, as: [SharedProfile].self)
        return items.first
    }

    func saveProfile(name: String, phone: String, age: Int, role: MemberRole) async throws -> SharedProfile {
        let existing = try await fetchMyProfile()
        let roleValue = role == .athlete ? "Athlete" : "Volunteer"
        if existing == nil {
            return try await rpc("create_my_profile", values: [
                "p_display_name": name,
                "p_phone": phone,
                "p_age": age,
                "p_role": roleValue
            ], as: SharedProfile.self)
        }
        return try await rpc("update_my_profile", values: [
            "p_display_name": name,
            "p_phone": phone,
            "p_age": age
        ], as: SharedProfile.self)
    }

    func loadEvents() async throws -> [SharedEvent] {
        try await rest("/rest/v1/events?select=*&order=starts_at.asc", method: "GET", body: Optional<Data>.none, as: [SharedEvent].self)
    }

    func loadProfiles() async throws -> [SharedProfile] {
        try await rest("/rest/v1/profiles?select=*", method: "GET", body: Optional<Data>.none, as: [SharedProfile].self)
    }

    func loadUpdates() async throws -> [SharedUpdate] {
        try await rest("/rest/v1/updates?select=*&order=created_at.desc", method: "GET", body: Optional<Data>.none, as: [SharedUpdate].self)
    }

    func loadResponses() async throws -> [SharedResponse] {
        try await rest("/rest/v1/event_responses?select=*", method: "GET", body: Optional<Data>.none, as: [SharedResponse].self)
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
        _ = try await rest("/rest/v1/events", method: "POST", body: jsonData(payload), as: [SharedEvent].self)
    }

    func createUpdate(_ update: CommunityMessage) async throws {
        let payload: [String: Any] = [
            "id": update.id.uuidString,
            "title": update.title,
            "body": update.body,
            "sport": update.sport?.rawValue ?? NSNull()
        ]
        _ = try await rest("/rest/v1/updates", method: "POST", body: jsonData(payload), as: [SharedUpdate].self)
    }

    func setResponse(eventID: UUID, response: String) async throws {
        _ = try await rest("/rest/v1/event_responses?on_conflict=event_id,user_id", method: "POST", body: jsonData([
            "event_id": eventID.uuidString,
            "response": response
        ]), as: [SharedResponse].self, extraHeaders: ["Prefer": "resolution=merge-duplicates,return=representation"])
    }

    private func authenticate(path: String, body: [String: String]) async throws -> AuthSession {
        let data = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (responseData, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: responseData)
        return try decoder.decode(AuthSession.self, from: responseData)
    }

    private func rpc<T: Decodable>(_ name: String, values: [String: Any], as: T.Type) async throws -> T {
        try await rest("/rest/v1/rpc/\(name)", method: "POST", body: jsonData(values), as: T.self)
    }

    private func rest<T: Decodable>(_ path: String, method: String, body: Data?, as: T.Type, extraHeaders: [String: String] = [:]) async throws -> T {
        guard let auth else { throw SyncError(message: "Shared data session expired. Please sign in again.") }
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = method
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        extraHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
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
        URL(string: path, relativeTo: projectURL)!
    }

    private func jsonData(_ object: [String: Any]) -> Data { (try? JSONSerialization.data(withJSONObject: object)) ?? Data() }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
                ?? (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["msg"] as? String
                ?? "Could not sync shared data."
            throw SyncError(message: message)
        }
    }
}
