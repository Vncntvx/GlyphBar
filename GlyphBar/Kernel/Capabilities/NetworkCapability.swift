import Foundation

/// Network capability. Modules declare `.network` in their manifest and the kernel
/// grants a `NetworkCapability` instance; the module must NOT touch
/// `URLSession.shared` directly.
@MainActor
final class NetworkCapability: Capability {
    static let declaredKey: CapabilityKey = .network

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: NetworkRequest) async throws -> (Data, HTTPURLResponse) {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        urlRequest.httpBody = request.body
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
