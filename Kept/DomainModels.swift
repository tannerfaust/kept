import Foundation
import SwiftUI

enum ConditionType: String, Codable, CaseIterable, Identifiable {
    case todo = "todo"
    case avoid = "avoid"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: "To-Do"
        case .avoid: "Avoid"
        }
    }

    var symbol: String {
        switch self {
        case .todo: "checkmark.circle.fill"
        case .avoid: "shield.fill"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let str = try container.decode(String.self).lowercased()
        if str == "proactive" || str == "todo" {
            self = .todo
        } else if str == "reactive" || str == "avoid" {
            self = .avoid
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown condition type: \(str)")
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
    case atLeast = "at_least"

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

struct KeptFriend: Identifiable, Codable, Equatable, Hashable {
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
    var type: ConditionType
    var inputType: PactInputType
    var comparison: ComparisonOperator
    var targetValue: Int
    var isRequired: Bool

    func isSatisfied(value: Int?) -> Bool {
        let val = value ?? 0
        switch type {
        case .todo:
            if inputType == .boolean {
                return val == 1
            } else {
                return val >= targetValue
            }
        case .avoid:
            if inputType == .boolean {
                return val == 0 // Clean (no violation)
            } else {
                return val <= targetValue // slips within max allowed limit
            }
        }
    }
}

struct Pact: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var description: String
    var startDate: Date
    var finishDate: Date
    var iconSymbol: String
    var accentColorHex: String
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

struct PactMessage: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let pactID: UUID
    let senderID: UUID
    let senderName: String
    let senderAccentColorHex: String
    let text: String
    let createdAt: Date
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

struct KeptNotification: Identifiable, Codable, Equatable, Hashable {
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
        let hasTodo = pact.conditions.contains(where: { $0.type == .todo })
        guard let checkIn else {
            // Missing check-in counts as violation/failed if there are active To-Do conditions,
            // otherwise (pure reactive boundary) it is clean.
            return !hasTodo
        }
        if checkIn.didReportViolation {
            return false
        }
        return pact.conditions.allSatisfy { condition in
            let val = checkIn.values.first { $0.conditionID == condition.id }?.integerValue
            return condition.isSatisfied(value: val)
        }
    }

    static func dayKeepPercentage(pact: Pact, checkIn: CheckIn?) -> Double {
        guard let checkIn else {
            let hasTodo = pact.conditions.contains(where: { $0.type == .todo })
            return hasTodo ? 0.0 : 1.0
        }
        if checkIn.didReportViolation {
            return 0.0
        }
        guard !pact.conditions.isEmpty else { return 1.0 }
        let satisfiedCount = pact.conditions.filter { condition in
            let val = checkIn.values.first { $0.conditionID == condition.id }?.integerValue
            return condition.isSatisfied(value: val)
        }.count
        return Double(satisfiedCount) / Double(pact.conditions.count)
    }

    static func statusTextAndColor(for percent: Double) -> (text: String, color: Color) {
        let pct = Int(round(percent * 100))
        if pct == 100 {
            return ("WORD KEPT", KeptColor.green)
        } else if pct == 0 {
            return ("PACT BROKEN", KeptColor.coral)
        } else {
            let color: Color
            if percent >= 0.75 {
                color = KeptColor.citron
            } else if percent >= 0.33 {
                color = Color(red: 1.0, green: 0.8, blue: 0.0) // Amber Yellow
            } else {
                color = Color.orange
            }
            return ("KEPT \(pct)%", color)
        }
    }

    static func statusTextAndColor(pact: Pact, checkIn: CheckIn?) -> (text: String, color: Color) {
        guard let checkIn else {
            return ("Open", Color.black.opacity(0.4))
        }
        let percent = dayKeepPercentage(pact: pact, checkIn: checkIn)
        return statusTextAndColor(for: percent)
    }

    static func integrityScore(for pacts: [Pact], checkIns: [CheckIn], userID: UUID, calendar: Calendar = .current) -> IntegritySnapshot {
        var expected = 0
        var completedFraction: Double = 0.0
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
                completedFraction += dayKeepPercentage(pact: pact, checkIn: checkIn)
            }
        }

        guard expected > 0 else {
            return IntegritySnapshot(score: 1, completedUnits: 0, expectedUnits: 0, activePacts: pacts.filter(\.isActiveToday).count, missedDays: 0)
        }

        let completedInt = Int(round(completedFraction))
        return IntegritySnapshot(
            score: completedFraction / Double(expected),
            completedUnits: completedInt,
            expectedUnits: expected,
            activePacts: pacts.filter(\.isActiveToday).count,
            missedDays: expected - completedInt
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

    static func pactFullyCompleted(pact: Pact, checkIns: [CheckIn], userID: UUID, calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: Date())
        let start = calendar.startOfDay(for: pact.startDate)
        guard start <= today else { return false }

        let finish = min(calendar.startOfDay(for: pact.finishDate), today)
        let dayCount = calendar.dateComponents([.day], from: start, to: finish).day ?? 0

        for offset in 0...dayCount {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let checkIn = checkIns.first {
                $0.pactID == pact.id
                    && $0.userID == userID
                    && calendar.isDate($0.day, inSameDayAs: day)
            }
            if !dayPassed(pact: pact, checkIn: checkIn, on: day) {
                return false
            }
        }
        return true
    }

    static func daysCompletedCount(pact: Pact, checkIns: [CheckIn], userID: UUID, calendar: Calendar = .current) -> (completed: Int, total: Int) {
        let today = calendar.startOfDay(for: Date())
        let start = calendar.startOfDay(for: pact.startDate)
        let finish = min(calendar.startOfDay(for: pact.finishDate), today)
        guard start <= finish else { return (0, 0) }

        let dayCount = calendar.dateComponents([.day], from: start, to: finish).day ?? 0
        var total = 0
        var completed = 0

        for offset in 0...dayCount {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            total += 1
            let checkIn = checkIns.first {
                $0.pactID == pact.id
                    && $0.userID == userID
                    && calendar.isDate($0.day, inSameDayAs: day)
            }
            if dayPassed(pact: pact, checkIn: checkIn, on: day) {
                completed += 1
            }
        }

        return (completed, total)
    }

    static func participantDayStatus(pact: Pact, checkIns: [CheckIn], participantID: UUID, calendar: Calendar = .current) -> [(date: Date, passed: Bool, percent: Double, hasReported: Bool)] {
        let today = calendar.startOfDay(for: Date())
        let start = calendar.startOfDay(for: pact.startDate)
        let finish = min(calendar.startOfDay(for: pact.finishDate), today)
        guard start <= finish else { return [] }

        let dayCount = calendar.dateComponents([.day], from: start, to: finish).day ?? 0
        var results: [(date: Date, passed: Bool, percent: Double, hasReported: Bool)] = []

        for offset in 0...dayCount {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let checkIn = checkIns.first {
                $0.pactID == pact.id
                    && $0.userID == participantID
                    && calendar.isDate($0.day, inSameDayAs: day)
            }
            let passed = dayPassed(pact: pact, checkIn: checkIn, on: day)
            let percent = dayKeepPercentage(pact: pact, checkIn: checkIn)
            results.append((date: day, passed: passed, percent: percent, hasReported: checkIn != nil))
        }

        return results
    }
}
