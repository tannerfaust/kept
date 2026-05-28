import Combine
import Foundation
import UserNotifications

@MainActor
final class KeptStore: ObservableObject {
    @Published var currentUser: UserProfile?
    @Published var friends: [KeptFriend] = []
    @Published var pacts: [Pact] = []
    @Published var checkIns: [CheckIn] = []
    @Published var notifications: [KeptNotification] = []
    @Published var pactMessages: [PactMessage] = []
    @Published var isSupabaseConfigured = SupabaseConfiguration.current.isConfigured
    @Published var isAuthBusy = false
    @Published var authStatusMessage = ""
    @Published var friendStatusMessage = ""
    @Published var localAvatarData: Data?

    static let demoUserID = UUID(uuidString: "A1111111-1111-4111-8111-111111111111")!
    static let systemSenderID = UUID(uuidString: "00000000-0000-4000-8000-000000000000")!

    var isCurrentUserDemo: Bool {
        currentUser?.id == Self.demoUserID
    }

    private let notificationScheduler = NotificationScheduler()
    private let backend: KeptBackendService
    private var demoSession: DemoSession?
    private var liveSyncTask: Task<Void, Never>?

    private struct DemoSession {
        let user: UserProfile
        let friends: [KeptFriend]
        let pacts: [Pact]
        let checkIns: [CheckIn]
        let notifications: [KeptNotification]
    }

