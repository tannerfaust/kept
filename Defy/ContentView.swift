import PhotosUI
import SwiftUI
import UIKit

enum DefyTab: String, CaseIterable, Identifiable {
    case today
    case pacts
    case friends
    case metrics
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .pacts: "Pacts"
        case .friends: "Friends"
        case .metrics: "Metrics"
        case .profile: "Profile"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .pacts: "seal.fill"
        case .friends: "person.2.fill"
        case .metrics: "chart.line.uptrend.xyaxis"
        case .profile: "person.crop.circle.fill"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: DefyStore
    @State private var tab: DefyTab = .today

    var body: some View {
        ZStack {
            AppBackground()
            if store.currentUser == nil {
                AuthView()
            } else {
                TabView(selection: $tab) {
                    TodayView()
                        .tabItem { Label(DefyTab.today.title, systemImage: DefyTab.today.symbol) }
                        .tag(DefyTab.today)
                    PactsView()
                        .tabItem { Label(DefyTab.pacts.title, systemImage: DefyTab.pacts.symbol) }
                        .tag(DefyTab.pacts)
                    FriendsView()
                        .tabItem { Label(DefyTab.friends.title, systemImage: DefyTab.friends.symbol) }
                        .tag(DefyTab.friends)
                    MetricsView()
                        .tabItem { Label(DefyTab.metrics.title, systemImage: DefyTab.metrics.symbol) }
                        .tag(DefyTab.metrics)
                    ProfileView()
                        .tabItem { Label(DefyTab.profile.title, systemImage: DefyTab.profile.symbol) }
                        .tag(DefyTab.profile)
                }
                .tint(DefyColor.ink)
            }
        }
        .preferredColorScheme(.light)
    }
}

