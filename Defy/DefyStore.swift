import Combine
import Foundation
import UserNotifications

@MainActor
final class DefyStore: ObservableObject {
    @Published var currentUser: UserProfile?
    @Published var friends: [DefyFriend] = []
    @Published var pacts: [Pact] = []
    @Published var checkIns: [CheckIn] = []
    @Published var notifications: [DefyNotification] = []
    @Published var isSupabaseConfigured = SupabaseConfiguration.current.isConfigured
    @Published var localAvatarData: Data?

    private let notificationScheduler = NotificationScheduler()

    var acceptedFriends: [DefyFriend] {
        friends.filter { $0.status == .accepted }
    }

    var integrity: IntegritySnapshot {
        guard let currentUser else { return .empty }
        return PactEvaluator.integrityScore(for: pacts, checkIns: checkIns, userID: currentUser.id)
    }

    var todaysPacts: [Pact] {
        pacts.filter(\.isActiveToday)
    }

    var unreadNotifications: Int {
        notifications.filter { !$0.isRead }.count
    }

    var profileSnapshot: ProfileSnapshot {
        guard let currentUser else {
            return ProfileSnapshot(
                integrityScore: 1,
                activePactCount: 0,
                completedUnits: 0,
                expectedUnits: 0,
                missedDays: 0,
                currentStreak: 0,
                bestStreak: 0,
                completionRate: 1,
                recentActivity: []
            )
        }
        return profileSnapshot(for: currentUser.id)
    }

    init(seedDemoData: Bool = true) {
        if seedDemoData {
            loadDemoData()
        }
    }

    func signInWithEmail(_ email: String) {
        ensureDemoIdentity(displayName: email.components(separatedBy: "@").first ?? "Defy User")
        addNotification(title: "Magic link ready", message: "Supabase email auth is configured through the service layer. Demo mode signed you in locally.")
    }

    func signInWithApple() {
        ensureDemoIdentity(displayName: "Tanner")
        addNotification(title: "Apple sign-in ready", message: "Apple auth UI is in place; connect the Supabase project keys to complete the live flow.")
    }

    func updateProfile(name: String, bio: String) {
        updateProfile(name: name, handle: name, bio: bio, accentColorHex: currentUser?.accentColorHex ?? "#ff564d")
    }

    func updateProfile(name: String, handle: String, bio: String, accentColorHex: String) {
        guard var user = currentUser,
              let normalizedHandle = ProfileHandleValidator.normalized(handle) else {
            return
        }

        let snapshot = profileSnapshot(for: user.id)
        user.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        user.handle = normalizedHandle
        user.bio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        user.accentColorHex = accentColorHex
        user.integrityScore = snapshot.integrityScore
        user.currentStreak = snapshot.currentStreak
        user.bestStreak = snapshot.bestStreak
        user.completionRate = snapshot.completionRate
        currentUser = user
        replaceUserInPacts(user)
    }

    func uploadAvatarImage(_ data: Data) async throws -> URL {
        guard var user = currentUser else {
            throw SupabaseError.invalidResponse
        }

        localAvatarData = data
        let url = URL(string: "defy-local-avatar://profiles/\(user.id.uuidString.lowercased()).jpg")!
        user.avatarURL = url
        currentUser = user
        replaceUserInPacts(user)
        addNotification(title: "Avatar updated", message: "Your profile photo is ready in demo mode. Supabase Storage will use the same handoff.")
        return url
    }

    func profileSnapshot(for userID: UUID) -> ProfileSnapshot {
        PactEvaluator.profileSnapshot(for: pacts, checkIns: checkIns, userID: userID)
    }

    func signOut() {
        currentUser = nil
        localAvatarData = nil
    }

