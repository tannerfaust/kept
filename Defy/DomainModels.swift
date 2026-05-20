import Foundation
import SwiftUI

enum PactCore: String, Codable, CaseIterable, Identifiable {
    case reactive
    case proactive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reactive: "Reactive"
        case .proactive: "Proactive"
        }
    }

    var symbol: String {
        switch self {
        case .reactive: "checkmark.seal.fill"
        case .proactive: "exclamationmark.triangle.fill"
        }
    }
}

enum PactInputType: String, Codable, CaseIterable, Identifiable {
    case boolean
    case integer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .boolean: "Toggle"
        case .integer: "Number"
        }
    }
}

enum PactStatus: String, Codable, CaseIterable, Identifiable {
    case draft
    case active
    case completed
    case failed
    case cancelled

    var id: String { rawValue }
}

enum FriendshipStatus: String, Codable {
    case pending
    case accepted
    case blocked
}

enum ComparisonOperator: String, Codable, CaseIterable, Identifiable {
    case equals
    case atLeast

    var id: String { rawValue }
}

struct UserProfile: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var displayName: String
    var handle: String
    var bio: String
    var avatarSymbol: String
    var avatarURL: URL?
    var accentColorHex: String
    var integrityScore: Double
    var currentStreak: Int
    var bestStreak: Int
    var completionRate: Double
}

struct DefyFriend: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var profile: UserProfile
    var status: FriendshipStatus
    var pendingDirection: PendingDirection?

    enum PendingDirection: String, Codable {
        case incoming
        case outgoing
    }
}

struct PactParticipant: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var profile: UserProfile
    var joinedAt: Date
    var isOwner: Bool
}

struct PactCondition: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var inputType: PactInputType
    var comparison: ComparisonOperator
    var targetValue: Int
    var isRequired: Bool

    func passes(value: Int?) -> Bool {
        guard let value else { return false }
        switch comparison {
        case .equals:
            return value == targetValue
        case .atLeast:
            return value >= targetValue
        }
    }
}

struct Pact: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var description: String
    var startDate: Date
    var finishDate: Date
    var core: PactCore
    var status: PactStatus
    var participants: [PactParticipant]
    var conditions: [PactCondition]
    var reminderHour: Int
    var reminderMinute: Int

    var isActiveToday: Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return today >= calendar.startOfDay(for: startDate)
            && today <= calendar.startOfDay(for: finishDate)
            && status == .active
    }

    var dateRangeText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: finishDate))"
    }
}

struct CheckInValue: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var conditionID: UUID
    var integerValue: Int
}

struct CheckIn: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var pactID: UUID
    var userID: UUID
    var day: Date
    var note: String
    var didReportViolation: Bool
    var values: [CheckInValue]
}

struct DefyNotification: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var message: String
    var createdAt: Date
    var pactID: UUID?
    var isRead: Bool
}

struct IntegritySnapshot: Equatable {
    var score: Double
    var completedUnits: Int
    var expectedUnits: Int
    var activePacts: Int
    var missedDays: Int

    static let empty = IntegritySnapshot(score: 1, completedUnits: 0, expectedUnits: 0, activePacts: 0, missedDays: 0)
}

struct ProfileSnapshot: Equatable {
    var integrityScore: Double
    var activePactCount: Int
    var completedUnits: Int
    var expectedUnits: Int
    var missedDays: Int
    var currentStreak: Int
    var bestStreak: Int
    var completionRate: Double
    var recentActivity: [ProfileActivityItem]
}

struct ProfileActivityItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var detail: String
    var date: Date
    var symbol: String
    var isPositive: Bool
}

enum ProfileHandleValidator {
    static func normalized(_ rawHandle: String) -> String? {
        let trimmed = rawHandle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }

        let handle = trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
        let allowed = CharacterSet(charactersIn: "@abcdefghijklmnopqrstuvwxyz0123456789_")
        guard handle.unicodeScalars.allSatisfy({ allowed.contains($0) }), handle.count > 1 else { return nil }
        return handle
    }
}

enum PactEvaluator {
    static func dayPassed(pact: Pact, checkIn: CheckIn?, on day: Date = Date()) -> Bool {
        switch pact.core {
        case .reactive:
            guard let checkIn else { return false }
            return requiredConditionsPass(pact: pact, checkIn: checkIn)
        case .proactive:
            guard let checkIn else { return true }
            return !checkIn.didReportViolation
        }
    }