struct AuthView: View {
    @EnvironmentObject private var store: DefyStore
    @State private var email = ""

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "bolt.badge.checkmark.fill")
                    .font(.system(size: 54, weight: .black))
                    .foregroundStyle(DefyColor.coral, DefyColor.citron)
                Text("Defy")
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .foregroundStyle(DefyColor.ink)
                Text("Give your word. Make it measurable.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 20)

            VStack(spacing: 12) {
                Button {
                    store.signInWithApple()
                } label: {
                    Label("Continue with Apple", systemImage: "apple.logo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .padding()
                    .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button {
                    store.signInWithEmail(email)
                } label: {
                    Label("Send magic link", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(email.isEmpty)
            }
            .padding(18)
            .defyGlass(cornerRadius: 28, interactive: true)
            .cardShadow()

            Text(store.isSupabaseConfigured ? "Live Supabase configuration detected." : "Demo mode: add SUPABASE_URL and SUPABASE_ANON_KEY to connect the live backend.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
    }
}

struct TodayView: View {
    @EnvironmentObject private var store: DefyStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HeaderBlock(
                        eyebrow: "Today",
                        title: "Keep the word visible.",
                        subtitle: "\(store.todaysPacts.count) live pacts. \(store.unreadNotifications) unread signals."
                    )

                    HStack(spacing: 12) {
                        MetricPill(title: "Integrity", value: "\(Int(store.integrity.score * 100))%", color: DefyColor.green)
                        MetricPill(title: "Missed days", value: "\(store.integrity.missedDays)", color: DefyColor.coral)
                    }

                    ForEach(store.todaysPacts) { pact in
                        NavigationLink(value: pact) {
                            PactTodayCard(pact: pact, checkIn: store.checkIn(for: pact))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationDestination(for: Pact.self) { pact in
                PactDetailView(pact: pact)
            }
            .navigationTitle("Defy")
        }
    }
}

struct PactsView: View {
    @EnvironmentObject private var store: DefyStore
    @State private var isMakingPact = false

    var body: some View {
        NavigationStack {
            List {
                Section("Active") {
                    ForEach(store.pacts.filter { $0.status == .active }) { pact in
                        NavigationLink(value: pact) {
                            PactRow(pact: pact, checkIn: store.checkIn(for: pact))
                        }
                    }
                }
                Section("Upcoming and finished") {
                    ForEach(store.pacts.filter { $0.status != .active }) { pact in
                        PactRow(pact: pact, checkIn: store.checkIn(for: pact))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Pacts")
            .navigationDestination(for: Pact.self) { pact in
                PactDetailView(pact: pact)
            }
            .toolbar {
                Button {
                    isMakingPact = true
                } label: {
                    Label("Forge", systemImage: "plus")
                }
            }
            .sheet(isPresented: $isMakingPact) {
                PactMakerView()
            }
        }
    }
}

struct PactMakerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DefyStore
    @State private var draft = PactDraft()
    @State private var selectedFriendIDs = Set<UUID>()

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Pact title", text: $draft.title)
                    TextField("Description", text: $draft.description, axis: .vertical)
                    Picker("Core", selection: $draft.core) {
                        ForEach(PactCore.allCases) { core in
                            Label(core.title, systemImage: core.symbol).tag(core)
                        }
                    }
                }

                Section("Dates") {
                    DatePicker("Start", selection: $draft.startDate, displayedComponents: .date)
                    DatePicker("Finish", selection: $draft.finishDate, displayedComponents: .date)
                    DatePicker("Reminder", selection: reminderBinding, displayedComponents: .hourAndMinute)
                }

                Section("Participants") {
                    if store.acceptedFriends.isEmpty {
                        Text("Solo pact. Add accepted friends to invite participants.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.acceptedFriends) { friend in
                        Toggle(friend.profile.displayName, isOn: Binding(
                            get: { selectedFriendIDs.contains(friend.profile.id) },
                            set: { isOn in
                                if isOn {
                                    selectedFriendIDs.insert(friend.profile.id)
                                } else {
                                    selectedFriendIDs.remove(friend.profile.id)
                                }
                            }
                        ))
                    }
                }

                Section("Daily condition") {
                    ForEach($draft.conditions) { $condition in
                        TextField("Condition", text: $condition.title)
                        Picker("Input", selection: $condition.inputType) {
                            ForEach(PactInputType.allCases) { input in
                                Text(input.title).tag(input)
                            }
                        }
                        if condition.inputType == .integer {
                            Stepper("Target: \(condition.targetValue)", value: $condition.targetValue, in: 1...1000)
                            Picker("Rule", selection: $condition.comparison) {
                                Text("At least").tag(ComparisonOperator.atLeast)
                                Text("Equals").tag(ComparisonOperator.equals)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Forge Pact")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        draft.friendIDs = Array(selectedFriendIDs)
                        store.createPact(draft: draft)
                        dismiss()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var reminderBinding: Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(hour: draft.reminderHour, minute: draft.reminderMinute)) ?? Date()
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            draft.reminderHour = components.hour ?? 20
            draft.reminderMinute = components.minute ?? 0
        }
    }
}

struct PactDetailView: View {
    @EnvironmentObject private var store: DefyStore
    let pact: Pact
    @State private var values: [UUID: Int] = [:]
    @State private var note = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PactHero(pact: pact)

                VStack(alignment: .leading, spacing: 12) {
                    Label("War Room", systemImage: "person.2.badge.gearshape.fill")
                        .font(.headline)
                    ForEach(pact.participants) { participant in
                        HStack {
                            Avatar(symbol: participant.profile.avatarSymbol, color: participant.isOwner ? DefyColor.coral : DefyColor.cyan)
                            VStack(alignment: .leading) {
                                Text(participant.profile.displayName)
                                    .font(.subheadline.weight(.bold))
                                Text(participant.isOwner ? "Owner" : "Participant")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: participantStatusSymbol)
                                .foregroundStyle(participantStatusColor)
                        }
                    }
                }
                .padding()
                .defyGlass(cornerRadius: 24)

                if pact.core == .reactive {
                    CheckInForm(pact: pact, values: $values, note: $note)
                    Button {
                        store.recordCheckIn(pact: pact, values: preparedValues, note: note)
                    } label: {
                        Label("Lock today", systemImage: "checkmark.seal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Proactive pact")
                            .font(.headline)
                        Text("Today counts as clean unless you report a violation.")
                            .foregroundStyle(.secondary)
                        TextField("What happened?", text: $note, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        Button(role: .destructive) {
                            store.reportViolation(pact: pact, note: note)
                        } label: {
                            Label("Report violation", systemImage: "exclamationmark.triangle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .defyGlass(cornerRadius: 24)
                }
            }
            .padding()
        }
        .navigationTitle(pact.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            for condition in pact.conditions {
                values[condition.id] = condition.inputType == .boolean ? 0 : condition.targetValue
            }
        }
    }

    private var preparedValues: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: pact.conditions.map { condition in
            (condition.id, values[condition.id] ?? (condition.inputType == .boolean ? 0 : condition.targetValue))
        })
    }

    private var participantStatusSymbol: String {
        if PactEvaluator.dayPassed(pact: pact, checkIn: store.checkIn(for: pact)) {
            "checkmark.circle.fill"
        } else {
            "clock.badge.exclamationmark.fill"
        }
    }

    private var participantStatusColor: Color {
        PactEvaluator.dayPassed(pact: pact, checkIn: store.checkIn(for: pact)) ? DefyColor.green : DefyColor.coral
    }
}

struct CheckInForm: View {
    let pact: Pact
    @Binding var values: [UUID: Int]
    @Binding var note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Today Check-in", systemImage: "checklist.checked")
                .font(.headline)
            ForEach(pact.conditions) { condition in
                if condition.inputType == .boolean {
                    Toggle(condition.title, isOn: Binding(
                        get: { values[condition.id, default: 0] == 1 },
                        set: { values[condition.id] = $0 ? 1 : 0 }
                    ))
                } else {
                    Stepper("\(condition.title): \(values[condition.id, default: condition.targetValue])", value: Binding(
                        get: { values[condition.id, default: condition.targetValue] },
                        set: { values[condition.id] = $0 }
                    ), in: 0...1000)
                }
            }
            TextField("Optional note", text: $note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
        }
        .padding()
        .defyGlass(cornerRadius: 24, interactive: true)
    }
}

struct FriendsView: View {
    @EnvironmentObject private var store: DefyStore
    @State private var handle = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Add friend") {
                    HStack {
                        TextField("@handle", text: $handle)
                            .textInputAutocapitalization(.never)
                        Button("Add") {
                            store.sendFriendRequest(handle: handle)
                            handle = ""
                        }
                        .disabled(handle.isEmpty)
                    }
                }

                Section("Network") {
                    ForEach(store.friends) { friend in
                        FriendRow(friend: friend) {
                            store.acceptFriend(friend)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Friends")
        }
    }
}

struct MetricsView: View {
    @EnvironmentObject private var store: DefyStore

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ScoreRing(score: store.integrity.score)
                    .frame(width: 220, height: 220)
                    .padding(.top, 20)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricPill(title: "Completed units", value: "\(store.integrity.completedUnits)", color: DefyColor.green)
                    MetricPill(title: "Expected units", value: "\(store.integrity.expectedUnits)", color: DefyColor.cyan)
                    MetricPill(title: "Active pacts", value: "\(store.integrity.activePacts)", color: DefyColor.violet)
                    MetricPill(title: "Missed days", value: "\(store.integrity.missedDays)", color: DefyColor.coral)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Score formula")
                        .font(.headline)
                    Text("Integrity Score = completed required daily units divided by expected required daily units. Proactive pact days count as complete unless you report a violation.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .defyGlass(cornerRadius: 24)
            }
            .padding()
        }
        .navigationTitle("Metrics")
    }
}

struct ProfileView: View {
    @EnvironmentObject private var store: DefyStore
    @State private var activeSheet: ProfileSheet?

    enum ProfileSheet: Identifiable {
        case edit
        case settings

        var id: String {
            switch self {
            case .edit: "edit"
            case .settings: "settings"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let user = store.currentUser {
                        ProfileHeaderView(user: user, snapshot: store.profileSnapshot, avatarData: store.localAvatarData) {
                            activeSheet = .edit
                        }

                        ProfileStatsGrid(snapshot: store.profileSnapshot)
                        CurrentCommitmentsView(pacts: store.todaysPacts) { pact in
                            store.checkIn(for: pact)
                        }
                        RecentAccountabilityView(activity: store.profileSnapshot.recentActivity)
                        FriendVisibleSummaryView(user: user, snapshot: store.profileSnapshot)
                    }
                }
                .padding()
            }
            .navigationTitle("Profile")
            .toolbar {
                Button {
                    activeSheet = .settings
                } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .edit:
                    EditProfileSheet()
                case .settings:
                    ProfileSettingsSheet()
                }
            }
        }
    }
}

struct ProfileHeaderView: View {
    let user: UserProfile
    let snapshot: ProfileSnapshot
    let avatarData: Data?
    var edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                ProfileAvatar(user: user, avatarData: avatarData, size: 92)
                Spacer()
                ScoreRing(score: snapshot.integrityScore, lineWidth: 8)
                    .frame(width: 118, height: 118)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(user.displayName)
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                    .foregroundStyle(DefyColor.ink)
                Text(user.handle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color(hex: user.accentColorHex))
                Text(user.bio.isEmpty ? "No bio yet." : user.bio)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: edit) {
                Label("Edit profile", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: user.accentColorHex))
        }
        .padding()
        .background(Color(hex: user.accentColorHex).opacity(0.16), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .defyGlass(cornerRadius: 30, interactive: true)
        .cardShadow()
    }
}

