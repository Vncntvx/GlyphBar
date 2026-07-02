import Foundation

extension Command {
    var actionText: String? {
        guard case .userAction(_, let payload) = self else {
            return nil
        }
        return payload?.text
    }

    var actionInt: Int? {
        actionText.flatMap(Int.init)
    }

    func actionBool(default defaultValue: Bool) -> Bool {
        guard let text = actionText?.lowercased() else {
            return defaultValue
        }
        if ["true", "1", "yes"].contains(text) { return true }
        if ["false", "0", "no"].contains(text) { return false }
        return defaultValue
    }

    func actionPayloadData<T: Decodable>(_ type: T.Type) -> T? {
        guard case .userAction(_, let payload) = self,
              let data = payload?.data else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }
}
