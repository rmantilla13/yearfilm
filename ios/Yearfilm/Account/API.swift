import Foundation

/// The yearfilm.com web API, called as the signed-in person.
enum API {
    static let base: URL = {
        let s = Bundle.main.object(forInfoDictionaryKey: "YFAPIBaseURL") as? String
        return URL(string: s ?? "https://www.yearfilm.com")!
    }()

    struct Failure: LocalizedError {
        let status: Int
        let message: String
        var errorDescription: String? { message }
    }

    private struct ErrorBody: Decodable { let error: String }

    /// `signedIn: false` is for the few public calls, like previewing an invite before signing in.
    static func request<Response: Decodable>(
        _ method: String, _ path: String, query: [URLQueryItem] = [], json: (any Encodable)? = nil, signedIn: Bool = true
    ) async throws -> Response {
        var url = base.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if signedIn {
            guard let token = await Account.shared.accessToken() else {
                throw Failure(status: 401, message: "Sign in first.")
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(json)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
            throw Failure(status: status, message: message ?? "Yearfilm couldn’t be reached (\(status)).")
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
