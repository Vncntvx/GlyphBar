import Foundation

enum ExportError: LocalizedError {
    case notLoggedIn
    case authFailed
    case noData
    case timeout

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: "Not logged in to DeepSeek platform."
        case .authFailed: "Session expired — please re-login."
        case .noData: "No usage data found in export."
        case .timeout: "Export timed out. Try again."
        }
    }
}