    var acceptedFriends: [KeptFriend] {
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

    init(seedDemoData: Bool = true, backend: KeptBackendService? = nil) {
        self.backend = backend ?? SupabaseService()
        if seedDemoData {
            demoSession = Self.makeDemoSession()
        }
    }

    static var preview: KeptStore {
        let store = KeptStore()
        store.signInWithApple()
        return store
    }

    func signInWithEmail(_ email: String) {
        if isSupabaseConfigured {
            Task { await sendMagicLink(email: email) }
            return
        }

        let displayName = email.components(separatedBy: "@").first ?? "Kept User"
        activateDemoSession(displayName: displayName.capitalized)
        addNotification(title: "Demo sign-in", message: "Add SUPABASE_URL and SUPABASE_ANON_KEY to use live magic links.")
    }

    func signInWithApple() {
        activateDemoSession(displayName: "Tanner")
        addNotification(title: "Demo sign-in", message: "Apple sign-in is disabled while Kept starts with email magic links.")
    }

    func restoreLiveSessionIfPossible() async {
        guard isSupabaseConfigured, currentUser == nil else { return }
        isAuthBusy = true
        defer { isAuthBusy = false }

        do {
            if let user = try await backend.restoreSession() {
                currentUser = user
                await reloadLiveData(showNotificationOnError: true)
                startLiveSync()
            }
        } catch {
            authStatusMessage = error.localizedDescription
        }
    }

    func handleAuthCallback(_ url: URL) async {
        guard isSupabaseConfigured else { return }
        isAuthBusy = true
        authStatusMessage = "Signing you in..."
        defer { isAuthBusy = false }

        do {
            currentUser = try await backend.handleAuthCallback(url)
            authStatusMessage = ""
            await reloadLiveData(showNotificationOnError: true)
            startLiveSync()
        } catch {
            authStatusMessage = error.localizedDescription
        }
    }

    private func sendMagicLink(email: String) async {
        isAuthBusy = true
        authStatusMessage = "Sending magic link..."
        defer { isAuthBusy = false }

        do {
            try await backend.sendMagicLink(email: email)
            authStatusMessage = "Magic link sent. Open it on this device to sign in."
        } catch {
            authStatusMessage = error.localizedDescription
        }
    }

    func startLiveSync() {
        guard isSupabaseConfigured, currentUser != nil, liveSyncTask == nil else { return }
        liveSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                await self?.reloadLiveData(showNotificationOnError: false)
            }
        }
    }

    private func stopLiveSync() {
        liveSyncTask?.cancel()
        liveSyncTask = nil
    }

    private func reloadLiveData(showNotificationOnError: Bool) async {
        guard isSupabaseConfigured, let currentUser else { return }

        do {
            async let liveFriends = backend.fetchFriends(userID: currentUser.id)
            async let livePacts = backend.fetchPacts(userID: currentUser.id)
            async let liveCheckIns = backend.fetchCheckIns(userID: currentUser.id)
            async let liveMessages = backend.fetchPactMessages(userID: currentUser.id)

            friends = try await liveFriends
            pacts = try await livePacts
            checkIns = try await liveCheckIns
            pactMessages = try await liveMessages
        } catch {
            if showNotificationOnError {
                addNotification(title: "Sync issue", message: error.localizedDescription)
            }
        }
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

        if isSupabaseConfigured, !isCurrentUserDemo {
            Task {
                try? await backend.updateProfile(user)
            }
        }
    }

    func uploadAvatarImage(_ data: Data) async throws -> URL {
        guard var user = currentUser else {
            throw SupabaseError.invalidResponse
        }

        localAvatarData = data
        let url: URL
        if isSupabaseConfigured, !isCurrentUserDemo {
            url = try await backend.uploadAvatarImage(data, userID: user.id)
        } else if let localURL = URL(string: "kept-local-avatar://profiles/\(user.id.uuidString.lowercased()).jpg") {
            url = localURL
        } else {
            throw SupabaseError.invalidResponse
        }
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
        stopLiveSync()
        if isSupabaseConfigured {
            Task { try? await backend.signOut() }
        }
        currentUser = nil
        localAvatarData = nil
        friends = []
        pacts = []
        checkIns = []
        notifications = []
        pactMessages = []
    }

    func clearDemoData() {
        demoSession = nil
        signOut()
    }

    func sendPactMessage(pactID: UUID, text: String) {
        guard let currentUser else { return }
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }

        let message = PactMessage(
            id: UUID(),
            pactID: pactID,
            senderID: currentUser.id,
            senderName: currentUser.displayName,
            senderAccentColorHex: currentUser.accentColorHex,
            text: cleanText,
            createdAt: Date()
        )
        pactMessages.append(message)
        if isSupabaseConfigured, !isCurrentUserDemo {
            Task {
                try? await backend.postPactMessage(message)
            }
        }
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
        guard let normalizedHandle = ProfileHandleValidator.normalized(handle) else {
            friendStatusMessage = "Use a valid @handle."
            return
        }

        if isSupabaseConfigured, !isCurrentUserDemo {
            Task { await sendLiveFriendRequest(handle: normalizedHandle) }
            return
        }

        let profile = UserProfile(
            id: UUID(),
            displayName: normalizedHandle.replacingOccurrences(of: "@", with: "").capitalized,
            handle: normalizedHandle,
            bio: "Invited to your accountability circle.",
            avatarSymbol: "sparkles",
            avatarURL: nil,
            accentColorHex: "#d1f23f",
            integrityScore: 0.82,
            currentStreak: 0,
            bestStreak: 0,
            completionRate: 0.82
        )
        friends.append(KeptFriend(id: UUID(), profile: profile, status: .pending, pendingDirection: .outgoing))
        addNotification(title: "Friend request sent", message: "\(profile.displayName) will appear in your pacts when they accept.")
    }

    func findFriend(handle: String) {
        guard let normalizedHandle = ProfileHandleValidator.normalized(handle) else {
            friendStatusMessage = "Use a valid @handle."
            return
        }

        if isSupabaseConfigured, !isCurrentUserDemo {
            Task { await findLiveFriend(handle: normalizedHandle) }
            return
        }

        friendStatusMessage = "Demo mode can add a pending friend request, but live search needs Supabase."
    }

    func acceptFriend(_ friend: KeptFriend) {
        if isSupabaseConfigured, !isCurrentUserDemo {
            Task { await acceptLiveFriend(friend) }
            return
        }

        guard let index = friends.firstIndex(where: { $0.id == friend.id }) else { return }
        friends[index].status = .accepted
        friends[index].pendingDirection = nil
        addNotification(title: "Friend added", message: "\(friends[index].profile.displayName) can now join pacts with you.")
    }

    private func findLiveFriend(handle: String) async {
        friendStatusMessage = "Searching..."
        do {
            guard let profile = try await backend.findProfile(handle: handle) else {
                friendStatusMessage = "No user found for \(handle)."
                return
            }
            if profile.id == currentUser?.id {
                friendStatusMessage = "That is your own handle."
            } else if friends.contains(where: { $0.profile.id == profile.id }) {
                friendStatusMessage = "\(profile.displayName) is already in your network."
            } else {
                friendStatusMessage = "Found \(profile.displayName). Tap Add to send a request."
            }
        } catch {
            friendStatusMessage = error.localizedDescription
        }
    }

    private func sendLiveFriendRequest(handle: String) async {
        friendStatusMessage = "Sending request..."
        do {
            let friend = try await backend.sendFriendRequest(handle: handle)
            if let index = friends.firstIndex(where: { $0.id == friend.id || $0.profile.id == friend.profile.id }) {
                friends[index] = friend
            } else {
                friends.insert(friend, at: 0)
            }
            friendStatusMessage = "Friend request sent to \(friend.profile.displayName)."
            addNotification(title: "Friend request sent", message: "\(friend.profile.displayName) can accept your request now.")
        } catch {
            friendStatusMessage = error.localizedDescription
        }
    }

    private func acceptLiveFriend(_ friend: KeptFriend) async {
        friendStatusMessage = "Accepting request..."
        do {
            let updatedFriend = try await backend.acceptFriendRequest(friend)
            if let index = friends.firstIndex(where: { $0.id == updatedFriend.id }) {
                friends[index] = updatedFriend
            }
            friendStatusMessage = "\(updatedFriend.profile.displayName) is now a friend."
            addNotification(title: "Friend added", message: "\(updatedFriend.profile.displayName) can now join pacts with you.")
        } catch {
            friendStatusMessage = error.localizedDescription
        }
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
            iconSymbol: draft.iconSymbol,
            accentColorHex: draft.accentColorHex,
            status: .active,
            participants: [owner] + friendParticipants,
            conditions: draft.conditions,
            reminderHour: draft.reminderHour,
            reminderMinute: draft.reminderMinute
        )
        pacts.insert(pact, at: 0)
        addNotification(title: "Pact forged", message: "\(pact.title) is now binding.")
        notificationScheduler.scheduleReminder(for: pact)

        if isSupabaseConfigured, !isCurrentUserDemo {
            Task {
                do {
                    try await backend.createPact(pact)
                } catch {
                    addNotification(title: "Pact sync failed", message: error.localizedDescription, pactID: pact.id)
                }
            }
        }
    }

    func postSystemMessage(pactID: UUID, text: String) {
        let msg = PactMessage(
            id: UUID(),
            pactID: pactID,
            senderID: Self.systemSenderID,
            senderName: "System",
            senderAccentColorHex: "#888888",
            text: text,
            createdAt: Date()
        )
        pactMessages.append(msg)
        if isSupabaseConfigured, !isCurrentUserDemo {
            Task {
                try? await backend.postPactMessage(msg)
            }
        }
    }

    func recordCheckIn(pact: Pact, values: [UUID: Int], note: String = "") {
        guard let currentUser else { return }

        let checkInValues = values.map { conditionID, value in
            CheckInValue(id: UUID(), conditionID: conditionID, integerValue: value)
        }
        let checkIn = CheckIn(
            id: UUID(),
            pactID: pact.id,
            userID: currentUser.id,
            day: Date(),
            note: note,
            didReportViolation: false,
            values: checkInValues
        )
        upsertCheckIn(checkIn)
        addNotification(title: "Check-in locked", message: "\(pact.title) counted for today.")

        if isSupabaseConfigured, !isCurrentUserDemo {
            Task {
                do {
                    try await backend.submitCheckIn(checkIn)
                } catch {
                    addNotification(title: "Check-in sync failed", message: error.localizedDescription, pactID: pact.id)
                }
            }
        }

        for message in Self.checkInInputMessages(for: pact, checkInValues: checkInValues, userName: currentUser.displayName) {
            postSystemMessage(pactID: pact.id, text: message)
        }

        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            postSystemMessage(pactID: pact.id, text: "📝 \(currentUser.displayName) added a note: \"\(note)\"")
        }

        // Generate descriptive system message for the chat
        let percent = PactEvaluator.dayKeepPercentage(pact: pact, checkIn: checkIn)
        let display = PactEvaluator.statusTextAndColor(for: percent)
        let pct = Int(round(percent * 100))
        
        var detailsText = ""
        let satisfiedConditions = pact.conditions.filter { cond in
            let val = checkInValues.first { $0.conditionID == cond.id }?.integerValue
            return cond.isSatisfied(value: val)
        }
        
        if pct == 100 {
            detailsText = "✅ \(currentUser.displayName) kept their word! (100% completed)"
        } else if pct == 0 {
            detailsText = "🚨 \(currentUser.displayName) broke the pact today (0% completed)."
        } else {
            let metTitles = satisfiedConditions.map { $0.title }.joined(separator: ", ")
            detailsText = "⚠️ \(currentUser.displayName) checked in: \(display.text) (\(metTitles) kept)."
        }

        postSystemMessage(pactID: pact.id, text: detailsText)
    }

    static func checkInInputMessages(for pact: Pact, checkInValues: [CheckInValue], userName: String) -> [String] {
        pact.conditions.map { condition in
            let value = checkInValues.first { $0.conditionID == condition.id }?.integerValue ?? 0
            let satisfied = condition.isSatisfied(value: value)

            switch (condition.type, condition.inputType) {
            case (.todo, .boolean):
                let state = satisfied ? "Done" : "Not done"
                let symbol = satisfied ? "✅" : "⬜"
                return "\(symbol) \(userName) marked \(state): \(condition.title)."
            case (.todo, .integer):
                let symbol = satisfied ? "✅" : "⚠️"
                return "\(symbol) \(userName) logged \(condition.title): \(value) / \(condition.targetValue)."
            case (.avoid, .boolean):
                let state = satisfied ? "Clean" : "Slipped"
                let symbol = satisfied ? "🛡️" : "⚠️"
                return "\(symbol) \(userName) marked \(state): \(condition.title)."
            case (.avoid, .integer):
                let symbol = satisfied ? "🛡️" : "⚠️"
                return "\(symbol) \(userName) logged \(condition.title): \(value) slip\(value == 1 ? "" : "s") / max \(condition.targetValue)."
            }
        }
    }

    func reportViolation(pact: Pact, note: String) {
        guard let currentUser else { return }

        let checkIn = CheckIn(
            id: UUID(),
            pactID: pact.id,
            userID: currentUser.id,
            day: Date(),
            note: note,
            didReportViolation: true,
            values: []
        )
        upsertCheckIn(checkIn)
        addNotification(title: "Violation recorded", message: "\(pact.title) marked today as broken.")

        if isSupabaseConfigured, !isCurrentUserDemo {
            Task {
                do {
                    try await backend.submitCheckIn(checkIn)
                } catch {
                    addNotification(title: "Violation sync failed", message: error.localizedDescription, pactID: pact.id)
                }
            }
        }

        var msgText = "🚨 \(currentUser.displayName) reported a violation today."
        if !note.isEmpty {
            msgText += " Reason: \"\(note)\""
        }
        postSystemMessage(pactID: pact.id, text: msgText)
    }

    func deleteCheckIn(for pact: Pact, on date: Date = Date()) {
        guard let currentUser else { return }
        checkIns.removeAll {
            $0.pactID == pact.id
                && $0.userID == currentUser.id
                && Calendar.current.isDate($0.day, inSameDayAs: date)
        }
        self.currentUser?.integrityScore = integrity.score
        addNotification(title: "Check-in unlocked", message: "\(pact.title) is open for edit.")

        if isSupabaseConfigured, !isCurrentUserDemo {
            Task {
                do {
                    try await backend.deleteCheckIn(pactID: pact.id, userID: currentUser.id, day: date)
                } catch {
                    addNotification(title: "Unlock sync failed", message: error.localizedDescription, pactID: pact.id)
                }
            }
        }

        postSystemMessage(pactID: pact.id, text: "🔓 \(currentUser.displayName) unlocked today's check-in for editing.")
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

    func pactProgress(for pact: Pact, userID: UUID) -> (completed: Int, total: Int) {
        PactEvaluator.daysCompletedCount(pact: pact, checkIns: checkIns, userID: userID)
    }

    private func activateDemoSession(displayName: String) {
        guard let demoSession else {
            currentUser = UserProfile(
                id: UUID(),
                displayName: displayName,
                handle: "@\(displayName.lowercased().replacingOccurrences(of: " ", with: ""))",
                bio: "",
                avatarSymbol: "bolt.fill",
                avatarURL: nil,
                accentColorHex: "#ff564d",
                integrityScore: 1,
                currentStreak: 0,
                bestStreak: 0,
                completionRate: 1
            )
            return
        }

        var user = demoSession.user
        user.displayName = displayName
        currentUser = user
        friends = demoSession.friends
        pacts = demoSession.pacts
        checkIns = demoSession.checkIns
        notifications = demoSession.notifications
        seedDemoMessages()
        refreshUserStats()
    }

    private func seedDemoMessages() {
        guard let firstPactID = pacts.first?.id,
              let secondPactID = pacts.dropFirst().first?.id else { return }

        let mayaID = UUID(uuidString: "B2222222-2222-4222-8222-222222222222") ?? UUID()
        let systemID = Self.systemSenderID

        pactMessages = [
            // System event
            PactMessage(
                id: UUID(),
                pactID: firstPactID,
                senderID: systemID,
                senderName: "System",
                senderAccentColorHex: "#888888",
                text: "📋 Pact \"Ultimate Morning Protocol\" started — Day 1",
                createdAt: Date().addingTimeInterval(-86400 * 4)
            ),
            PactMessage(
                id: UUID(),
                pactID: firstPactID,
                senderID: mayaID,
                senderName: "Maya",
                senderAccentColorHex: "#38c7eb",
                text: "Cold shower was freezing today! Did you lock it in yet?",
                createdAt: Date().addingTimeInterval(-7200)
            ),
            PactMessage(
                id: UUID(),
                pactID: firstPactID,
                senderID: Self.demoUserID,
                senderName: "Tanner",
                senderAccentColorHex: "#ff564d",
                text: "Just did it. Wakes you right up!",
                createdAt: Date().addingTimeInterval(-3600)
            ),
            // System event — streak
            PactMessage(
                id: UUID(),
                pactID: firstPactID,
                senderID: systemID,
                senderName: "System",
                senderAccentColorHex: "#888888",
                text: "🔥 Maya hit a 3-day streak!",
                createdAt: Date().addingTimeInterval(-1800)
            ),
            PactMessage(
                id: UUID(),
                pactID: firstPactID,
                senderID: mayaID,
                senderName: "Maya",
                senderAccentColorHex: "#38c7eb",
                text: "Let's gooo 💪",
                createdAt: Date().addingTimeInterval(-1700)
            ),
            PactMessage(
                id: UUID(),
                pactID: secondPactID,
                senderID: Self.demoUserID,
                senderName: "Tanner",
                senderAccentColorHex: "#ff564d",
                text: "Focus block started. 90 minutes on the clock.",
                createdAt: Date().addingTimeInterval(-1800)
            ),
            // System event
            PactMessage(
                id: UUID(),
                pactID: secondPactID,
                senderID: systemID,
                senderName: "System",
                senderAccentColorHex: "#888888",
                text: "✅ Tanner locked today's check-in",
                createdAt: Date().addingTimeInterval(-900)
            )
        ]
    }

    private func refreshUserStats() {
        guard var user = currentUser else { return }
        let snapshot = profileSnapshot(for: user.id)
        user.integrityScore = snapshot.integrityScore
        user.currentStreak = snapshot.currentStreak
        user.bestStreak = snapshot.bestStreak
        user.completionRate = snapshot.completionRate
        currentUser = user
        replaceUserInPacts(user)
    }

    private func addNotification(title: String, message: String, pactID: UUID? = nil) {
        notifications.insert(
            KeptNotification(id: UUID(), title: title, message: message, createdAt: Date(), pactID: pactID, isRead: false),
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

    private static func makeDemoSession() -> DemoSession {
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
        let friends = [
            KeptFriend(id: UUID(), profile: maya, status: .accepted, pendingDirection: nil),
            KeptFriend(id: UUID(), profile: jon, status: .pending, pendingDirection: .incoming)
        ]

        let coldShower = PactCondition(id: UUID(), title: "Cold shower completed", type: .todo, inputType: .boolean, comparison: .equals, targetValue: 1, isRequired: true)
        let snoozeAvoid = PactCondition(id: UUID(), title: "Avoid snooze button", type: .avoid, inputType: .boolean, comparison: .equals, targetValue: 0, isRequired: true)

        let focusMinutes = PactCondition(id: UUID(), title: "Deep work focus", type: .todo, inputType: .integer, comparison: .atLeast, targetValue: 90, isRequired: true)
        let socialSlips = PactCondition(id: UUID(), title: "Social media limit", type: .avoid, inputType: .integer, comparison: .equals, targetValue: 0, isRequired: true)

        let junkFoodSlips = PactCondition(id: UUID(), title: "Avoid junk food", type: .avoid, inputType: .boolean, comparison: .equals, targetValue: 0, isRequired: true)
        let waterIntake = PactCondition(id: UUID(), title: "Drink 3L Water", type: .todo, inputType: .boolean, comparison: .equals, targetValue: 1, isRequired: true)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let pacts = [
            Pact(
                id: UUID(),
                title: "Ultimate Morning Protocol",
                description: "No excuses. Set the tone for the day.",
                startDate: calendar.date(byAdding: .day, value: -4, to: today) ?? today,
                finishDate: calendar.date(byAdding: .day, value: 25, to: today) ?? today,
                iconSymbol: "bolt.fill",
                accentColorHex: "#ff564d",
                status: .active,
                participants: [
                    PactParticipant(id: UUID(), profile: user, joinedAt: Date(), isOwner: true),
                    PactParticipant(id: UUID(), profile: maya, joinedAt: Date(), isOwner: false)
                ],
                conditions: [coldShower, snoozeAvoid],
                reminderHour: 8,
                reminderMinute: 15
            ),
            Pact(
                id: UUID(),
                title: "Deep Work Sprint",
                description: "Ninety minutes deep work, zero browsing.",
                startDate: calendar.date(byAdding: .day, value: -2, to: today) ?? today,
                finishDate: calendar.date(byAdding: .day, value: 12, to: today) ?? today,
                iconSymbol: "brain.headset",
                accentColorHex: "#795ff0",
                status: .active,
                participants: [PactParticipant(id: UUID(), profile: user, joinedAt: Date(), isOwner: true)],
                conditions: [focusMinutes, socialSlips],
                reminderHour: 19,
                reminderMinute: 0
            ),
            Pact(
                id: UUID(),
                title: "Healthy Habits Circle",
                description: "Fuel the body and hydrate properly.",
                startDate: calendar.date(byAdding: .day, value: -8, to: today) ?? today,
                finishDate: calendar.date(byAdding: .day, value: 21, to: today) ?? today,
                iconSymbol: "leaf.fill",
                accentColorHex: "#d1f23f",
                status: .active,
                participants: [
                    PactParticipant(id: UUID(), profile: user, joinedAt: Date(), isOwner: true),
                    PactParticipant(id: UUID(), profile: maya, joinedAt: Date(), isOwner: false)
                ],
                conditions: [junkFoodSlips, waterIntake],
                reminderHour: 21,
                reminderMinute: 30
            )
        ]

        let checkIns = [
            CheckIn(
                id: UUID(),
                pactID: pacts[0].id,
                userID: user.id,
                day: calendar.date(byAdding: .day, value: -1, to: today) ?? today,
                note: "Shower was freezing, but didn't snooze.",
                didReportViolation: false,
                values: [
                    CheckInValue(id: UUID(), conditionID: coldShower.id, integerValue: 1),
                    CheckInValue(id: UUID(), conditionID: snoozeAvoid.id, integerValue: 0)
                ]
            ),
            CheckIn(
                id: UUID(),
                pactID: pacts[0].id,
                userID: maya.id,
                day: calendar.date(byAdding: .day, value: -1, to: today) ?? today,
                note: "Done!",
                didReportViolation: false,
                values: [
                    CheckInValue(id: UUID(), conditionID: coldShower.id, integerValue: 1),
                    CheckInValue(id: UUID(), conditionID: snoozeAvoid.id, integerValue: 0)
                ]
            ),
            CheckIn(
                id: UUID(),
                pactID: pacts[1].id,
                userID: user.id,
                day: calendar.date(byAdding: .day, value: -1, to: today) ?? today,
                note: "100 mins done.",
                didReportViolation: false,
                values: [
                    CheckInValue(id: UUID(), conditionID: focusMinutes.id, integerValue: 100),
                    CheckInValue(id: UUID(), conditionID: socialSlips.id, integerValue: 0)
                ]
            ),
            CheckIn(
                id: UUID(),
                pactID: pacts[2].id,
                userID: user.id,
                day: calendar.date(byAdding: .day, value: -1, to: today) ?? today,
                note: "Water target met.",
                didReportViolation: false,
                values: [
                    CheckInValue(id: UUID(), conditionID: junkFoodSlips.id, integerValue: 0),
                    CheckInValue(id: UUID(), conditionID: waterIntake.id, integerValue: 1)
                ]
            ),
            CheckIn(
                id: UUID(),
                pactID: pacts[2].id,
                userID: maya.id,
                day: calendar.date(byAdding: .day, value: -1, to: today) ?? today,
                note: "Slipped and ate a cookie.",
                didReportViolation: false,
                values: [
                    CheckInValue(id: UUID(), conditionID: junkFoodSlips.id, integerValue: 1),
                    CheckInValue(id: UUID(), conditionID: waterIntake.id, integerValue: 1)
                ]
            )
        ]

        let notifications = [
            KeptNotification(id: UUID(), title: "Today is live", message: "Two pacts need an explicit check-in before midnight.", createdAt: Date(), pactID: nil, isRead: false),
            KeptNotification(id: UUID(), title: "Maya checked in", message: "Cold shower streak is holding.", createdAt: Date().addingTimeInterval(-3600), pactID: pacts.first?.id, isRead: false)
        ]

        return DemoSession(user: user, friends: friends, pacts: pacts, checkIns: checkIns, notifications: notifications)
    }
}

struct PactDraft {
    var title = ""
    var description = ""
    var startDate = Date()
    var finishDate = Calendar.current.date(byAdding: .day, value: 29, to: Date()) ?? Date()
    var iconSymbol = "bolt.fill"
    var accentColorHex = "#ff564d"
    var friendIDs: [UUID] = []
    var conditions: [PactCondition] = [
        PactCondition(id: UUID(), title: "Did the thing", type: .todo, inputType: .boolean, comparison: .equals, targetValue: 1, isRequired: true)
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
        content.title = "Kept check-in"
        content.body = "\(pact.title) needs your word today."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "pact-\(pact.id.uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