    func notificationPermissionStatusText() async -> String {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Allowed"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not requested"
        @unknown default:
            return "Unknown"
        }
    }

    private func replaceUserInPacts(_ user: UserProfile) {
        pacts = pacts.map { pact in
            var updated = pact
            updated.participants = pact.participants.map { participant in
                guard participant.profile.id == user.id else { return participant }
                var updatedParticipant = participant
                updatedParticipant.profile = user
                return updatedParticipant
            }
            return updated
        }
    }

    private func legacyUpdateProfile(name: String, bio: String) {
        currentUser?.displayName = name
        currentUser?.handle = "@\(name.lowercased().replacingOccurrences(of: " ", with: ""))"
        currentUser?.bio = bio
        currentUser?.integrityScore = integrity.score
    }

    func sendFriendRequest(handle: String) {
        let cleanHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHandle.isEmpty else { return }

        let profile = UserProfile(
            id: UUID(),
            displayName: cleanHandle.replacingOccurrences(of: "@", with: "").capitalized,
            handle: cleanHandle.hasPrefix("@") ? cleanHandle : "@\(cleanHandle)",
            bio: "Invited to your accountability circle.",
            avatarSymbol: "sparkles",
            avatarURL: nil,
            accentColorHex: "#d1f23f",
            integrityScore: 0.82,
            currentStreak: 0,
            bestStreak: 0,
            completionRate: 0.82
        )
        friends.append(DefyFriend(id: UUID(), profile: profile, status: .pending, pendingDirection: .outgoing))
        addNotification(title: "Friend request sent", message: "\(profile.displayName) will appear in your pacts when they accept.")
    }

    func acceptFriend(_ friend: DefyFriend) {
        guard let index = friends.firstIndex(where: { $0.id == friend.id }) else { return }
        friends[index].status = .accepted
        friends[index].pendingDirection = nil
        addNotification(title: "Friend added", message: "\(friends[index].profile.displayName) can now join pacts with you.")
    }

    func createPact(draft: PactDraft) {
        guard let currentUser else { return }

        let selectedFriendIDs = Set(draft.friendIDs)
        let friendParticipants = acceptedFriends
            .filter { selectedFriendIDs.contains($0.profile.id) }
            .map { PactParticipant(id: UUID(), profile: $0.profile, joinedAt: Date(), isOwner: false) }

        let owner = PactParticipant(id: UUID(), profile: currentUser, joinedAt: Date(), isOwner: true)
        let pact = Pact(
            id: UUID(),
            title: draft.title,
            description: draft.description,
            startDate: draft.startDate,
            finishDate: draft.finishDate,
            core: draft.core,
            status: .active,
            participants: [owner] + friendParticipants,
            conditions: draft.conditions,
            reminderHour: draft.reminderHour,
            reminderMinute: draft.reminderMinute
        )
        pacts.insert(pact, at: 0)
        addNotification(title: "Pact forged", message: "\(pact.title) is now binding.")
        notificationScheduler.scheduleReminder(for: pact)
    }

    func recordCheckIn(pact: Pact, values: [UUID: Int], note: String = "") {
        guard let currentUser else { return }

        let checkInValues = values.map { conditionID, value in
            CheckInValue(id: UUID(), conditionID: conditionID, integerValue: value)
        }
        upsertCheckIn(
            CheckIn(
                id: UUID(),
                pactID: pact.id,
                userID: currentUser.id,
                day: Date(),
                note: note,
                didReportViolation: false,
                values: checkInValues
            )
        )
        addNotification(title: "Check-in locked", message: "\(pact.title) counted for today.")
    }

    func reportViolation(pact: Pact, note: String) {
        guard let currentUser else { return }

        upsertCheckIn(
            CheckIn(
                id: UUID(),
                pactID: pact.id,
                userID: currentUser.id,
                day: Date(),
                note: note,
                didReportViolation: true,
                values: []
            )
        )
        addNotification(title: "Violation recorded", message: "\(pact.title) marked today as broken.")
    }

    func markNotificationsRead() {
        notifications = notifications.map {
            var item = $0
            item.isRead = true
            return item
        }
    }

    func checkIn(for pact: Pact, on date: Date = Date()) -> CheckIn? {
        guard let currentUser else { return nil }
        return checkIns.first {
            $0.pactID == pact.id
                && $0.userID == currentUser.id
                && Calendar.current.isDate($0.day, inSameDayAs: date)
        }
    }

    private func ensureDemoIdentity(displayName: String) {
        if currentUser == nil {
            currentUser = UserProfile(
                id: UUID(uuidString: "A1111111-1111-4111-8111-111111111111") ?? UUID(),
                displayName: displayName,
                handle: "@\(displayName.lowercased().replacingOccurrences(of: " ", with: ""))",
                bio: "Building discipline in public with a tight circle.",
                avatarSymbol: "bolt.fill",
                avatarURL: nil,
                accentColorHex: "#ff564d",
                integrityScore: 0.91,
                currentStreak: 3,
                bestStreak: 12,
                completionRate: 0.91
            )
        }
    }

    private func addNotification(title: String, message: String, pactID: UUID? = nil) {
        notifications.insert(
            DefyNotification(id: UUID(), title: title, message: message, createdAt: Date(), pactID: pactID, isRead: false),
            at: 0
        )
    }

    private func upsertCheckIn(_ checkIn: CheckIn) {
        if let index = checkIns.firstIndex(where: {
            $0.pactID == checkIn.pactID
                && $0.userID == checkIn.userID
                && Calendar.current.isDate($0.day, inSameDayAs: checkIn.day)
        }) {
            checkIns[index] = checkIn
        } else {
            checkIns.append(checkIn)
        }
        currentUser?.integrityScore = integrity.score
    }

    private func loadDemoData() {
        let user = UserProfile(
            id: UUID(uuidString: "A1111111-1111-4111-8111-111111111111") ?? UUID(),
            displayName: "Tanner",
            handle: "@tanner",
            bio: "Thirty days of doing what I said I would do.",
            avatarSymbol: "bolt.fill",
            avatarURL: nil,
            accentColorHex: "#ff564d",
            integrityScore: 0.91,
            currentStreak: 3,
            bestStreak: 12,
            completionRate: 0.91
        )
        let maya = UserProfile(
            id: UUID(uuidString: "B2222222-2222-4222-8222-222222222222") ?? UUID(),
            displayName: "Maya",
            handle: "@maya",
            bio: "No skipped reps.",
            avatarSymbol: "flame.fill",
            avatarURL: nil,
            accentColorHex: "#38c7eb",
            integrityScore: 0.88,
            currentStreak: 8,
            bestStreak: 18,
            completionRate: 0.88
        )
        let jon = UserProfile(
            id: UUID(uuidString: "C3333333-3333-4333-8333-333333333333") ?? UUID(),
            displayName: "Jon",
            handle: "@jon",
            bio: "Less scrolling, more shipping.",
            avatarSymbol: "target",
            avatarURL: nil,
            accentColorHex: "#795ff0",
            integrityScore: 0.77,
            currentStreak: 2,
            bestStreak: 9,
            completionRate: 0.77
        )
        currentUser = user
        friends = [
            DefyFriend(id: UUID(), profile: maya, status: .accepted, pendingDirection: nil),
            DefyFriend(id: UUID(), profile: jon, status: .pending, pendingDirection: .incoming)
        ]

        let coldShower = PactCondition(id: UUID(), title: "Cold shower completed", inputType: .boolean, comparison: .equals, targetValue: 1, isRequired: true)
        let focusMinutes = PactCondition(id: UUID(), title: "Deep work minutes", inputType: .integer, comparison: .atLeast, targetValue: 90, isRequired: true)
        let detox = PactCondition(id: UUID(), title: "Social media slip", inputType: .boolean, comparison: .equals, targetValue: 0, isRequired: true)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        pacts = [
            Pact(
                id: UUID(),
                title: "Cold shower streak",
                description: "No excuses before coffee. Check in every morning.",
                startDate: calendar.date(byAdding: .day, value: -4, to: today) ?? today,
                finishDate: calendar.date(byAdding: .day, value: 25, to: today) ?? today,
                core: .reactive,
                status: .active,
                participants: [
                    PactParticipant(id: UUID(), profile: user, joinedAt: Date(), isOwner: true),
                    PactParticipant(id: UUID(), profile: maya, joinedAt: Date(), isOwner: false)
                ],
                conditions: [coldShower],
                reminderHour: 8,
                reminderMinute: 15
            ),
            Pact(
                id: UUID(),
                title: "Ship the Defy prototype",
                description: "Ninety minutes minimum deep work each day.",
                startDate: calendar.date(byAdding: .day, value: -2, to: today) ?? today,
                finishDate: calendar.date(byAdding: .day, value: 12, to: today) ?? today,
                core: .reactive,
                status: .active,
                participants: [PactParticipant(id: UUID(), profile: user, joinedAt: Date(), isOwner: true)],
                conditions: [focusMinutes],
                reminderHour: 19,
                reminderMinute: 0
            ),
            Pact(
                id: UUID(),
                title: "30-day digital detox",
                description: "Assume clean days unless a slip is reported.",
                startDate: calendar.date(byAdding: .day, value: -8, to: today) ?? today,
                finishDate: calendar.date(byAdding: .day, value: 21, to: today) ?? today,
                core: .proactive,
                status: .active,
                participants: [
                    PactParticipant(id: UUID(), profile: user, joinedAt: Date(), isOwner: true),
                    PactParticipant(id: UUID(), profile: maya, joinedAt: Date(), isOwner: false)
                ],
                conditions: [detox],
                reminderHour: 21,
                reminderMinute: 30
            )
        ]

        if let pact = pacts.first {
            checkIns = [
                CheckIn(
                    id: UUID(),
                    pactID: pact.id,
                    userID: user.id,
                    day: calendar.date(byAdding: .day, value: -1, to: today) ?? today,
                    note: "Done before breakfast.",
                    didReportViolation: false,
                    values: [CheckInValue(id: UUID(), conditionID: pact.conditions[0].id, integerValue: 1)]
                )
            ]
        }

        notifications = [
            DefyNotification(id: UUID(), title: "Today is live", message: "Two pacts need an explicit check-in before midnight.", createdAt: Date(), pactID: nil, isRead: false),
            DefyNotification(id: UUID(), title: "Maya checked in", message: "Cold shower streak is holding.", createdAt: Date().addingTimeInterval(-3600), pactID: pacts.first?.id, isRead: false)
        ]
    }
}

struct PactDraft {
    var title = ""
    var description = ""
    var startDate = Date()
    var finishDate = Calendar.current.date(byAdding: .day, value: 29, to: Date()) ?? Date()
    var core: PactCore = .reactive
    var friendIDs: [UUID] = []
    var conditions: [PactCondition] = [
        PactCondition(id: UUID(), title: "Did the thing", inputType: .boolean, comparison: .equals, targetValue: 1, isRequired: true)
    ]
    var reminderHour = 20
    var reminderMinute = 0
}

struct NotificationScheduler {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    func scheduleReminder(for pact: Pact) {
        requestAuthorization()
        var components = DateComponents()
        components.hour = pact.reminderHour
        components.minute = pact.reminderMinute

        let content = UNMutableNotificationContent()
        content.title = "Defy check-in"
        content.body = "\(pact.title) needs your word today."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "pact-\(pact.id.uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