struct ProfileStatsGrid: View {
    let snapshot: ProfileSnapshot

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricPill(title: "Active pacts", value: "\(snapshot.activePactCount)", color: DefyColor.violet)
            MetricPill(title: "Completed", value: "\(snapshot.completedUnits)", color: DefyColor.green)
            MetricPill(title: "Missed days", value: "\(snapshot.missedDays)", color: DefyColor.coral)
            MetricPill(title: "Completion", value: "\(Int((snapshot.completionRate * 100).rounded()))%", color: DefyColor.cyan)
            MetricPill(title: "Current streak", value: "\(snapshot.currentStreak)d", color: DefyColor.citron)
            MetricPill(title: "Best streak", value: "\(snapshot.bestStreak)d", color: DefyColor.green)
        }
    }
}

struct CurrentCommitmentsView: View {
    let pacts: [Pact]
    let checkIn: (Pact) -> CheckIn?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current commitments")
                .font(.title3.weight(.black))
            if pacts.isEmpty {
                Text("No active commitments today.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(pacts.prefix(4)) { pact in
                    HStack(spacing: 12) {
                        Image(systemName: pact.core.symbol)
                            .foregroundStyle(pact.core == .reactive ? DefyColor.violet : DefyColor.coral)
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.65), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pact.title)
                                .font(.headline)
                            Text(pact.core.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(PactEvaluator.dayPassed(pact: pact, checkIn: checkIn(pact)) ? "Held" : "Open")
                            .font(.caption.weight(.black))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(statusColor(for: pact).opacity(0.18), in: Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .defyGlass(cornerRadius: 24)
    }

    private func statusColor(for pact: Pact) -> Color {
        PactEvaluator.dayPassed(pact: pact, checkIn: checkIn(pact)) ? DefyColor.green : DefyColor.coral
    }
}

struct RecentAccountabilityView: View {
    let activity: [ProfileActivityItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent accountability")
                .font(.title3.weight(.black))
            if activity.isEmpty {
                Text("Check-ins and violations will appear here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activity) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.symbol)
                            .foregroundStyle(item.isPositive ? DefyColor.green : DefyColor.coral)
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.65), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.headline)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.date, style: .date)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .defyGlass(cornerRadius: 24)
    }
}

struct FriendVisibleSummaryView: View {
    let user: UserProfile
    let snapshot: ProfileSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Friend-visible summary", systemImage: "eye.fill")
                .font(.title3.weight(.black))
            HStack(spacing: 12) {
                ProfileAvatar(user: user, avatarData: nil, size: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text(user.displayName)
                        .font(.headline)
                    Text("\(Int((snapshot.integrityScore * 100).rounded()))% Integrity · \(snapshot.activePactCount) active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text("Friends can see identity, bio, avatar, Integrity Score, active pact count, and recent accountability activity. Private pact descriptions stay inside participant views.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .defyGlass(cornerRadius: 24)
    }
}

struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DefyStore
    @State private var name = ""
    @State private var handle = ""
    @State private var bio = ""
    @State private var accentColorHex = "#ff564d"
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var handleError: String?

    private let accentOptions = ["#ff564d", "#38c7eb", "#795ff0", "#d1f23f", "#3dbc61"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Avatar") {
                    HStack {
                        if let user = store.currentUser {
                            ProfileAvatar(user: user, avatarData: store.localAvatarData, size: 72)
                        }
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("Choose photo", systemImage: "photo.on.rectangle.angled")
                        }
                    }
                }

