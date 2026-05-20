import Foundation

struct SupabaseConfiguration {
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
    case missingConfiguration
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "Set SUPABASE_URL and SUPABASE_ANON_KEY in app configuration before using live backend calls."
        case .invalidResponse:
            "Supabase returned a response that could not be decoded."
        }
    }
}

protocol DefyBackendService {
    func fetchProfile(userID: UUID) async throws -> UserProfile
    func fetchPacts(userID: UUID) async throws -> [Pact]
    func submitCheckIn(_ checkIn: CheckIn) async throws
    func updateProfile(_ profile: UserProfile) async throws
    func uploadAvatarImage(_ data: Data, userID: UUID) async throws -> URL
    func signOut() async throws
}

struct SupabaseService: DefyBackendService {
    private let configuration: SupabaseConfiguration
    private let session: URLSession

    init(configuration: SupabaseConfiguration = .current, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func fetchProfile(userID: UUID) async throws -> UserProfile {
        try await request(path: "profiles?id=eq.\(userID.uuidString)&select=*", method: "GET", body: Optional<Data>.none)
    }

    func fetchPacts(userID: UUID) async throws -> [Pact] {
        try await request(path: "pacts?select=*", method: "GET", body: Optional<Data>.none)
    }

    func submitCheckIn(_ checkIn: CheckIn) async throws {
        let body = try JSONEncoder.defy.encode(checkIn)
        let _: EmptyResponse = try await request(path: "check_ins", method: "POST", body: body)
    }

    func updateProfile(_ profile: UserProfile) async throws {
        let body = try JSONEncoder.defy.encode(profile)
        let _: EmptyResponse = try await request(path: "profiles?id=eq.\(profile.id.uuidString)", method: "PATCH", body: body)
    }

    func uploadAvatarImage(_ data: Data, userID: UUID) async throws -> URL {
        guard let baseURL = configuration.url, configuration.isConfigured else {
            throw SupabaseError.missingConfiguration
        }

        let objectPath = "\(userID.uuidString.lowercased())/avatar.jpg"
        let endpoint = baseURL.appending(path: "storage/v1/object/profile-avatars/\(objectPath)")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "upsert")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw SupabaseError.invalidResponse
        }

        return baseURL.appending(path: "storage/v1/object/public/profile-avatars/\(objectPath)")
    }

    func signOut() async throws {}

    private func request<Response: Decodable>(path: String, method: String, body: Data?) async throws -> Response {
        guard let baseURL = configuration.url, configuration.isConfigured else {
            throw SupabaseError.missingConfiguration
        }

        let endpoint = baseURL.appending(path: "rest/v1/\(path)")
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw SupabaseError.invalidResponse
        }

        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        return try JSONDecoder.defy.decode(Response.self, from: data)
    }
}

private struct EmptyResponse: Decodable {}

extension JSONEncoder {
    static var defy: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}

extension JSONDecoder {
    static var defy: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
