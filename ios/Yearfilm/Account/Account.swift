import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Supabase

/// Who is signed in, and their family. An account exists for backup and for making a film
/// together: the app works fully without one, and signing in uploads nothing and creates no
/// family by itself.
@MainActor
@Observable
final class Account {
    static let shared = Account()

    struct Family: Decodable, Equatable {
        let id: UUID
        let name: String
        let role: String
        /// A contributor may be limited to some weeks of one year's film.
        let weeks: [Int]?
        let year: Int?

        var isProducer: Bool { role == "producer" }

        /// Whether something filmed in `week` may be added to this family's film.
        func allows(_ week: FilmWeek) -> Bool {
            guard role != "viewer" else { return false }
            guard let weeks else { return true }
            return week.year == year && weeks.contains(week.week)
        }
    }

    private(set) var userID: UUID?
    private(set) var family: Family?
    private(set) var displayName: String?
    /// An invite link the app was opened with, waiting to be shown.
    var pendingInvite: PendingInvite?
    var isSignedIn: Bool { userID != nil }

    @ObservationIgnored private let client: SupabaseClient?
    @ObservationIgnored private var nonce: String?

    private init() {
        let info = Bundle.main.infoDictionary
        if let url = (info?["YFSupabaseURL"] as? String).flatMap(URL.init(string:)),
           let key = info?["YFSupabaseKey"] as? String {
            client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        } else {
            client = nil
        }
    }

    /// Picks up a session saved in the keychain from a previous launch.
    func restore() async {
        guard let session = try? await client?.auth.session else { return }
        userID = session.user.id
        try? await refresh()
    }

    func refresh() async throws {
        family = try await fetchFamily()
        let profile: Profile = try await API.request("GET", "/api/profile")
        displayName = profile.displayName
    }

    func accessToken() async -> String? {
        try? await client?.auth.session.accessToken
    }

    // MARK: Sign in with Apple

    /// Configures the Apple request. No name or email is asked for.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let raw = Self.randomNonce()
        nonce = raw
        request.requestedScopes = []
        request.nonce = Self.sha256(raw)
    }

    func signIn(_ result: Result<ASAuthorization, Error>) async throws {
        guard let client else { throw API.Failure(status: 0, message: "Accounts aren’t set up in this build.") }
        guard let credential = try result.get().credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              let nonce
        else { throw API.Failure(status: 0, message: "Apple didn’t return a sign-in token. Try again.") }

        let session = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
        self.nonce = nil
        userID = session.user.id
        try? await refresh()
    }

    func signOut() async {
        try? await client?.auth.signOut()
        userID = nil
        family = nil
        displayName = nil
    }

    /// Deletes the account and, if they're the family's last producer, every clip and note
    /// stored for the family. Local copies on this iPhone are kept.
    func deleteAccount() async throws {
        let _: OK = try await API.request("DELETE", "/api/account")
        await signOut()
    }

    // MARK: Profile and family

    private struct FamilyResponse: Decodable { let family: Family? }
    private struct Name: Encodable { let name: String }
    private struct Profile: Codable { let displayName: String? }
    private struct OK: Decodable { let ok: Bool }

    struct Member: Decodable, Identifiable, Equatable {
        let id: UUID
        let name: String?
        let role: String
        let weeks: [Int]?
        let year: Int?
        let isYou: Bool
    }

    private func fetchFamily() async throws -> Family? {
        let response: FamilyResponse = try await API.request("GET", "/api/family")
        return response.family
    }

    /// Starts a family with this person as its producer. Only when they turn on backup
    /// without having joined someone else's film.
    func startFamily(named name: String) async throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let response: FamilyResponse = try await API.request(
            "POST", "/api/family", json: Name(name: clean.isEmpty ? "Our family" : clean)
        )
        family = response.family
    }

    func renameFamily(_ name: String) async throws {
        let response: FamilyResponse = try await API.request("PATCH", "/api/family", json: Name(name: name))
        family = response.family
    }

    func setDisplayName(_ name: String) async throws {
        let profile: Profile = try await API.request("PUT", "/api/profile", json: Profile(displayName: name))
        displayName = profile.displayName
    }

    func members() async throws -> [Member] {
        struct Response: Decodable { let members: [Member] }
        let response: Response = try await API.request("GET", "/api/family/members")
        return response.members
    }

    // MARK: Invites

    struct Invite: Decodable, Identifiable, Equatable {
        let id: UUID
        let role: String
        let weeks: [Int]?
        let year: Int?
        let expiresAt: String
        let uses: Int
        let state: String
    }

    struct NewInvite: Decodable {
        let id: UUID
        let url: URL
    }

    struct InvitePreview: Decodable {
        let familyName: String
        let invitedBy: String?
        let role: String
        let weeks: [Int]?
        let year: Int?
        let state: String
    }

    struct PendingInvite: Identifiable, Equatable {
        let token: String
        var id: String { token }

        /// yearfilm://join/<token> or https://www.yearfilm.com/join/<token>
        init?(url: URL) {
            let parts = (url.scheme == "yearfilm" ? [url.host ?? ""] + url.pathComponents : url.pathComponents)
                .filter { $0 != "/" && !$0.isEmpty }
            guard parts.count == 2, parts[0] == "join",
                  parts[1].range(of: "^[A-Za-z0-9_-]{32}$", options: .regularExpression) != nil
            else { return nil }
            token = parts[1]
        }
    }

    private struct InviteRequest: Encodable {
        let role: String
        let weeks: [Int]?
        let year: Int?
        let days: Int
    }

    func createInvite(role: String, weeks: [Int]?, year: Int?, days: Int = 14) async throws -> NewInvite {
        try await API.request(
            "POST", "/api/invites",
            json: InviteRequest(role: role, weeks: weeks, year: weeks == nil ? nil : year, days: days)
        )
    }

    func invites() async throws -> [Invite] {
        struct Response: Decodable { let invites: [Invite] }
        let response: Response = try await API.request("GET", "/api/invites")
        return response.invites
    }

    func revokeInvite(_ id: UUID) async throws {
        struct Response: Decodable { let revoked: Bool }
        let _: Response = try await API.request("DELETE", "/api/invites/\(id.uuidString.lowercased())")
    }

    func previewInvite(_ invite: PendingInvite) async throws -> InvitePreview {
        try await API.request("GET", "/api/invites/preview", query: [URLQueryItem(name: "token", value: invite.token)], signedIn: false)
    }

    func acceptInvite(_ invite: PendingInvite) async throws {
        struct Token: Encodable { let token: String }
        let response: FamilyResponse = try await API.request("POST", "/api/invites/accept", json: Token(token: invite.token))
        family = response.family
    }

    // MARK: Nonce (binds Apple's token to this sign-in, so a stolen token can't be replayed)

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// "any week", "week 30", "weeks 47–48 of 2026". Mirrors lib/weeks.ts.
func weeksLabel(_ weeks: [Int]?, year: Int?) -> String {
    guard let weeks, let first = weeks.first else { return "any week" }
    var runs: [String] = []
    var start = first, prev = first
    for w in weeks.dropFirst() + [Int.min] {
        if w == prev + 1 { prev = w; continue }
        runs.append(start == prev ? "\(start)" : "\(start)–\(prev)")
        start = w; prev = w
    }
    let noun = weeks.count > 1 ? "weeks" : "week"
    return "\(noun) \(runs.joined(separator: ", "))" + (year.map { " of \(String($0))" } ?? "")
}
