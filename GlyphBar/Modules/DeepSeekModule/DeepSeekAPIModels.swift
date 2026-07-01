import Foundation

struct BalanceInfo: Codable {
    let currency: String
    let totalBalance: String
    let grantedBalance: String
    let toppedUpBalance: String

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }
}

struct BalanceResponse: Codable {
    let isAvailable: Bool
    let balanceInfos: [BalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

enum DeepSeekError: LocalizedError {
    case missingKey
    case invalidKey
    case forbidden
    case rateLimited
    case networkError(String)
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "API key not configured"
        case .invalidKey:
            return "Invalid API key (401)"
        case .forbidden:
            return "Access denied (403)"
        case .rateLimited:
            return "Rate limited (429)"
        case .networkError(let message):
            return "Network: \(message)"
        case .apiError(let code, _):
            return "API error (\(code))"
        }
    }
}