                Section("Identity") {
                    TextField("Display name", text: $name)
                    TextField("@handle", text: $handle)
                        .textInputAutocapitalization(.never)
                    if let handleError {
                        Text(handleError)
                            .font(.caption)
                            .foregroundStyle(DefyColor.coral)
                    }
                    TextField("Bio", text: $bio, axis: .vertical)
                }

                Section("Accent") {
                    HStack {
                        ForEach(accentOptions, id: \.self) { hex in
                            Button {
                                accentColorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if accentColorHex == hex {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.black))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .task(id: selectedPhoto) {
                await uploadSelectedPhoto()
            }
            .onAppear {
                name = store.currentUser?.displayName ?? ""
                handle = store.currentUser?.handle ?? ""
                bio = store.currentUser?.bio ?? ""
                accentColorHex = store.currentUser?.accentColorHex ?? "#ff564d"
            }
        }
    }

    private func save() {
        guard let normalizedHandle = ProfileHandleValidator.normalized(handle) else {
            handleError = "Use lowercase letters, numbers, underscores, and no spaces."
            return
        }

        store.updateProfile(name: name, handle: normalizedHandle, bio: bio, accentColorHex: accentColorHex)
        dismiss()
    }

    private func uploadSelectedPhoto() async {
        guard let selectedPhoto,
              let data = try? await selectedPhoto.loadTransferable(type: Data.self) else {
            return
        }
        _ = try? await store.uploadAvatarImage(data)
    }
}

struct ProfileSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DefyStore
    @State private var permissionStatus = "Checking"
    @State private var defaultReminder = Calendar.current.date(from: DateComponents(hour: 20, minute: 0)) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Notifications") {
                    LabeledContent("Permission", value: permissionStatus)
                    DatePicker("Default reminder", selection: $defaultReminder, displayedComponents: .hourAndMinute)
                }

