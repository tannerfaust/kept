import Foundation
import Security

struct SupabaseConfiguration {
    static let callbackURL = "kept://auth-callback"

    var url: URL?
    var anonKey: String

    var isConfigured: Bool {
        url != nil && !anonKey.isEmpty
    }

    static var current: SupabaseConfiguration {
        let info = Bundle.main.infoDictionary ?? [:]
        let rawURL = info["SUPABASE_URL"] as? String ?? ProcessInfo.processInfo.environment["SUPABASE_URL"]
        let anonKey = info["SUPABASE_ANON_KEY"] as? String ?? ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"] ?? ""
        return SupabaseConfiguration(url: rawURL.flatMap(URL.init(string:)), anonKey: anonKey)
    }
}

enum SupabaseError: LocalizedError {
    case authCallbackMissingSession
    case backend(String)
    case invalidResponse
    case missingConfiguration
    case unauthenticated

    var errorDescription: String? {
        switch self {
        case .authCallbackMissingSession:
            "The magic link opened, but it did not include a Supabase session."
        case .backend(let message):
            message
        case .invalidResponse:
            "Supabase returned a response that could not be decoded."
        case .missingConfiguration:
            "Set SUPABASE_URL and SUPABASE_ANON_KEY in app configuration before using live backend calls."
        case .unauthenticated:
            "Sign in before using the live backend."
        }
    }
}

struct SupabaseSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: UUID
    var email: String?

    enum CodingKeys: String, CodingKey {
        case accessToken
        case refreshToken
        case expiresAt
        case userID = "userId"
        case email
    }

    var isExpired: Bool {
        Date().addingTimeInterval(60) >= expiresAt
    }
}

protocol KeptBackendService {
    var currentSession: SupabaseSession? { get }

    func sendMagicLink(email: String) async throws
    func handleAuthCallback(_ url: URL) async throws -> UserProfile
    func restoreSession() async throws -> UserProfile?
    func fetchProfile(userID: UUID) async throws -> UserProfile
    func ensureProfile(for session: SupabaseSession) async throws -> UserProfile
    func findProfile(handle: String) async throws -> UserProfile?
    func fetchFriends(userID: UUID) async throws -> [KeptFriend]
    func sendFriendRequest(handle: String) async throws -> KeptFriend
    func acceptFriendRequest(_ friend: KeptFriend) async throws -> KeptFriend
    func fetchPacts(userID: UUID) async throws -> [Pact]
    func fetchCheckIns(userID: UUID) async throws -> [CheckIn]
    func fetchPactMessages(userID: UUID) async throws -> [PactMessage]
    func createPact(_ pact: Pact) async throws
    func submitCheckIn(_ checkIn: CheckIn) async throws
    func deleteCheckIn(pactID: UUID, userID: UUID, day: Date) async throws
    func postPactMessage(_ message: PactMessage) async throws
    func updateProfile(_ profile: UserProfile) async throws
    func uploadAvatarImage(_ data: Data, userID: UUID) async throws -> URL
    func signOut() async throws
}

final class SupabaseService: KeptBackendService, KeptBackendBreadcrumbCarrier {
    private static let sessionStorageKey = "kept.supabase.session.v2"
    private static let legacySessionStorageKey = "kept.supabase.session"

    private let configuration: SupabaseConfiguration
    private let session: URLSession
    private(set) var currentSession: SupabaseSession?
    var requestBreadcrumb: String?

    init(configuration: SupabaseConfiguration = .current, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        self.currentSession = Self.loadStoredSession()
    }

    func sendMagicLink(email: String) async throws {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanEmail.isEmpty else { return }

        let body = MagicLinkRequest(email: cleanEmail, createUser: true)
        let _: EmptyResponse = try await authRequest(
            path: "otp",
            queryItems: [URLQueryItem(name: "redirect_to", value: SupabaseConfiguration.callbackURL)],
            method: "POST",
            body: body,
            authorized: false
        )
    }

