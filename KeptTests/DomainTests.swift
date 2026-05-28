import XCTest
@testable import Kept

final class DomainTests: XCTestCase {
    func testTodoConditionRequiresDoneCheckIn() {
        let user = makeUser()
        let condition = PactCondition(
            id: UUID(),
            title: "Done",
            type: .todo,
            inputType: .boolean,
            comparison: .equals,
            targetValue: 1,
            isRequired: true
        )
        let pact = makePact(user: user, conditions: [condition])

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

    func testAvoidConditionPassesUnlessSlipped() {
        let user = makeUser()
        let condition = PactCondition(
            id: UUID(),
            title: "Avoid Snacking",
            type: .avoid,
            inputType: .boolean,
            comparison: .equals,
            targetValue: 0,
            isRequired: true
        )
        let pact = makePact(user: user, conditions: [condition])

        // Pass by default when there is no check-in (Clean)
        XCTAssertTrue(PactEvaluator.dayPassed(pact: pact, checkIn: nil))

        // Pass when checked-in as Clean (integerValue: 0)
        let cleanCheckIn = CheckIn(
            id: UUID(),
            pactID: pact.id,
            userID: user.id,
            day: Date(),
            note: "",
            didReportViolation: false,
            values: [CheckInValue(id: UUID(), conditionID: condition.id, integerValue: 0)]
        )
        XCTAssertTrue(PactEvaluator.dayPassed(pact: pact, checkIn: cleanCheckIn))

        // Fail when checked-in as Slipped (integerValue: 1)
        let slippedCheckIn = CheckIn(
            id: UUID(),
            pactID: pact.id,
            userID: user.id,
            day: Date(),
            note: "",
            didReportViolation: false,
            values: [CheckInValue(id: UUID(), conditionID: condition.id, integerValue: 1)]
        )
        XCTAssertFalse(PactEvaluator.dayPassed(pact: pact, checkIn: slippedCheckIn))

        // Fail when didReportViolation is true
        let violationCheckIn = CheckIn(
            id: UUID(),
            pactID: pact.id,
            userID: user.id,
            day: Date(),
            note: "Slip",
            didReportViolation: true,
            values: []
        )
        XCTAssertFalse(PactEvaluator.dayPassed(pact: pact, checkIn: violationCheckIn))
    }

    func testIntegrityScoreUsesCompletionRatio() {
        let calendar = Calendar(identifier: .gregorian)
        let user = makeUser()
        let condition = PactCondition(
            id: UUID(),
            title: "Done",
            type: .todo,
            inputType: .boolean,
            comparison: .equals,
            targetValue: 1,
            isRequired: true
        )
        let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        let pact = makePact(user: user, startDate: start, finishDate: Date(), conditions: [condition])
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
        let condition = PactCondition(
            id: UUID(),
            title: "Done",
            type: .todo,
            inputType: .boolean,
            comparison: .equals,
            targetValue: 1,
            isRequired: true
        )
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        let pact = makePact(user: user, startDate: yesterday, finishDate: Date(), conditions: [condition])
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

    func testSupabaseSnakeCaseDecoderSupportsIdAcronyms() throws {
        struct Row: Decodable {
            let friendshipID: UUID
            let requesterID: UUID

            enum CodingKeys: String, CodingKey {
                case friendshipID = "friendshipId"
                case requesterID = "requesterId"
            }
        }

        let friendshipID = UUID()
        let requesterID = UUID()
        let json = """
        [{
            "friendship_id": "\(friendshipID.uuidString)",
            "requester_id": "\(requesterID.uuidString)"
        }]
        """.data(using: .utf8)!

        let rows = try JSONDecoder.kept.decode([Row].self, from: json)

        XCTAssertEqual(rows.first?.friendshipID, friendshipID)
        XCTAssertEqual(rows.first?.requesterID, requesterID)
    }

    @MainActor
    func testCheckInInputMessagesDescribeEveryInput() {
        let user = makeUser()
        let doneCondition = PactCondition(
            id: UUID(),
            title: "Cold shower",
            type: .todo,
            inputType: .boolean,
            comparison: .equals,
            targetValue: 1,
            isRequired: true
        )
        let slippedCondition = PactCondition(
            id: UUID(),
            title: "Avoid snooze",
            type: .avoid,
            inputType: .boolean,
            comparison: .equals,
            targetValue: 0,
            isRequired: true
        )
        let numericCondition = PactCondition(
            id: UUID(),
            title: "Focus minutes",
            type: .todo,
            inputType: .integer,
            comparison: .atLeast,
            targetValue: 90,
            isRequired: true
        )
        let pact = makePact(user: user, conditions: [doneCondition, slippedCondition, numericCondition])

        let messages = KeptStore.checkInInputMessages(
            for: pact,
            checkInValues: [
                CheckInValue(id: UUID(), conditionID: doneCondition.id, integerValue: 1),
                CheckInValue(id: UUID(), conditionID: slippedCondition.id, integerValue: 1),
                CheckInValue(id: UUID(), conditionID: numericCondition.id, integerValue: 75)
            ],
            userName: user.displayName
        )

        XCTAssertEqual(messages, [
            "✅ Test marked Done: Cold shower.",
            "⚠️ Test marked Slipped: Avoid snooze.",
            "⚠️ Test logged Focus minutes: 75 / 90."
        ])
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
            iconSymbol: "bolt.fill",
            accentColorHex: "#ff564d",
            status: .active,
            participants: [PactParticipant(id: UUID(), profile: user, joinedAt: Date(), isOwner: true)],
            conditions: conditions,
            reminderHour: 20,
            reminderMinute: 0
        )
    }
}