                Section("Privacy") {
                    Text("Accepted friends can see your name, handle, bio, avatar, Integrity Score, active pact count, and recent accountability activity.")
                    Text("Private pact descriptions and check-in notes stay visible only to pact participants.")
                        .foregroundStyle(.secondary)
                }

                Section("Backend") {
                    LabeledContent("Supabase", value: store.isSupabaseConfigured ? "Configured" : "Demo mode")
                }

                Section("Account") {
                    Button(role: .destructive) {
                        store.signOut()
                        dismiss()
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                permissionStatus = await store.notificationPermissionStatusText()
            }
        }
    }
}

struct ProfileAvatar: View {
    let user: UserProfile
    let avatarData: Data?
    var size: CGFloat

    var body: some View {
        Group {
            if let avatarData, let image = UIImage(data: avatarData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let avatarURL = user.avatarURL, avatarURL.scheme != "defy-local-avatar" {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.70), lineWidth: 3))
        .shadow(color: Color(hex: user.accentColorHex).opacity(0.28), radius: 16, x: 0, y: 10)
        .accessibilityLabel("\(user.displayName) avatar")
    }

    private var fallback: some View {
        Image(systemName: user.avatarSymbol)
            .font(.system(size: size * 0.42, weight: .black))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: user.accentColorHex), in: Circle())
    }
}

