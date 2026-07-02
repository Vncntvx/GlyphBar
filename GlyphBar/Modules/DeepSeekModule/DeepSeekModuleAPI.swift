import Foundation

extension DeepSeekModule {
    static func validateApiKey(_ key: String, network: NetworkCapability) async throws {
        let request = NetworkRequest(
            url: URL(string: "\(DeepSeekAPI.baseURL)/user/balance")!,
            headers: [
                "Authorization": "Bearer \(key)",
                "Accept": "application/json"
            ]
        )
        let (_, http) = try await network.send(request)
        if http.statusCode == 401 { throw DeepSeekError.invalidKey }
        if http.statusCode == 403 { throw DeepSeekError.forbidden }
        if http.statusCode == 429 { throw DeepSeekError.rateLimited }
        if http.statusCode != 200 { throw DeepSeekError.apiError(http.statusCode, "") }
    }

    func fetchBalance(apiKey: String) async throws -> BalanceResponse {
        guard let network else {
            throw DeepSeekError.networkError("Network capability not available")
        }
        let request = NetworkRequest(
            url: URL(string: "\(DeepSeekAPI.baseURL)/user/balance")!,
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Accept": "application/json"
            ]
        )
        let (data, http) = try await network.send(request)
        if http.statusCode == 401 { throw DeepSeekError.invalidKey }
        if http.statusCode != 200 { throw DeepSeekError.apiError(http.statusCode, "") }
        return try JSONDecoder().decode(BalanceResponse.self, from: data)
    }
}

private enum DeepSeekAPI {
    static let baseURL = "https://api.deepseek.com"
}
