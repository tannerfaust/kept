import XCTest
@testable import Defy

final class DomainTests: XCTestCase {
    func testReactivePactRequiresPassingCheckIn() {
        let user = makeUser()
        let condition = PactCondition(id: UUID(), title: "Done", inputType: .boolean, comparison: .equals, targetValue: 1, isRequired: true)
        let pact = makePact(user: user, core: .reactive, conditions: [condition])

        XCTAssertFalse(PactEvaluator.dayPassed(pact: pact, checkIn: nil))

        let checkIn = CheckIn(
            id: UUID(),
            pactID: pact.id,
            userID: user.id,
            day: Date(),
            note: "",
            didReportViolation: false,
            values: [CheckInValue(id: UUID(), conditionID: condition.id, integerValue: 1)]
        )
        XCTAssertTrue(PactEvaluator.dayPassed(pact: pact, checkIn: checkIn))
    }

    func testProactivePactPassesUnlessViolationIsReported() {
        let user = makeUser()
        let pact = makePact(user: user, core: .proactive, conditions: [])

        XCTAssertTrue(PactEvaluator.dayPassed(pact: pact, checkIn: nil))

        let violation = CheckIn(id: UUID(), pactID: pact.id, userID: user.id, day: Date(), note: "Slip", didReportViolation: true, values: [])
        XCTAssertFalse(PactEvaluator.dayPassed(pact: pact, checkIn: violation))
    }

    func testIntegrityScoreUsesCompletionRatio() {
        let calendar = Calendar(identifier: .gregorian)
        let user = makeUser()
        let condition = PactCondition(id: UUID(), title: "Done", inputType: .boolean, comparison: .equals, targetValue: 1, isRequired: true)
        let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        let pact = makePact(user: user, core: .reactive, startDate: start, finishDate: Date(), conditions: [condition])
        let checkIn = CheckIn(
            id: UUID(),
            pactID: pact.id,
            userID: user.id,
            day: start,
            note: "",
            didReportViolation: false,
            values: [CheckInValue(id: UUID(), conditionID: condition.id, integerValue: 1)]
        )

        let snapshot = PactEvaluator.integrityScore(for: [pact], checkIns: [checkIn], userID: user.id, calendar: calendar)

        XCTAssertEqual(snapshot.completedUnits, 1)
        XCTAssertEqual(snapshot.expectedUnits, 2)
        XCTAssertEqual(snapshot.score, 0.5, accuracy: 0.001)
    }

    func testProfileSnapshotCalculatesStreaksAndCompletionRate() {
        let calendar = Calendar(identifier: .gregorian)
        let user = makeUser()
        let condition = PactCondition(id: UUID(), title: "Done", inputType: .boolean, comparison: .equals, targetValue: 1, isRequired: true)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        let pact = makePact(user: user, core: .reactive, startDate: yesterday, finishDate: Date(), conditions: [condition])
        let checkIns = [
            CheckIn(
                id: UUID(),
                pactID: pact.id,
                userID: user.id,
                day: yesterday,
                note: "",
                didReportViolation: false,
                values: [CheckInValue(id: UUID(), conditionID: condition.id, integerValue: 1)]
            ),
            CheckIn(
                id: UUID(),
                pactID: pact.id,
                userID: user.id,
                day: Date(),
                note: "",
                didReportViolation: false,
                values: [CheckInValue(id: UUID(), conditionID: condition.id, integerValue: 1)]
            )
        ]

        let snapshot = PactEvaluator.profileSnapshot(for: [pact], checkIns: checkIns, userID: user.id, calendar: calendar)

        XCTAssertEqual(snapshot.currentStreak, 2)
        XCTAssertEqual(snapshot.bestStreak, 2)
        XCTAssertEqual(snapshot.completionRate, 1, accuracy: 0.001)
        XCTAssertEqual(snapshot.recentActivity.count, 2)
    }

    func testHandleNormalizationRejectsSpacesAndPreservesValidHandles() {
        XCTAssertEqual(ProfileHandleValidator.normalized("Tanner_01"), "@tanner_01")
        XCTAssertEqual(ProfileHandleValidator.normalized("@maya"), "@maya")
        XCTAssertNil(ProfileHandleValidator.normalized("@bad handle"))
    }

    func testProfileAvatarFallbackExistsWhenNoAvatarURLExists() {
        let user = makeUser()

        XCTAssertNil(user.avatarURL)
        XCTAssertEqual(user.avatarSymbol, "bolt.fill")
    }

    private func makeUser() -> UserProfile {
        UserProfile(
            id: UUID(),
            displayName: "Test",
            handle: "@test",
            bio: "",
            avatarSymbol: "bolt.fill",
            avatarURL: nil,
            accentColorHex: "#ff564d",
            integrityScore: 1,
            currentStreak: 0,
            bestStreak: 0,
            completionRate: 1
        )
    }

    private func makePact(
        user: UserProfile,
        core: PactCore,
        startDate: Date = Date(),
        finishDate: Date = Date(),
        conditions: [PactCondition]
    ) -> Pact {
        Pact(
            id: UUID(),
            title: "Test Pact",
            description: "",
            startDate: startDate,
            finishDate: finishDate,
            core: core,
            status: .active,
            participants: [PactParticipant(id: UUID(), profile: user, joinedAt: Date(), isOwner: true)],
            conditions: conditions,
            reminderHour: 20,
            reminderMinute: 0
        )
    }
}