    func handleAuthCallback(_ url: URL) async throws -> UserProfile {
        let parameters = callbackParameters(from: url)
        guard let accessToken = parameters["access_token"],
              let refreshToken = parameters["refresh_token"] else {
            throw SupabaseError.authCallbackMissingSession
        }

        let expiresIn = TimeInterval(parameters["expires_in"].flatMap(Int.init) ?? 3600)
        let claims = try JWTClaims.decode(from: accessToken)
        let session = SupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn),
            userID: claims.sub,
            email: claims.email
        )
        storeSession(session)
        return try await ensureProfile(for: session)
    }

    func restoreSession() async throws -> UserProfile? {
        guard let session = currentSession else { return nil }
        if session.isExpired {
            try await refreshSession()
        }
        guard let restored = currentSession else { return nil }
        return try await ensureProfile(for: restored)
    }

    func fetchProfile(userID: UUID) async throws -> UserProfile {
        let rows: [ProfileRow] = try await restRequest(
            path: "profiles",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(userID.uuidString.lowercased())"),
                URLQueryItem(name: "select", value: "*")
            ],
            method: "GET",
            body: Optional<EmptyBody>.none
        )
        guard let row = rows.first else { throw SupabaseError.invalidResponse }
        return row.model
    }

    func ensureProfile(for session: SupabaseSession) async throws -> UserProfile {
        if let profile = try? await fetchProfile(userID: session.userID) {
            return profile
        }

        let fallbackName = session.email?.components(separatedBy: "@").first ?? "Kept"
        let shortID = String(session.userID.uuidString.prefix(8)).lowercased()
        let profile = UserProfile(
            id: session.userID,
            displayName: fallbackName.capitalized,
            handle: "@\(fallbackName.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" })_\(shortID)",
            bio: "",
            avatarSymbol: "bolt.fill",
            avatarURL: nil,
            accentColorHex: "#ff564d",
            integrityScore: 1,
            currentStreak: 0,
            bestStreak: 0,
            completionRate: 1
        )

        let _: [ProfileRow] = try await restRequest(
            path: "profiles",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            method: "POST",
            body: ProfileRow(profile)
        )
        return profile
    }

    func findProfile(handle: String) async throws -> UserProfile? {
        let rows: [ProfileRow] = try await rpcRequest(
            function: "find_profile_by_handle",
            method: "POST",
            body: HandleRequest(searchHandle: handle)
        )
        return rows.first?.model
    }

    func fetchFriends(userID: UUID) async throws -> [KeptFriend] {
        let rows: [FriendshipProfileRow] = try await rpcRequest(
            function: "list_friendships",
            method: "POST",
            body: Optional<EmptyBody>.none
        )

        return rows.map { row in
            let direction: KeptFriend.PendingDirection?
            if row.status == .pending {
                direction = row.requesterID == userID ? .outgoing : .incoming
            } else {
                direction = nil
            }
            return KeptFriend(id: row.friendshipID, profile: row.profile, status: row.status, pendingDirection: direction)
        }
    }

    func sendFriendRequest(handle: String) async throws -> KeptFriend {
        guard let userID = currentSession?.userID else { throw SupabaseError.unauthenticated }
        let row: FriendshipRow = try await rpcRequest(
            function: "send_friend_request",
            method: "POST",
            body: HandleRequest(searchHandle: handle)
        )
        let otherID = row.requesterID == userID ? row.addresseeID : row.requesterID
        let profile = try await fetchProfile(userID: otherID)
        return KeptFriend(id: row.id, profile: profile, status: row.status, pendingDirection: row.requesterID == userID ? .outgoing : .incoming)
    }

    func acceptFriendRequest(_ friend: KeptFriend) async throws -> KeptFriend {
        guard let userID = currentSession?.userID else { throw SupabaseError.unauthenticated }
        let row: FriendshipRow = try await rpcRequest(
            function: "accept_friend_request",
            method: "POST",
            body: FriendshipIDRequest(friendshipID: friend.id)
        )
        let otherID = row.requesterID == userID ? row.addresseeID : row.requesterID
        let profile = try await fetchProfile(userID: otherID)
        return KeptFriend(id: row.id, profile: profile, status: row.status, pendingDirection: nil)
    }

    func fetchPacts(userID: UUID) async throws -> [Pact] {
        let participantRows: [PactParticipantRow] = try await restRequest(
            path: "pact_participants",
            queryItems: [
                URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString.lowercased())"),
                URLQueryItem(name: "select", value: "*")
            ],
            method: "GET",
            body: Optional<EmptyBody>.none
        )
        let pactIDs = participantRows.map(\.pactID)
        guard !pactIDs.isEmpty else { return [] }

        let pactRows = try await fetchPactRows(ids: pactIDs)
        let allParticipantRows = try await fetchParticipantRows(pactIDs: pactIDs)
        let conditionRows = try await fetchConditionRows(pactIDs: pactIDs)
        let profiles = try await fetchProfiles(ids: Array(Set(allParticipantRows.map(\.userID))))

        return pactRows.map { row in
            let participants = allParticipantRows
                .filter { $0.pactID == row.id }
                .compactMap { participant -> PactParticipant? in
                    guard let profile = profiles[participant.userID] else { return nil }
                    return PactParticipant(id: participant.id, profile: profile, joinedAt: participant.joinedAt, isOwner: participant.isOwner)
                }
            let conditions = conditionRows
                .filter { $0.pactID == row.id }
                .map(\.model)
            return row.model(participants: participants, conditions: conditions)
        }
        .sorted { $0.startDate > $1.startDate }
    }

    func fetchCheckIns(userID: UUID) async throws -> [CheckIn] {
        let pacts = try await fetchPacts(userID: userID)
        let pactIDs = pacts.map(\.id)
        guard !pactIDs.isEmpty else { return [] }

        let rows: [CheckInRow] = try await restRequest(
            path: "check_ins",
            queryItems: [
                URLQueryItem(name: "pact_id", value: "in.(\(pactIDs.map { $0.uuidString.lowercased() }.joined(separator: ",")))"),
                URLQueryItem(name: "select", value: "*")
            ],
            method: "GET",
            body: Optional<EmptyBody>.none
        )
        guard !rows.isEmpty else { return [] }

        let values = try await fetchCheckInValueRows(checkInIDs: rows.map(\.id))
        return rows.map { row in
            row.model(values: values.filter { $0.checkInID == row.id }.map(\.model))
        }
    }

    func fetchPactMessages(userID: UUID) async throws -> [PactMessage] {
        let pacts = try await fetchPacts(userID: userID)
        guard !pacts.isEmpty else { return [] }
        let rows: [PactMessageRow] = try await restRequest(
            path: "pact_messages",
            queryItems: [
                URLQueryItem(name: "pact_id", value: "in.(\(pacts.map { $0.id.uuidString.lowercased() }.joined(separator: ",")))"),
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "created_at.asc")
            ],
            method: "GET",
            body: Optional<EmptyBody>.none
        )
        return rows.map(\.model)
    }

    func createPact(_ pact: Pact) async throws {
        guard let userID = currentSession?.userID else { throw SupabaseError.unauthenticated }

        let _: [PactRecord] = try await restRequest(path: "pacts", queryItems: [], method: "POST", body: PactRecord(pact: pact, createdBy: userID))

        let participants = pact.participants.map { PactParticipantRow(participant: $0, pactID: pact.id) }
        let _: [PactParticipantRow] = try await restRequest(path: "pact_participants", queryItems: [], method: "POST", body: participants)

        let conditions = pact.conditions.map { PactConditionRow(condition: $0, pactID: pact.id) }
        let _: [PactConditionRow] = try await restRequest(path: "pact_conditions", queryItems: [], method: "POST", body: conditions)
    }

    func submitCheckIn(_ checkIn: CheckIn) async throws {
        let checkInRow = CheckInRow(checkIn)
        let _: [CheckInRow] = try await restRequest(
            path: "check_ins",
            queryItems: [URLQueryItem(name: "on_conflict", value: "pact_id,user_id,day")],
            method: "POST",
            body: checkInRow
        )

        let values = checkIn.values.map { CheckInValueRow(value: $0, checkInID: checkIn.id) }
        let _: [CheckInValueRow] = try await restRequest(
            path: "check_in_values",
            queryItems: [URLQueryItem(name: "on_conflict", value: "check_in_id,condition_id")],
            method: "POST",
            body: values
        )
    }

    func deleteCheckIn(pactID: UUID, userID: UUID, day: Date) async throws {
        let _: EmptyResponse = try await restRequest(
            path: "check_ins",
            queryItems: [
                URLQueryItem(name: "pact_id", value: "eq.\(pactID.uuidString.lowercased())"),
                URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString.lowercased())"),
                URLQueryItem(name: "day", value: "eq.\(DateFormatter.keptDateOnly.string(from: day))")
            ],
            method: "DELETE",
            body: Optional<EmptyBody>.none
        )
    }

    func postPactMessage(_ message: PactMessage) async throws {
        let _: [PactMessageRow] = try await restRequest(path: "pact_messages", queryItems: [], method: "POST", body: PactMessageRow(message))
    }

    func updateProfile(_ profile: UserProfile) async throws {
        let _: EmptyResponse = try await restRequest(
            path: "profiles",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(profile.id.uuidString.lowercased())")],
            method: "PATCH",
            body: ProfileRow(profile)
        )
    }

    func uploadAvatarImage(_ data: Data, userID: UUID) async throws -> URL {
        guard let baseURL = configuration.url, configuration.isConfigured else {
            throw SupabaseError.missingConfiguration
        }
        guard let token = try await validAccessToken() else { throw SupabaseError.unauthenticated }

        let objectPath = "\(userID.uuidString.lowercased())/avatar.jpg"
        let endpoint = baseURL.appending(path: "storage/v1/object/profile-avatars/\(objectPath)")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw SupabaseError.invalidResponse
        }

        return baseURL.appending(path: "storage/v1/object/public/profile-avatars/\(objectPath)")
    }

    func signOut() async throws {
        if currentSession != nil {
            let _: EmptyResponse? = try? await authRequest(
                path: "logout",
                queryItems: [],
                method: "POST",
                body: Optional<EmptyBody>.none,
                authorized: true
            )
        }
        clearStoredSession()
    }

    private func fetchPactRows(ids: [UUID]) async throws -> [PactRecord] {
        try await restRequest(
            path: "pacts",
            queryItems: [
                URLQueryItem(name: "id", value: "in.(\(ids.map { $0.uuidString.lowercased() }.joined(separator: ",")))"),
                URLQueryItem(name: "select", value: "*")
            ],
            method: "GET",
            body: Optional<EmptyBody>.none
        )
    }

    private func fetchParticipantRows(pactIDs: [UUID]) async throws -> [PactParticipantRow] {
        try await restRequest(
            path: "pact_participants",
            queryItems: [
                URLQueryItem(name: "pact_id", value: "in.(\(pactIDs.map { $0.uuidString.lowercased() }.joined(separator: ",")))"),
                URLQueryItem(name: "select", value: "*")
            ],
            method: "GET",
            body: Optional<EmptyBody>.none
        )
    }

    private func fetchConditionRows(pactIDs: [UUID]) async throws -> [PactConditionRow] {
        try await restRequest(
            path: "pact_conditions",
            queryItems: [
                URLQueryItem(name: "pact_id", value: "in.(\(pactIDs.map { $0.uuidString.lowercased() }.joined(separator: ",")))"),
                URLQueryItem(name: "select", value: "*")
            ],
            method: "GET",
            body: Optional<EmptyBody>.none
        )
    }

    private func fetchCheckInValueRows(checkInIDs: [UUID]) async throws -> [CheckInValueRow] {
        try await restRequest(
            path: "check_in_values",
            queryItems: [
                URLQueryItem(name: "check_in_id", value: "in.(\(checkInIDs.map { $0.uuidString.lowercased() }.joined(separator: ",")))"),
                URLQueryItem(name: "select", value: "*")
            ],
            method: "GET",
            body: Optional<EmptyBody>.none
        )
    }

    private func fetchProfiles(ids: [UUID]) async throws -> [UUID: UserProfile] {
        let ids = Array(Set(ids))
        guard !ids.isEmpty else { return [:] }

        let rows: [ProfileRow] = try await restRequest(
            path: "profiles",
            queryItems: [
                URLQueryItem(name: "id", value: "in.(\(ids.map { $0.uuidString.lowercased() }.joined(separator: ",")))"),
                URLQueryItem(name: "select", value: "*")
            ],
            method: "GET",
            body: Optional<EmptyBody>.none
        )
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.model) })
    }

    private func refreshSession() async throws {
        guard let refreshToken = currentSession?.refreshToken else { throw SupabaseError.unauthenticated }
        let response: TokenResponse = try await authRequest(
            path: "token",
            queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            method: "POST",
            body: RefreshTokenRequest(refreshToken: refreshToken),
            authorized: false
        )
        let claims = try JWTClaims.decode(from: response.accessToken)
        let session = SupabaseSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            userID: claims.sub,
            email: response.user.email ?? claims.email
        )
        storeSession(session)
    }

    private func validAccessToken() async throws -> String? {
        if currentSession?.isExpired == true {
            try await refreshSession()
        }
        return currentSession?.accessToken
    }

    private func restRequest<Body: Encodable, Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem],
        method: String,
        body: Body?
    ) async throws -> Response {
        guard let token = try await validAccessToken() else { throw SupabaseError.unauthenticated }
        return try await request(basePath: "rest/v1/\(path)", queryItems: queryItems, method: method, body: body, bearerToken: token)
    }

    private func authRequest<Body: Encodable, Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem],
        method: String,
        body: Body?,
        authorized: Bool
    ) async throws -> Response {
        let bearerToken = authorized ? try await validAccessToken() : nil
        return try await request(basePath: "auth/v1/\(path)", queryItems: queryItems, method: method, body: body, bearerToken: bearerToken)
    }

    private func rpcRequest<Body: Encodable, Response: Decodable>(
        function: String,
        method: String,
        body: Body?
    ) async throws -> Response {
        guard let token = try await validAccessToken() else { throw SupabaseError.unauthenticated }
        return try await request(basePath: "rest/v1/rpc/\(function)", queryItems: [], method: method, body: body, bearerToken: token)
    }

    private func request<Body: Encodable, Response: Decodable>(
        basePath: String,
        queryItems: [URLQueryItem],
        method: String,
        body: Body?,
        bearerToken: String?
    ) async throws -> Response {
        guard let baseURL = configuration.url, configuration.isConfigured else {
            throw SupabaseError.missingConfiguration
        }

        var components = URLComponents(url: baseURL.appending(path: basePath), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let endpoint = components?.url else { throw SupabaseError.invalidResponse }

        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONEncoder.kept.encode(body)
        }
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(bearerToken ?? configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if method == "POST" {
            request.setValue("return=representation,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        } else if method == "PATCH" {
            request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        }
        applyBreadcrumbHeader(to: &request)

        let (data, response) = try await session.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode
        KeptBreadcrumbLog.backend(
            method: method,
            path: basePath,
            breadcrumb: requestBreadcrumb,
            statusCode: statusCode
        )
        guard let httpResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            if let message = SupabaseErrorMessage.message(from: data) {
                throw SupabaseError.backend(message)
            }
            throw SupabaseError.backend("Supabase request failed with status \(statusCode ?? 0).")
        }

        if Response.self == EmptyResponse.self || data.isEmpty {
            return EmptyResponse() as! Response
        }
        do {
            return try JSONDecoder.kept.decode(Response.self, from: data)
        } catch {
            throw SupabaseError.backend("Could not read Supabase response: \(Self.decodingMessage(for: error))")
        }
    }

    private static func decodingMessage(for error: Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let key, let context):
            return "missing '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case DecodingError.valueNotFound(_, let context):
            return "missing value at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case DecodingError.typeMismatch(_, let context):
            return "wrong type at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case DecodingError.dataCorrupted(let context):
            return context.debugDescription
        default:
            return error.localizedDescription
        }
    }

    private func callbackParameters(from url: URL) -> [String: String] {
        var pairs: [String: String] = [:]
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems?.forEach { pairs[$0.name] = $0.value }
        }
        if let fragment = url.fragment,
           let fragmentComponents = URLComponents(string: "kept://auth-callback?\(fragment)") {
            fragmentComponents.queryItems?.forEach { pairs[$0.name] = $0.value }
        }
        return pairs
    }

    private func storeSession(_ session: SupabaseSession) {
        currentSession = session
        if let data = try? JSONEncoder.kept.encode(session) {
            UserDefaults.standard.set(data, forKey: Self.sessionStorageKey)
            UserDefaults.standard.set(data, forKey: Self.legacySessionStorageKey)
            UserDefaults.standard.synchronize()

            if !KeychainStorage.set(data, for: Self.sessionStorageKey) {
                KeptBreadcrumbLog.backend(method: "KEYCHAIN", path: "session.store", breadcrumb: "write failed", statusCode: nil)
            }
        }
    }

    private func clearStoredSession() {
        currentSession = nil
        UserDefaults.standard.removeObject(forKey: Self.sessionStorageKey)
        UserDefaults.standard.removeObject(forKey: Self.legacySessionStorageKey)
        UserDefaults.standard.synchronize()
        KeychainStorage.delete(Self.sessionStorageKey)
        KeychainStorage.delete(Self.legacySessionStorageKey)
    }

    private static func loadStoredSession() -> SupabaseSession? {
        let candidates = [
            KeychainStorage.data(for: sessionStorageKey),
            UserDefaults.standard.data(forKey: sessionStorageKey),
            KeychainStorage.data(for: legacySessionStorageKey),
            UserDefaults.standard.data(forKey: legacySessionStorageKey)
        ]

        for data in candidates.compactMap({ $0 }) {
            if let session = try? JSONDecoder.kept.decode(SupabaseSession.self, from: data) {
                return session
            }
        }
        return nil
    }
}