struct HeaderBlock: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.black))
                .foregroundStyle(DefyColor.coral)
            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .foregroundStyle(DefyColor.ink)
            Text(subtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PactTodayCard: View {
    let pact: Pact
    let checkIn: CheckIn?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(pact.core.title, systemImage: pact.core.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(pact.core == .reactive ? DefyColor.violet : DefyColor.coral)
                Spacer()
                Text(PactEvaluator.dayPassed(pact: pact, checkIn: checkIn) ? "Held" : "Open")
                    .font(.caption.weight(.black))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusColor.opacity(0.18), in: Capsule())
            }
            Text(pact.title)
                .font(.title2.weight(.black))
                .foregroundStyle(DefyColor.ink)
            Text(pact.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                ForEach(pact.participants.prefix(4)) { participant in
                    Avatar(symbol: participant.profile.avatarSymbol, color: participant.isOwner ? DefyColor.coral : DefyColor.cyan, size: 34)
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(DefyColor.ink)
            }
        }
        .padding()
        .defyGlass(cornerRadius: 28, interactive: true)
        .cardShadow()
    }

    private var statusColor: Color {
        PactEvaluator.dayPassed(pact: pact, checkIn: checkIn) ? DefyColor.green : DefyColor.coral
    }
}

struct PactRow: View {
    let pact: Pact
    let checkIn: CheckIn?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: pact.core.symbol)
                .foregroundStyle(pact.core == .reactive ? DefyColor.violet : DefyColor.coral)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.6), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(pact.title)
                    .font(.headline)
                Text(pact.dateRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: PactEvaluator.dayPassed(pact: pact, checkIn: checkIn) ? "checkmark.circle.fill" : "clock.fill")
                .foregroundStyle(PactEvaluator.dayPassed(pact: pact, checkIn: checkIn) ? DefyColor.green : DefyColor.coral)
        }
    }
}

struct PactHero: View {
    let pact: Pact

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(pact.core.title, systemImage: pact.core.symbol)
                .font(.caption.weight(.black))
                .foregroundStyle(pact.core == .reactive ? DefyColor.violet : DefyColor.coral)
            Text(pact.title)
                .font(.system(.largeTitle, design: .rounded, weight: .black))
            Text(pact.description)
                .font(.body)
                .foregroundStyle(.secondary)
            Text(pact.dateRangeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(DefyColor.citron.opacity(0.18), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .defyGlass(cornerRadius: 28)
    }
}

struct FriendRow: View {
    let friend: DefyFriend
    var accept: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Avatar(symbol: friend.profile.avatarSymbol, color: friend.status == .accepted ? DefyColor.green : DefyColor.coral)
            VStack(alignment: .leading) {
                Text(friend.profile.displayName)
                    .font(.headline)
                Text(friend.profile.handle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch friend.status {
            case .accepted:
                Text("\(Int(friend.profile.integrityScore * 100))%")
                    .font(.headline.weight(.black))
                    .foregroundStyle(DefyColor.green)
            case .pending:
                if friend.pendingDirection == .incoming {
                    Button("Accept", action: accept)
                } else {
                    Text("Pending")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            case .blocked:
                Text("Blocked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct Avatar: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .black))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
            .accessibilityHidden(true)
    }
}

#Preview {
    ContentView()
        .environmentObject(DefyStore())
}