    static func integrityScore(for pacts: [Pact], checkIns: [CheckIn], userID: UUID, calendar: Calendar = .current) -> IntegritySnapshot {
        var expected = 0
        var completed = 0
        let today = calendar.startOfDay(for: Date())

        for pact in pacts where pact.participants.contains(where: { $0.profile.id == userID }) {
            let start = calendar.startOfDay(for: pact.startDate)
            let finish = min(calendar.startOfDay(for: pact.finishDate), today)
            guard start <= finish else { continue }

            let dayCount = calendar.dateComponents([.day], from: start, to: finish).day ?? 0
            for offset in 0...dayCount {
                guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
                expected += 1
                let checkIn = checkIns.first {
                    $0.pactID == pact.id
                        && $0.userID == userID
                        && calendar.isDate($0.day, inSameDayAs: day)
                }
                if dayPassed(pact: pact, checkIn: checkIn, on: day) {
                    completed += 1
                }
            }
        }

        guard expected > 0 else {
            return IntegritySnapshot(score: 1, completedUnits: 0, expectedUnits: 0, activePacts: pacts.filter(\.isActiveToday).count, missedDays: 0)
        }

        return IntegritySnapshot(
            score: Double(completed) / Double(expected),
            completedUnits: completed,
            expectedUnits: expected,
            activePacts: pacts.filter(\.isActiveToday).count,
            missedDays: expected - completed
        )
    }

    static func profileSnapshot(for pacts: [Pact], checkIns: [CheckIn], userID: UUID, calendar: Calendar = .current) -> ProfileSnapshot {
        let integrity = integrityScore(for: pacts, checkIns: checkIns, userID: userID, calendar: calendar)
        let streaks = streaksForProfile(pacts: pacts, checkIns: checkIns, userID: userID, calendar: calendar)
        let activity = recentActivity(pacts: pacts, checkIns: checkIns, userID: userID, calendar: calendar)

        return ProfileSnapshot(
            integrityScore: integrity.score,
            activePactCount: integrity.activePacts,
            completedUnits: integrity.completedUnits,
            expectedUnits: integrity.expectedUnits,
            missedDays: integrity.missedDays,
            currentStreak: streaks.current,
            bestStreak: streaks.best,
            completionRate: integrity.expectedUnits == 0 ? 1 : integrity.score,
            recentActivity: activity
        )
    }

    private static func requiredConditionsPass(pact: Pact, checkIn: CheckIn) -> Bool {
        let required = pact.conditions.filter(\.isRequired)
        guard !required.isEmpty else { return true }
        return required.allSatisfy { condition in
            let submitted = checkIn.values.first { $0.conditionID == condition.id }?.integerValue
            return condition.passes(value: submitted)
        }
    }

    private static func streaksForProfile(pacts: [Pact], checkIns: [CheckIn], userID: UUID, calendar: Calendar) -> (current: Int, best: Int) {
        let today = calendar.startOfDay(for: Date())
        let days = profileDayResults(pacts: pacts, checkIns: checkIns, userID: userID, calendar: calendar)
            .filter { $0.day <= today && $0.expected > 0 }
            .sorted { $0.day < $1.day }

        var best = 0
        var run = 0
        for day in days {
            if day.completed == day.expected {
                run += 1
                best = max(best, run)
            } else {
                run = 0
            }
        }

        var current = 0
        for day in days.reversed() {
            guard day.completed == day.expected else { break }
            current += 1
        }

        return (current, best)
    }

    private static func profileDayResults(
        pacts: [Pact],
        checkIns: [CheckIn],
        userID: UUID,
        calendar: Calendar
    ) -> [(day: Date, expected: Int, completed: Int)] {
        let today = calendar.startOfDay(for: Date())
        var results: [Date: (expected: Int, completed: Int)] = [:]

        for pact in pacts where pact.participants.contains(where: { $0.profile.id == userID }) {
            let start = calendar.startOfDay(for: pact.startDate)
            let finish = min(calendar.startOfDay(for: pact.finishDate), today)
            guard start <= finish else { continue }

            let dayCount = calendar.dateComponents([.day], from: start, to: finish).day ?? 0
            for offset in 0...dayCount {
                guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
                let checkIn = checkIns.first {
                    $0.pactID == pact.id
                        && $0.userID == userID
                        && calendar.isDate($0.day, inSameDayAs: day)
                }
                let passed = dayPassed(pact: pact, checkIn: checkIn, on: day)
                let current = results[day] ?? (expected: 0, completed: 0)
                results[day] = (current.expected + 1, current.completed + (passed ? 1 : 0))
            }
        }

        return results.map { (day: $0.key, expected: $0.value.expected, completed: $0.value.completed) }
    }

    private static func recentActivity(pacts: [Pact], checkIns: [CheckIn], userID: UUID, calendar: Calendar) -> [ProfileActivityItem] {
        checkIns
            .filter { $0.userID == userID }
            .sorted { $0.day > $1.day }
            .prefix(5)
            .map { checkIn in
                let pactTitle = pacts.first { $0.id == checkIn.pactID }?.title ?? "Pact"
                return ProfileActivityItem(
                    id: checkIn.id,
                    title: checkIn.didReportViolation ? "Violation reported" : "Check-in locked",
                    detail: pactTitle,
                    date: checkIn.day,
                    symbol: checkIn.didReportViolation ? "exclamationmark.triangle.fill" : "checkmark.seal.fill",
                    isPositive: !checkIn.didReportViolation
                )
            }
    }
}