private enum KeychainStorage {
    private static var services: [String] {
        var values = [Bundle.main.bundleIdentifier ?? "TannerFaust.Kept"]
        values.append("TannerFaust.Kept")
        return Array(Set(values))
    }

    static func data(for account: String) -> Data? {
        for service in services {
            var query = baseQuery(account: account, service: service)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecSuccess, let data = item as? Data {
                return data
            }
        }
        return nil
    }

    @discardableResult
    static func set(_ data: Data, for account: String) -> Bool {
        var didWrite = false
        for service in services {
            let query = baseQuery(account: account, service: service)
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if updateStatus == errSecSuccess {
                didWrite = true
                continue
            }

            var addQuery = query
            attributes.forEach { addQuery[$0.key] = $0.value }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus == errSecSuccess || addStatus == errSecDuplicateItem {
                didWrite = true
            }
        }
        return didWrite
    }

    static func delete(_ account: String) {
        services.forEach { service in
            SecItemDelete(baseQuery(account: account, service: service) as CFDictionary)
        }
    }

    private static func baseQuery(account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private struct MagicLinkRequest: Encodable {
    let email: String
    let createUser: Bool
}

private struct RefreshTokenRequest: Encodable {
    let refreshToken: String
}

private struct HandleRequest: Encodable {
    let searchHandle: String
}

private struct FriendshipIDRequest: Encodable {
    let friendshipID: UUID

    enum CodingKeys: String, CodingKey {
        case friendshipID = "friendshipId"
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: AuthUser
}

private struct AuthUser: Decodable {
    let id: UUID
    let email: String?
}

private struct JWTClaims: Decodable {
    let sub: UUID
    let email: String?

    static func decode(from jwt: String) throws -> JWTClaims {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { throw SupabaseError.invalidResponse }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload.append("=")
        }
        guard let data = Data(base64Encoded: payload) else { throw SupabaseError.invalidResponse }
        return try JSONDecoder.kept.decode(JWTClaims.self, from: data)
    }
}

private struct ProfileRow: Codable {
    var id: UUID
    var displayName: String
    var handle: String
    var bio: String
    var avatarSymbol: String
    var avatarUrl: URL?
    var accentColor: String
    var integrityScore: Double
    var currentStreak: Int
    var bestStreak: Int
    var completionRate: Double

    init(_ profile: UserProfile) {
        id = profile.id
        displayName = profile.displayName
        handle = profile.handle
        bio = profile.bio
        avatarSymbol = profile.avatarSymbol
        avatarUrl = profile.avatarURL
        accentColor = profile.accentColorHex
        integrityScore = profile.integrityScore
        currentStreak = profile.currentStreak
        bestStreak = profile.bestStreak
        completionRate = profile.completionRate
    }

    var model: UserProfile {
        UserProfile(
            id: id,
            displayName: displayName,
            handle: handle,
            bio: bio,
            avatarSymbol: avatarSymbol,
            avatarURL: avatarUrl,
            accentColorHex: accentColor,
            integrityScore: integrityScore,
            currentStreak: currentStreak,
            bestStreak: bestStreak,
            completionRate: completionRate
        )
    }
}

private struct FriendshipRow: Codable {
    var id: UUID
    var requesterID: UUID
    var addresseeID: UUID
    var status: FriendshipStatus

    enum CodingKeys: String, CodingKey {
        case id
        case requesterID = "requesterId"
        case addresseeID = "addresseeId"
        case status
    }
}

private struct FriendshipProfileRow: Codable {
    var friendshipID: UUID
    var requesterID: UUID
    var addresseeID: UUID
    var status: FriendshipStatus
    var profileID: UUID
    var displayName: String
    var handle: String
    var bio: String
    var avatarSymbol: String
    var avatarUrl: URL?
    var accentColor: String
    var integrityScore: Double
    var currentStreak: Int
    var bestStreak: Int
    var completionRate: Double

    var profile: UserProfile {
        UserProfile(
            id: profileID,
            displayName: displayName,
            handle: handle,
            bio: bio,
            avatarSymbol: avatarSymbol,
            avatarURL: avatarUrl,
            accentColorHex: accentColor,
            integrityScore: integrityScore,
            currentStreak: currentStreak,
            bestStreak: bestStreak,
            completionRate: completionRate
        )
    }

    enum CodingKeys: String, CodingKey {
        case friendshipID = "friendshipId"
        case requesterID = "requesterId"
        case addresseeID = "addresseeId"
        case status
        case profileID = "profileId"
        case displayName
        case handle
        case bio
        case avatarSymbol
        case avatarUrl
        case accentColor
        case integrityScore
        case currentStreak
        case bestStreak
        case completionRate
    }
}

private struct PactRecord: Codable {
    var id: UUID
    var createdBy: UUID
    var title: String
    var description: String
    var startDate: Date
    var finishDate: Date
    var iconSymbol: String
    var accentColor: String
    var status: PactStatus
    var reminderHour: Int
    var reminderMinute: Int

    init(pact: Pact, createdBy: UUID) {
        id = pact.id
        self.createdBy = createdBy
        title = pact.title
        description = pact.description
        startDate = pact.startDate
        finishDate = pact.finishDate
        iconSymbol = pact.iconSymbol
        accentColor = pact.accentColorHex
        status = pact.status
        reminderHour = pact.reminderHour
        reminderMinute = pact.reminderMinute
    }

    func model(participants: [PactParticipant], conditions: [PactCondition]) -> Pact {
        Pact(
            id: id,
            title: title,
            description: description,
            startDate: startDate,
            finishDate: finishDate,
            iconSymbol: iconSymbol,
            accentColorHex: accentColor,
            status: status,
            participants: participants,
            conditions: conditions,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute
        )
    }
}

private struct PactParticipantRow: Codable {
    var id: UUID
    var pactID: UUID
    var userID: UUID
    var isOwner: Bool
    var joinedAt: Date

    init(participant: PactParticipant, pactID: UUID) {
        id = participant.id
        self.pactID = pactID
        userID = participant.profile.id
        isOwner = participant.isOwner
        joinedAt = participant.joinedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case pactID = "pactId"
        case userID = "userId"
        case isOwner
        case joinedAt
    }
}

private struct PactConditionRow: Codable {
    var id: UUID
    var pactID: UUID
    var title: String
    var conditionType: ConditionType
    var inputType: PactInputType
    var comparison: ComparisonOperator
    var targetValue: Int
    var isRequired: Bool

    init(condition: PactCondition, pactID: UUID) {
        id = condition.id
        self.pactID = pactID
        title = condition.title
        conditionType = condition.type
        inputType = condition.inputType
        comparison = condition.comparison
        targetValue = condition.targetValue
        isRequired = condition.isRequired
    }

    var model: PactCondition {
        PactCondition(
            id: id,
            title: title,
            type: conditionType,
            inputType: inputType,
            comparison: comparison,
            targetValue: targetValue,
            isRequired: isRequired
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case pactID = "pactId"
        case title
        case conditionType
        case inputType
        case comparison
        case targetValue
        case isRequired
    }
}

private struct CheckInRow: Codable {
    var id: UUID
    var pactID: UUID
    var userID: UUID
    var day: Date
    var note: String
    var didReportViolation: Bool

    init(_ checkIn: CheckIn) {
        id = checkIn.id
        pactID = checkIn.pactID
        userID = checkIn.userID
        day = checkIn.day
        note = checkIn.note
        didReportViolation = checkIn.didReportViolation
    }

    func model(values: [CheckInValue]) -> CheckIn {
        CheckIn(id: id, pactID: pactID, userID: userID, day: day, note: note, didReportViolation: didReportViolation, values: values)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case pactID = "pactId"
        case userID = "userId"
        case day
        case note
        case didReportViolation
    }
}

private struct CheckInValueRow: Codable {
    var id: UUID
    var checkInID: UUID
    var conditionID: UUID
    var integerValue: Int

    init(value: CheckInValue, checkInID: UUID) {
        id = value.id
        self.checkInID = checkInID
        conditionID = value.conditionID
        integerValue = value.integerValue
    }

    var model: CheckInValue {
        CheckInValue(id: id, conditionID: conditionID, integerValue: integerValue)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case checkInID = "checkInId"
        case conditionID = "conditionId"
        case integerValue
    }
}

private struct PactMessageRow: Codable {
    var id: UUID
    var pactID: UUID
    var userID: UUID
    var senderName: String
    var senderAccentColor: String
    var body: String
    var createdAt: Date

    init(_ message: PactMessage) {
        id = message.id
        pactID = message.pactID
        userID = message.senderID
        senderName = message.senderName
        senderAccentColor = message.senderAccentColorHex
        body = message.text
        createdAt = message.createdAt
    }

    var model: PactMessage {
        PactMessage(
            id: id,
            pactID: pactID,
            senderID: userID,
            senderName: senderName,
            senderAccentColorHex: senderAccentColor,
            text: body,
            createdAt: createdAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case pactID = "pactId"
        case userID = "userId"
        case senderName
        case senderAccentColor
        case body
        case createdAt
    }
}

private struct EmptyBody: Encodable {}
private struct EmptyResponse: Decodable {}

private struct SupabaseErrorMessage: Decodable {
    let message: String?
    let msg: String?
    let hint: String?

    static func message(from data: Data) -> String? {
        guard !data.isEmpty,
              let decoded = try? JSONDecoder().decode(SupabaseErrorMessage.self, from: data) else {
            return nil
        }
        return decoded.message ?? decoded.msg ?? decoded.hint
    }
}

extension JSONEncoder {
    static var kept: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601DateFormatter.keptDateTime.string(from: date))
        }
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}

extension JSONDecoder {
    static var kept: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = ISO8601DateFormatter.keptDateTime.date(from: string) {
                return date
            }
            if let date = ISO8601DateFormatter.keptDateTimeWithoutFractions.date(from: string) {
                return date
            }
            if let date = DateFormatter.keptDateOnly.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date string: \(string)")
        }
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

private extension ISO8601DateFormatter {
    static let keptDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let keptDateTimeWithoutFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private extension DateFormatter {
    static let keptDateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
