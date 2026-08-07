import Foundation

struct UsageQuota: Codable, Sendable {

    struct Window: Codable, Sendable {
        let usedPercentage: Double
        let resetsAt: Date
    }

    let fiveHour: Window?
    let sevenDay: Window?
    let readAt: Date

    var valid: UsageQuota? {
        let now = Date()
        let five = fiveHour.flatMap { $0.resetsAt > now ? $0 : nil }
        let seven = sevenDay.flatMap { $0.resetsAt > now ? $0 : nil }
        guard five != nil || seven != nil else { return nil }
        return UsageQuota(fiveHour: five, sevenDay: seven, readAt: readAt)
    }
}

extension UsageQuota {

    private static let storageKey = "usageQuota"

    static var stored: UsageQuota? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let quota = try? JSONDecoder().decode(UsageQuota.self, from: data) else { return nil }
        return quota.valid
    }

    static func store(_ quota: UsageQuota?) {
        guard let quota, let data = try? JSONEncoder().encode(quota) else {
            return UserDefaults.standard.removeObject(forKey: storageKey)
        }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
