import PhotosUI
import SwiftUI

enum KeptTab: String, CaseIterable, Identifiable {
    case today
    case pacts
    case friends
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .pacts: "Pacts"
        case .friends: "Friends"
        case .profile: "Profile"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max.fill"
        case .pacts: "seal.fill"
        case .friends: "person.2.fill"
        case .profile: "person.crop.circle.fill"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: KeptStore
    @State private var tab: KeptTab = .today

    var body: some View {
        ZStack {
            AppBackground()
            if store.currentUser == nil {
                AuthView()
            } else {
                TabView(selection: $tab) {
                    TodayView()
                        .tabItem { Label(KeptTab.today.title, systemImage: KeptTab.today.symbol) }
                        .tag(KeptTab.today)
                    PactsView()
                        .tabItem { Label(KeptTab.pacts.title, systemImage: KeptTab.pacts.symbol) }
                        .tag(KeptTab.pacts)
                    FriendsView()
                        .tabItem { Label(KeptTab.friends.title, systemImage: KeptTab.friends.symbol) }
                        .tag(KeptTab.friends)
                    ProfileView()
                        .tabItem { Label(KeptTab.profile.title, systemImage: KeptTab.profile.symbol) }
                        .tag(KeptTab.profile)
                }
                .tint(KeptColor.ink)
            }
        }
        .preferredColorScheme(.light)
        .task {
            await store.restoreLiveSessionIfPossible()
            store.startLiveSync()
        }
        .onOpenURL { url in
            Task {
                await store.handleAuthCallback(url)
            }
        }
    }
}

struct AuthView: View {
    @EnvironmentObject private var store: KeptStore
    @State private var email = ""

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "bolt.badge.checkmark.fill")
                    .font(.system(size: 54, weight: .black))
                    .foregroundStyle(KeptColor.ink)
                Text("Kept")
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .foregroundStyle(KeptColor.ink)
                Text("Give your word. Make it measurable.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 20)

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.black, lineWidth: 2)
                    )

                Button {
                    store.signInWithEmail(email)
                } label: {
                    Label("Send magic link", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(Color.black)
                .disabled(email.isEmpty || store.isAuthBusy)

                if store.isAuthBusy {
                    ProgressView()
                        .tint(Color.black)
                }
            }
            .padding(18)
            .keptGlass(cornerRadius: 28, interactive: true)

            Text(statusText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
    }

    private var statusText: String {
        if !store.authStatusMessage.isEmpty {
            return store.authStatusMessage
        }
        return store.isSupabaseConfigured
            ? "Live Supabase magic-link auth is enabled."
            : "Demo mode: add SUPABASE_URL and SUPABASE_ANON_KEY to connect the live backend."
    }
}

struct TodayView: View {
    @EnvironmentObject private var store: KeptStore

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
                        MetricPill(title: "Integrity", value: "\(Int(store.integrity.score * 100))%", color: KeptColor.green)
                        MetricPill(title: "Missed days", value: "\(store.integrity.missedDays)", color: KeptColor.coral)
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
            .navigationTitle("Kept")
        }
    }
}

struct PactsView: View {
    @EnvironmentObject private var store: KeptStore
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
    @EnvironmentObject private var store: KeptStore
    @State private var draft = PactDraft()
    @State private var selectedFriendIDs = Set<UUID>()

    private let iconOptions = [
        "bolt.fill", "drop.fill", "flame.fill", "brain.headset",
        "leaf.fill", "target", "bubbles.and.sparkles.fill",
        "moon.fill", "book.fill", "heart.fill", "hourglass"
    ]
    private let colorOptions = ["#ff564d", "#38c7eb", "#795ff0", "#d1f23f", "#3dbc61"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Pact title", text: $draft.title)
                    TextField("Description", text: $draft.description, axis: .vertical)
                }

                Section("Style") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose Icon")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(iconOptions, id: \.self) { symbol in
                                    Button {
                                        draft.iconSymbol = symbol
                                    } label: {
                                        Image(systemName: symbol)
                                            .font(.title2)
                                            .frame(width: 44, height: 44)
                                            .background(draft.iconSymbol == symbol ? Color.black : Color.white)
                                            .foregroundStyle(draft.iconSymbol == symbol ? Color.white : Color.black)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.black, lineWidth: 1.5)
                                            )
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose Theme Color")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            ForEach(colorOptions, id: \.self) { hex in
                                Button {
                                    draft.accentColorHex = hex
                                } label: {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 34, height: 34)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.black, lineWidth: draft.accentColorHex == hex ? 2.5 : 1)
                                        )
                                        .overlay {
                                            if draft.accentColorHex == hex {
                                                Image(systemName: "checkmark")
                                                    .font(.caption.weight(.black))
                                                    .foregroundStyle(hex == "#d1f23f" ? Color.black : Color.white)
                                            }
                                        }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Dates") {
                    DatePicker("Start", selection: $draft.startDate, in: ...draft.finishDate, displayedComponents: .date)
                    DatePicker("Finish", selection: $draft.finishDate, in: draft.startDate..., displayedComponents: .date)
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

                Section("Daily Conditions") {
                    ForEach($draft.conditions) { $condition in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                TextField("Condition name (e.g. Cold shower)", text: $condition.title)
                                Button(role: .destructive) {
                                    if draft.conditions.count > 1 {
                                        draft.conditions.removeAll { $0.id == condition.id }
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .disabled(draft.conditions.count <= 1)
                            }
                            
                            Picker("Type", selection: $condition.type) {
                                ForEach(ConditionType.allCases) { type in
                                    Text(type.title).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)
                            
                            Picker("Input Type", selection: $condition.inputType) {
                                ForEach(PactInputType.allCases) { input in
                                    Text(input.title).tag(input)
                                }
                            }
                            .pickerStyle(.segmented)
                            
                            if condition.inputType == .integer {
                                Stepper(value: $condition.targetValue, in: 0...1000) {
                                    if condition.type == .todo {
                                        Text("Target completion: \(condition.targetValue)")
                                    } else {
                                        Text("Max allowed slips: \(condition.targetValue)")
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    Button {
                        draft.conditions.append(PactCondition(
                            id: UUID(),
                            title: "",
                            type: .todo,
                            inputType: .boolean,
                            comparison: .equals,
                            targetValue: 1,
                            isRequired: true
                        ))
                    } label: {
                        Label("Add Condition", systemImage: "plus")
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
                        if draft.finishDate < draft.startDate {
                            draft.finishDate = draft.startDate
                        }
                        store.createPact(draft: draft)
                        dismiss()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.finishDate < draft.startDate)
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
    @EnvironmentObject private var store: KeptStore
    let pact: Pact
    @State private var values: [UUID: Int] = [:]
    @State private var note = ""
    @State private var chatText = ""
    @State private var selectedTab: PactDetailTab = .checkIn
    @State private var showStamp = false
    @State private var stampTriggered = false
    @State private var itemPulse: UUID? = nil
    @State private var showCompletion = false
    @State private var showLockConfirmation = false

    // War Room View States
    @State private var warRoomViewMode: WarRoomMode = .overview
    @State private var expandedParticipantID: UUID? = nil
    @State private var selectedConditionID: UUID? = nil
    @State private var selectedDayOffset: Int? = nil
    @State private var selectedCalendarUserID: UUID? = nil

    private let systemSenderID = UUID(uuidString: "00000000-0000-4000-8000-000000000000") ?? UUID()

    enum PactDetailTab: String, CaseIterable, Identifiable {
        case checkIn = "Check-in"
        case warRoom = "War Room"
        case chat = "Chat"

        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .checkIn: "checkmark.seal.fill"
            case .warRoom: "person.2.badge.gearshape.fill"
            case .chat: "bubble.left.and.bubble.right.fill"
            }
        }
    }

    enum WarRoomMode: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case insights = "Insights"
        case analytics = "Analytics"

        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 0) {
                    pactHeroBanner
                    tabSwitcher
                        .padding(.top, 12)

                    // Dynamic Content
                    switch selectedTab {
                    case .checkIn:
                        checkInTab
                            .padding(.top, 8)
                    case .warRoom:
                        warRoomTab
                            .padding(.top, 8)
                    case .chat:
                        EmptyView() // Chat has its own layout
                    }
                }
            }
            .opacity(selectedTab == .chat ? 0 : 1)

            if selectedTab == .chat {
                chatTab
            }

            // Pact Completion Overlay
            if showCompletion {
                pactCompletionOverlay
            }
        }
        .background(AppBackground())
        .alert("Lock Broken Pact?", isPresented: $showLockConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Lock Anyway", role: .destructive) {
                commitCheckIn()
            }
        } message: {
            Text("You have unmet daily conditions. Once locked, today will be marked as PACT BROKEN.")
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(selectedTab == .chat ? "Chat" : pact.title)
        .navigationBarBackButtonHidden(selectedTab == .chat)
        .toolbar {
            if selectedTab == .chat {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = .checkIn
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .bold))
                            Text("Pact")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundStyle(KeptColor.ink)
                    }
                }
            }
        }
        .onAppear {
            setupDefaultValues()
            checkForCompletion()
        }
    }

    // MARK: - Hero Banner

    private var pactHeroBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Icon + Title + Progress Badge Row
            HStack(spacing: 12) {
                Image(systemName: pact.iconSymbol)
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color(hex: pact.accentColorHex))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.black, lineWidth: 1.5)
                    )
                    .shadow(color: Color.black, radius: 0, x: 2, y: 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pact.title)
                        .font(.system(.headline, design: .rounded, weight: .black))
                        .foregroundStyle(KeptColor.ink)
                    if !pact.description.isEmpty {
                        Text(pact.description)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
                
                let progress = store.pactProgress(for: pact, userID: store.currentUser?.id ?? UUID())
                if progress.total > 0 {
                    let percent = Int(Double(progress.completed) / Double(progress.total) * 100)
                    Text("\(percent)%")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: pact.accentColorHex).opacity(0.15))
                        .foregroundStyle(Color.black)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.black, lineWidth: 1.5)
                        )
                }
            }

            // Compact Progress Bar
            let progress = store.pactProgress(for: pact, userID: store.currentUser?.id ?? UUID())
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.black.opacity(0.06))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: pact.accentColorHex))
                        .frame(width: progress.total > 0 ? geo.size.width * CGFloat(progress.completed) / CGFloat(progress.total) : 0, height: 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.black, lineWidth: 0.5)
                        )
                }
            }
            .frame(height: 5)
            
            // Date + Participants Row
            HStack {
                Label(pact.dateRangeText, systemImage: "calendar")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: -6) {
                    ForEach(pact.participants.prefix(4)) { participant in
                        Avatar(symbol: participant.profile.avatarSymbol,
                               color: Color(hex: participant.profile.accentColorHex),
                               size: 22)
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.black, lineWidth: 1.5)
        )
        .shadow(color: Color.black, radius: 0, x: 3, y: 3)
        .padding(.horizontal)
        .padding(.top, 6)
    }

    // MARK: - Tab Switcher (Compact Capsules)

    private var tabSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(PactDetailTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.caption.weight(.black))
                        Text(tab.rawValue)
                            .font(.caption.weight(.black))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedTab == tab ? Color.black : Color.white)
                    .foregroundStyle(selectedTab == tab ? Color.white : Color.black)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.black, lineWidth: 1.5)
                    )
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Setup

    private func setupDefaultValues() {
        for condition in pact.conditions {
            if condition.type == .todo {
                values[condition.id] = condition.inputType == .boolean ? 0 : 0
            } else {
                values[condition.id] = 0
            }
        }
        if let myCheckIn = store.checkIn(for: pact) {
            note = myCheckIn.note
            for val in myCheckIn.values {
                values[val.conditionID] = val.integerValue
            }
        }
        if selectedCalendarUserID == nil {
            selectedCalendarUserID = store.currentUser?.id
        }
    }

    private func checkForCompletion() {
        guard let userID = store.currentUser?.id else { return }
        if pact.status == .active,
           PactEvaluator.pactFullyCompleted(pact: pact, checkIns: store.checkIns, userID: userID) {
            let totalDays = PactEvaluator.daysCompletedCount(pact: pact, checkIns: store.checkIns, userID: userID).total
            if totalDays > 3 { // Only show celebration for multi-day pacts
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showCompletion = true
                }
            }
        }
    }

    // MARK: - Check-In Tab

    private var checkInTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let myCheckIn = store.checkIn(for: pact) {
                // ── LOCKED STATE ──
                lockedCheckInView(myCheckIn: myCheckIn)
            } else {
                // ── ACTIVE INPUT FORM ──
                activeCheckInForm
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }

    private func lockedCheckInView(myCheckIn: CheckIn) -> some View {
        let percent = PactEvaluator.dayKeepPercentage(pact: pact, checkIn: myCheckIn)
        let status = PactEvaluator.statusTextAndColor(for: percent)

        return VStack(spacing: 16) {
            // Stamp
            HStack {
                Spacer()
                Text(status.text)
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(status.color)
                    .foregroundStyle(Color.black)
                    .overlay(
                        Rectangle()
                            .stroke(Color.black, lineWidth: 2.5)
                    )
                    .stampSlam(isActive: stampTriggered)
                    .confettiBurst(isActive: percent >= 0.5 && stampTriggered)
                    .shadow(color: Color.black, radius: 0, x: 3, y: 3)
                Spacer()
            }
            .padding(.vertical, 6)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    stampTriggered = true
                    if percent == 1.0 {
                        HapticFeedback.success()
                    } else if percent == 0.0 {
                        HapticFeedback.warning()
                    } else {
                        HapticFeedback.impact()
                    }
                }
            }

            // Condition Summary
            VStack(alignment: .leading, spacing: 8) {
                ForEach(pact.conditions) { condition in
                    let cValue = myCheckIn.values.first { $0.conditionID == condition.id }?.integerValue
                    let satisfied = condition.isSatisfied(value: cValue)

                    HStack(spacing: 10) {
                        Image(systemName: satisfied ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(satisfied ? KeptColor.green : KeptColor.coral)
                            .font(.body.weight(.bold))
                        Text(condition.title)
                            .font(.subheadline.weight(.bold))
                        Spacer()
                        if condition.inputType == .integer {
                            Text("\(cValue ?? 0)")
                                .font(.caption.weight(.black))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(0.06))
                                .cornerRadius(6)
                        }
                    }
                }
            }
            .padding(14)
            .background(Color.white)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.black, lineWidth: 1.5)
            )

            // Note
            if !myCheckIn.note.isEmpty {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: 3)
                    Text(myCheckIn.note)
                        .font(.subheadline.italic())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            // Unlock & Edit Button
            Button {
                HapticFeedback.impact()
                withAnimation(.easeInOut(duration: 0.2)) {
                    showStamp = false
                    stampTriggered = false
                    store.deleteCheckIn(for: pact)
                }
            } label: {
                Label("Unlock & Edit check-in", systemImage: "lock.open.fill")
                    .font(.subheadline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .foregroundStyle(Color.black)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.black, lineWidth: 1.5)
                    )
                    .shadow(color: Color.black, radius: 0, x: 2, y: 2)
            }
            .padding(.top, 8)
        }
        .padding()
        .keptGlass(cornerRadius: 24)
    }

    private func commitCheckIn() {
        store.recordCheckIn(pact: pact, values: values, note: note)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            stampTriggered = true
            let isHeld = PactEvaluator.dayPassed(pact: pact, checkIn: store.checkIn(for: pact))
            if isHeld {
                HapticFeedback.success()
            } else {
                HapticFeedback.warning()
            }
        }
    }

    private var activeCheckInForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Lock Today's Accountability", systemImage: "pencil.and.outline")
                .font(.headline.weight(.black))
                .foregroundStyle(KeptColor.ink)

            let todoConditions = pact.conditions.filter { $0.type == .todo }
            let avoidConditions = pact.conditions.filter { $0.type == .avoid }

            if !todoConditions.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .font(.system(size: 10, weight: .black))
                    Text("TO-DO")
                        .font(.system(size: 10, weight: .black))
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(KeptColor.green)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.black, lineWidth: 1.2)
                )
                .shadow(color: Color.black, radius: 0, x: 2, y: 2)
                .padding(.top, 2)

                ForEach(todoConditions) { condition in
                    conditionInputCard(condition: condition, accentColor: KeptColor.green)
                }
            }

            if !avoidConditions.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 10, weight: .black))
                    Text("AVOID")
                        .font(.system(size: 10, weight: .black))
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(KeptColor.coral)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.black, lineWidth: 1.2)
                )
                .shadow(color: Color.black, radius: 0, x: 2, y: 2)
                .padding(.top, 4)

                ForEach(avoidConditions) { condition in
                    conditionInputCard(condition: condition, accentColor: KeptColor.coral)
                }
            }

            TextField("Add note...", text: $note)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color.white)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.black, lineWidth: 1.5)
                )

            Button {
                HapticFeedback.impact()

                // Pre-evaluate if the check-in is kept or broken
                let mockCheckIn = CheckIn(
                    id: UUID(),
                    pactID: pact.id,
                    userID: store.currentUser?.id ?? UUID(),
                    day: Date(),
                    note: note,
                    didReportViolation: false,
                    values: pact.conditions.map { cond in
                        CheckInValue(id: UUID(), conditionID: cond.id, integerValue: values[cond.id, default: 0])
                    }
                )
                let isHeld = PactEvaluator.dayPassed(pact: pact, checkIn: mockCheckIn)

                if !isHeld {
                    showLockConfirmation = true
                } else {
                    commitCheckIn()
                }
            } label: {
                Label("Lock check-in", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.black)
                    .foregroundStyle(Color.white)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.black, lineWidth: 2)
                    )
            }
        }
        .padding()
        .keptGlass(cornerRadius: 24)
    }

    private func conditionInputCard(condition: PactCondition, accentColor: Color) -> some View {
        let isActive = (itemPulse == condition.id)
        let currentValue = values[condition.id, default: 0]
        let isSatisfied = condition.isSatisfied(value: currentValue)

        let cardBg: Color
        let stripeColor: Color
        let iconName: String
        let titleColor: Color

        if condition.type == .todo {
            cardBg = isSatisfied ? KeptColor.green.opacity(0.08) : Color.white
            stripeColor = isSatisfied ? KeptColor.green : Color.black.opacity(0.2)
            iconName = isSatisfied ? "checkmark.circle.fill" : "circle"
            titleColor = isSatisfied ? .secondary : Color.black
        } else {
            // Avoid type
            cardBg = isSatisfied ? KeptColor.green.opacity(0.04) : KeptColor.coral.opacity(0.08)
            stripeColor = isSatisfied ? KeptColor.green : KeptColor.coral
            iconName = isSatisfied ? "shield.fill" : "exclamationmark.triangle.fill"
            titleColor = isSatisfied ? Color.black : KeptColor.coral
        }

        return HStack(spacing: 0) {
            // Left Accent Stripe
            Rectangle()
                .fill(stripeColor)
                .frame(width: 8)

            HStack(spacing: 12) {
                if condition.type == .todo {
                    // ── TO-DO TYPE ──
                    Image(systemName: iconName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(isSatisfied ? KeptColor.green : Color.black.opacity(0.3))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(condition.title)
                            .font(.subheadline.weight(.bold))
                            .strikethrough(isSatisfied)
                            .foregroundStyle(titleColor)
                        if condition.inputType == .integer {
                            Text("Target: \(condition.targetValue)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if condition.inputType == .boolean {
                        Button {
                            values[condition.id] = isSatisfied ? 0 : 1
                            itemPulse = condition.id
                            HapticFeedback.impact()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                itemPulse = nil
                            }
                        } label: {
                            Text("Done")
                                .font(.caption.weight(.black))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isSatisfied ? KeptColor.green : Color.white)
                                .foregroundStyle(Color.black)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.black, lineWidth: 1.5))
                        }
                    } else {
                        // Integer stepper
                        stepperView(for: condition)
                    }
                } else {
                    // ── AVOID TYPE ──
                    Image(systemName: iconName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(stripeColor)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(condition.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(titleColor)
                            
                            // Visual badge indicating current state
                            Text(isSatisfied ? "CLEAN" : "SLIPPED")
                                .font(.system(size: 8, weight: .black))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2.5)
                                .background(isSatisfied ? KeptColor.green.opacity(0.2) : KeptColor.coral.opacity(0.2))
                                .foregroundStyle(stripeColor)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        
                        if condition.inputType == .integer {
                            Text("Max slips: \(condition.targetValue)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if condition.inputType == .boolean {
                        Button {
                            // Toggle: if currently satisfied (Clean), set value to 1 (Slipped). If currently not satisfied (Slipped), set value to 0 (Clean).
                            values[condition.id] = isSatisfied ? 1 : 0
                            itemPulse = condition.id
                            HapticFeedback.impact()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                itemPulse = nil
                            }
                        } label: {
                            Text(isSatisfied ? "Slipped" : "Undo")
                                .font(.caption.weight(.black))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isSatisfied ? Color.white : KeptColor.coral)
                                .foregroundStyle(isSatisfied ? Color.black : Color.white)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.black, lineWidth: 1.5))
                        }
                    } else {
                        // Integer stepper
                        stepperView(for: condition)
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
        }
        .background(cardBg)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .pulseGlow(isActive: isActive, color: stripeColor)
    }

    @ViewBuilder
    private func stepperView(for condition: PactCondition) -> some View {
        let currentValue = values[condition.id, default: 0]
        let isSatisfied = condition.isSatisfied(value: currentValue)

        HStack(spacing: 6) {
            Button {
                let current = values[condition.id, default: 0]
                if current > 0 {
                    values[condition.id] = current - 1
                    HapticFeedback.impact()
                }
            } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.black))
                    .frame(width: 28, height: 28)
                    .background(Color.white)
                    .foregroundStyle(Color.black)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
            }

            Text("\(currentValue)")
                .font(.body.weight(.black))
                .frame(width: 36)
                .foregroundStyle(condition.type == .avoid && !isSatisfied ? KeptColor.coral : Color.black)

            Button {
                let current = values[condition.id, default: 0]
                values[condition.id] = current + 1
                HapticFeedback.impact()
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.black))
                    .frame(width: 28, height: 28)
                    .background(Color.black)
                    .foregroundStyle(Color.white)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
            }
        }
    }

    // MARK: - War Room Tab

    private struct CalendarCell: Identifiable {
        let id = UUID()
        let date: Date?
        let index: Int?
    }

    private var warRoomTab: some View {
        let activeUserID = selectedCalendarUserID ?? store.currentUser?.id ?? UUID()
        
        return VStack(alignment: .leading, spacing: 18) {
            // Stats Summary Bar
            pactStatsBar

            // Member Standings
            VStack(alignment: .leading, spacing: 10) {
                Label("Member Standings", systemImage: "person.2.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .black))
                    .foregroundStyle(Color.black)
                
                VStack(spacing: 0) {
                    ForEach(Array(pact.participants.enumerated()), id: \.element.id) { index, participant in
                        participantRow(participant: participant)
                        
                        if index < pact.participants.count - 1 {
                            Divider()
                                .background(Color.black.opacity(0.1))
                                .padding(.horizontal, 12)
                        }
                    }
                }
                .background(Color.white)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.black, lineWidth: 1.5)
                )
            }

            // Consistency Heatmap (GitHub-style calendar)
            consistencyCalendarSection(for: activeUserID)

            // Weekly consistency trend bar chart
            weeklyTrendChartSection

            // Condition Health
            conditionHealthSection
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }

    private var pactStatsBar: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let finish = calendar.startOfDay(for: pact.finishDate)
        let daysRemaining = max(0, calendar.dateComponents([.day], from: today, to: finish).day ?? 0)
        let userProgress = store.pactProgress(for: pact, userID: store.currentUser?.id ?? UUID())
        let successRate = userProgress.total > 0 ? "\(Int(Double(userProgress.completed) / Double(userProgress.total) * 100))%" : "–"

        return HStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("\(daysRemaining)")
                    .font(.system(.title3, design: .rounded, weight: .black))
                    .foregroundStyle(KeptColor.ink)
                Text("Days left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            
            Divider()
                .background(Color.black.opacity(0.15))
                .frame(height: 30)
            
            VStack(spacing: 4) {
                Text("\(pact.participants.count)")
                    .font(.system(.title3, design: .rounded, weight: .black))
                    .foregroundStyle(KeptColor.ink)
                Text("Members")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            
            Divider()
                .background(Color.black.opacity(0.15))
                .frame(height: 30)
            
            VStack(spacing: 4) {
                Text(successRate)
                    .font(.system(.title3, design: .rounded, weight: .black))
                    .foregroundStyle(KeptColor.ink)
                Text("Success Rate")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black, lineWidth: 1.5)
        )
    }

    private func participantRow(participant: PactParticipant) -> some View {
        let pCheckIn = checkIn(for: participant)
        let isHeld = PactEvaluator.dayPassed(pact: pact, checkIn: pCheckIn)
        let hasReported = pCheckIn != nil
        let progress = store.pactProgress(for: pact, userID: participant.profile.id)
        
        let isSelected = (selectedCalendarUserID ?? store.currentUser?.id) == participant.profile.id

        let percent = pCheckIn != nil ? PactEvaluator.dayKeepPercentage(pact: pact, checkIn: pCheckIn) : (isHeld ? 1.0 : 0.0)
        let display = hasReported ? PactEvaluator.statusTextAndColor(for: percent) : (text: "Pending", color: Color.black)

        return Button {
            HapticFeedback.impact()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0)) {
                selectedCalendarUserID = participant.profile.id
                selectedDayOffset = nil
            }
        } label: {
            HStack(spacing: 12) {
                Avatar(symbol: participant.profile.avatarSymbol,
                       color: Color(hex: participant.profile.accentColorHex),
                       size: 36)
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(participant.profile.displayName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.black)
                        if participant.isOwner {
                            Text("OWNER")
                                .font(.system(size: 8, weight: .black))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.black)
                                .foregroundStyle(Color.white)
                                .cornerRadius(3)
                        }
                    }
                    
                    Text("\(progress.completed)/\(progress.total) held · \(progress.completed)d streak")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Non-binary status badge
                Text(hasReported ? display.text : "Pending")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(hasReported ? display.color.opacity(0.12) : Color.black.opacity(0.04))
                    .foregroundStyle(hasReported ? display.color : .secondary)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isSelected ? Color(hex: participant.profile.accentColorHex).opacity(0.08) : Color.clear)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.black, lineWidth: isSelected ? 1.5 : 0)
            )
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func generateCalendarCells(for userID: UUID) -> [CalendarCell] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: pact.startDate)
        let finish = calendar.startOfDay(for: pact.finishDate)
        guard start <= finish else { return [] }
        
        let weekday = calendar.component(.weekday, from: start)
        let firstWeekdayIndex = (weekday + 5) % 7 // Monday-first: 0 = Mon, 6 = Sun
        
        var cells: [CalendarCell] = []
        
        // Add placeholders
        for _ in 0..<firstWeekdayIndex {
            cells.append(CalendarCell(date: nil, index: nil))
        }
        
        // Add actual dates
        let dayCount = calendar.dateComponents([.day], from: start, to: finish).day ?? 0
        for offset in 0...dayCount {
            if let date = calendar.date(byAdding: .day, value: offset, to: start) {
                cells.append(CalendarCell(date: date, index: offset))
            }
        }
        
        return cells
    }

    private func consistencyCalendarSection(for userID: UUID) -> some View {
        let cells = generateCalendarCells(for: userID)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        let memberName = pact.participants.first { $0.profile.id == userID }?.profile.displayName ?? "User"
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("\(memberName)'s Consistency Grid", systemImage: "square.grid.3x3.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .black))
                    .foregroundStyle(Color.black)
                
                Spacer()
                
                Picker("Member", selection: $selectedCalendarUserID) {
                    ForEach(pact.participants) { participant in
                        Text(participant.profile.displayName).tag(participant.profile.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
                .accentColor(Color.black)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black, lineWidth: 1))
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 0) {
                    ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                        Text(day)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(Color.black.opacity(0.4))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 4)
                
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(cells) { cell in
                        calendarCellView(cell: cell, userID: userID, today: today, calendar: calendar)
                    }
                }
                
                // Legend
                HStack {
                    Spacer()
                    Text("Less")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.black.opacity(0.08))
                            .frame(width: 10, height: 10)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.black, lineWidth: 0.5))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(KeptColor.coral)
                            .frame(width: 10, height: 10)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.black, lineWidth: 0.5))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.orange)
                            .frame(width: 10, height: 10)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.black, lineWidth: 0.5))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 1.0, green: 0.8, blue: 0.0))
                            .frame(width: 10, height: 10)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.black, lineWidth: 0.5))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(KeptColor.citron)
                            .frame(width: 10, height: 10)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.black, lineWidth: 0.5))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(KeptColor.green)
                            .frame(width: 10, height: 10)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.black, lineWidth: 0.5))
                    }
                    
                    Text("More")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            .padding(14)
            .background(Color.white)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.black, lineWidth: 1.5)
            )
            
            // Show interactive day details
            if let index = selectedDayOffset {
                let start = calendar.startOfDay(for: pact.startDate)
                if let tappedDate = calendar.date(byAdding: .day, value: index, to: start) {
                    let checkIn = store.checkIns.first {
                        $0.pactID == pact.id
                            && $0.userID == userID
                            && calendar.isDate($0.day, inSameDayAs: tappedDate)
                    }
                    let passed = PactEvaluator.dayPassed(pact: pact, checkIn: checkIn, on: tappedDate)
                    let percent = checkIn != nil ? PactEvaluator.dayKeepPercentage(pact: pact, checkIn: checkIn) : (passed ? 1.0 : 0.0)
                    let display = PactEvaluator.statusTextAndColor(for: percent)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Details for \(tappedDate.formatted(.dateTime.month().day().year()))")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.black)
                            Spacer()
                            Text(display.text)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(display.color)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black, lineWidth: 1))
                        }
                        
                        if let checkIn {
                            if !checkIn.note.isEmpty {
                                Text("\"\(checkIn.note)\"")
                                    .font(.system(size: 12).italic())
                                    .foregroundStyle(.secondary)
                            }
                            
                            VStack(spacing: 6) {
                                ForEach(pact.conditions) { cond in
                                    let val = checkIn.values.first { $0.conditionID == cond.id }?.integerValue
                                    let satisfied = cond.isSatisfied(value: val)
                                    
                                    HStack {
                                        Image(systemName: satisfied ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundStyle(satisfied ? KeptColor.green : KeptColor.coral)
                                            .font(.system(size: 12))
                                        Text(cond.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Color.black)
                                        Spacer()
                                        if cond.inputType == .integer {
                                            Text("Value: \(val ?? 0) (Target: \(cond.targetValue))")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        } else {
                            Text(passed ? "All avoid conditions kept. No check-in was required." : "No check-in was recorded. This counts as a broken pact day.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        
                        Button {
                            withAnimation {
                                selectedDayOffset = nil
                            }
                        } label: {
                            Text("Close details")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(12)
                    .background(Color.black.opacity(0.02))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
                    .padding(.top, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func calendarCellView(cell: CalendarCell, userID: UUID, today: Date, calendar: Calendar) -> some View {
        if let date = cell.date, let index = cell.index {
            let checkIn = store.checkIns.first {
                $0.pactID == pact.id
                    && $0.userID == userID
                    && calendar.isDate($0.day, inSameDayAs: date)
            }
            
            let isFuture = date > today
            let passed = PactEvaluator.dayPassed(pact: pact, checkIn: checkIn, on: date)
            let percent = checkIn != nil ? PactEvaluator.dayKeepPercentage(pact: pact, checkIn: checkIn) : (passed ? 1.0 : 0.0)
            let display = PactEvaluator.statusTextAndColor(for: percent)
            
            let cellColor: Color = isFuture ? Color.black.opacity(0.02) : (checkIn == nil ? (passed ? KeptColor.green.opacity(0.15) : Color.black.opacity(0.08)) : display.color)
            let isSelected = selectedDayOffset == index
            let strokeWidth: CGFloat = isSelected ? 2 : (isFuture ? 0.5 : 1)
            let strokeOpacity: Double = isFuture ? 0.3 : 1
            
            RoundedRectangle(cornerRadius: 4)
                .fill(cellColor)
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.black, lineWidth: strokeWidth)
                        .opacity(strokeOpacity)
                )
                .onTapGesture {
                    if !isFuture {
                        HapticFeedback.impact()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0)) {
                            if selectedDayOffset == index {
                                selectedDayOffset = nil
                            } else {
                                selectedDayOffset = index
                            }
                        }
                    }
                }
        } else {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
        }
    }

    private func last7DaysGroupCompliance() -> [(dayLabel: String, rate: Double)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var data: [(dayLabel: String, rate: Double)] = []
        
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        
        for offset in (-6)...0 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            guard day >= calendar.startOfDay(for: pact.startDate) && day <= calendar.startOfDay(for: pact.finishDate) else {
                continue
            }
            
            var totalPct = 0.0
            var count = 0
            for participant in pact.participants {
                let checkIn = store.checkIns.first {
                    $0.pactID == pact.id
                        && $0.userID == participant.profile.id
                        && calendar.isDate($0.day, inSameDayAs: day)
                }
                let passed = PactEvaluator.dayPassed(pact: pact, checkIn: checkIn, on: day)
                let percent = checkIn != nil ? PactEvaluator.dayKeepPercentage(pact: pact, checkIn: checkIn) : (passed ? 1.0 : 0.0)
                totalPct += percent
                count += 1
            }
            let avg = count > 0 ? (totalPct / Double(count)) : 0.0
            let label = formatter.string(from: day)
            data.append((dayLabel: label, rate: avg))
        }
        return data
    }

    private var weeklyTrendChartSection: some View {
        let data = last7DaysGroupCompliance()
        
        return VStack(alignment: .leading, spacing: 10) {
            Label("Group Consistency Trend", systemImage: "chart.bar.fill")
                .font(.system(.subheadline, design: .rounded, weight: .black))
                .foregroundStyle(Color.black)
                .padding(.top, 4)
            
            VStack(spacing: 12) {
                if data.isEmpty {
                    Text("No trend data available yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    HStack(alignment: .bottom, spacing: 12) {
                        ForEach(data, id: \.dayLabel) { item in
                            trendBarView(label: item.dayLabel, rate: item.rate)
                        }
                    }
                    .frame(height: 120)
                    .padding(.top, 8)
                }
            }
            .padding(14)
            .background(Color.white)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.black, lineWidth: 1.5)
            )
        }
    }

    @ViewBuilder
    private func trendBarView(label: String, rate: Double) -> some View {
        let percent = Int(round(rate * 100))
        let display = PactEvaluator.statusTextAndColor(for: rate)
        let barHeight = CGFloat(max(4, rate * 80))
        
        VStack(spacing: 6) {
            Spacer()
            
            Text("\(percent)%")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(display.color)
            
            RoundedRectangle(cornerRadius: 6)
                .fill(display.color)
                .frame(height: barHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.black, lineWidth: 1.2)
                )
            
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private var conditionHealthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Condition Health", systemImage: "chart.bar.doc.horizontal")
                .font(.system(.subheadline, design: .rounded, weight: .black))
                .foregroundStyle(Color.black)
                .padding(.top, 4)

            VStack(spacing: 16) {
                ForEach(pact.conditions) { cond in
                    let rate = conditionGroupComplianceRate(condition: cond)
                    let percent = Int(rate * 100)
                    let accentColor = cond.type == .todo ? KeptColor.green : KeptColor.coral
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(cond.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.black)
                            Spacer()
                            Text("\(percent)% kept")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(accentColor)
                        }
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.black.opacity(0.05))
                                    .frame(height: 8)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(accentColor)
                                    .frame(width: geo.size.width * CGFloat(rate), height: 8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.black, lineWidth: 0.8)
                                    )
                            }
                        }
                        .frame(height: 8)
                    }
                }
            }
            .padding(14)
            .background(Color.white)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.black, lineWidth: 1.5)
            )
        }
    }

    // Helper functions for stats computation
    private func conditionComplianceRate(for participantID: UUID, condition: PactCondition) -> (completed: Int, total: Int) {
        let pCheckIns = store.checkIns.filter { $0.pactID == pact.id && $0.userID == participantID }
        var completed = 0
        var total = 0
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.startOfDay(for: pact.startDate)
        let finish = min(calendar.startOfDay(for: pact.finishDate), today)
        guard start <= finish else { return (0, 0) }
        
        let dayCount = calendar.dateComponents([.day], from: start, to: finish).day ?? 0
        
        for offset in 0...dayCount {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            total += 1
            let checkIn = pCheckIns.first { calendar.isDate($0.day, inSameDayAs: day) }
            let val = checkIn?.values.first { $0.conditionID == condition.id }?.integerValue
            if condition.isSatisfied(value: val) {
                completed += 1
            }
        }
        return (completed, total)
    }

    private func conditionGroupComplianceRate(condition: PactCondition) -> Double {
        var completedCount = 0
        var totalCount = 0
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.startOfDay(for: pact.startDate)
        let finish = min(calendar.startOfDay(for: pact.finishDate), today)
        guard start <= finish else { return 0 }
        let dayCount = calendar.dateComponents([.day], from: start, to: finish).day ?? 0
        
        for participant in pact.participants {
            let pCheckIns = store.checkIns.filter { $0.pactID == pact.id && $0.userID == participant.profile.id }
            for offset in 0...dayCount {
                guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
                totalCount += 1
                let checkIn = pCheckIns.first { calendar.isDate($0.day, inSameDayAs: day) }
                let val = checkIn?.values.first { $0.conditionID == condition.id }?.integerValue
                if condition.isSatisfied(value: val) {
                    completedCount += 1
                }
            }
        }
        
        return totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0
    }

    // MARK: - Chat Tab

    private var chatTab: some View {
        VStack(spacing: 0) {
            // Hero mini header
            HStack(spacing: 10) {
                Image(systemName: pact.iconSymbol)
                    .font(.body.weight(.black))
                    .foregroundStyle(Color(hex: pact.accentColorHex))
                Text(pact.title)
                    .font(.subheadline.weight(.black))
                Spacer()
                Text("\(pact.participants.count) members")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color.white)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(Color.black.opacity(0.1)),
                alignment: .bottom
            )

            let chatMessages = store.pactMessages.filter { $0.pactID == pact.id }.sorted { $0.createdAt < $1.createdAt }

            if chatMessages.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.black.opacity(0.15))
                    Text("No messages yet")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("Fire up the war room!")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(chatMessages) { msg in
                                let isSystem = msg.senderID == systemSenderID

                                if isSystem {
                                    // System Event Pill
                                    Text(msg.text)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                        .background(Color.black.opacity(0.05))
                                        .clipShape(Capsule())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 2)
                                } else {
                                    let isMe = msg.senderID == store.currentUser?.id
                                    VStack(alignment: isMe ? .trailing : .leading, spacing: 3) {
                                        if !isMe {
                                            Text(msg.senderName)
                                                .font(.caption2.weight(.black))
                                                .foregroundStyle(Color(hex: msg.senderAccentColorHex))
                                        }
                                        HStack {
                                            if isMe { Spacer(minLength: 60) }
                                            Text(msg.text)
                                                .font(.subheadline)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(isMe ? Color.black : Color.white)
                                                .foregroundStyle(isMe ? Color.white : Color.black)
                                                .cornerRadius(14)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 14)
                                                        .stroke(Color.black, lineWidth: isMe ? 0 : 1.5)
                                                )
                                            if !isMe { Spacer(minLength: 60) }
                                        }
                                        Text(msg.createdAt.formatted(.dateTime.hour().minute()))
                                            .font(.system(size: 9))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: isMe ? .trailing : .leading)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .onAppear {
                        if let last = chatMessages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: chatMessages.count) {
                        if let last = chatMessages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            // Quick Reactions + Input Bar
            VStack(spacing: 8) {
                // Quick reaction buttons
                HStack(spacing: 8) {
                    ForEach(["💪", "🔥", "👏", "😤", "🫡"], id: \.self) { emoji in
                        Button {
                            store.sendPactMessage(pactID: pact.id, text: emoji)
                            HapticFeedback.impact()
                        } label: {
                            Text(emoji)
                                .font(.body)
                                .frame(width: 36, height: 36)
                                .background(Color.white)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.black, lineWidth: 1))
                        }
                    }
                    Spacer()
                }

                // Text Input
                HStack(spacing: 8) {
                    TextField("Message...", text: $chatText)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.black, lineWidth: 1.5)
                        )

                    Button {
                        store.sendPactMessage(pactID: pact.id, text: chatText)
                        chatText = ""
                        HapticFeedback.impact()
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(Color.white)
                            .padding(10)
                            .background(Color.black)
                            .clipShape(Circle())
                    }
                    .disabled(chatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color.white)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(Color.black.opacity(0.1)),
                alignment: .top
            )
        }
        .background(AppBackground())
    }

    // MARK: - Pact Completion Overlay

    private var pactCompletionOverlay: some View {
        let progress = store.pactProgress(for: pact, userID: store.currentUser?.id ?? UUID())

        return ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 56, weight: .black))
                    .foregroundStyle(KeptColor.citron)
                    .confettiBurst(isActive: showCompletion)

                Text("PACT COMPLETE")
                    .font(.system(size: 28, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .stampSlam(isActive: showCompletion)

                Text("Your word was kept for \(progress.completed) days")
                    .font(.headline)
                    .foregroundStyle(Color.white.opacity(0.8))

                Text(pact.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(hex: pact.accentColorHex))

                Button {
                    withAnimation {
                        showCompletion = false
                    }
                } label: {
                    Text("Dismiss")
                        .font(.subheadline.weight(.black))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .foregroundStyle(Color.black)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.black, lineWidth: 2)
                        )
                }
                .padding(.top, 8)
            }
        }
        .transition(.opacity)
    }

    private func checkIn(for participant: PactParticipant) -> CheckIn? {
        store.checkIns.first {
            $0.pactID == pact.id
                && $0.userID == participant.profile.id
                && Calendar.current.isDate($0.day, inSameDayAs: Date())
        }
    }
}

// MARK: - Stat Chip (for War Room)

struct StatChip: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .black))
                .foregroundStyle(KeptColor.ink)
            Text(label)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(Color.black.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black, lineWidth: 1.5)
        )
    }
}

struct FriendsView: View {
    @EnvironmentObject private var store: KeptStore
    @State private var handle = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Add friend") {
                    HStack(spacing: 8) {
                        TextField("@handle", text: $handle)
                            .textInputAutocapitalization(.never)
                        Button("Find") {
                            store.findFriend(handle: handle)
                        }
                        .disabled(handle.isEmpty)
                        Button("Add") {
                            store.sendFriendRequest(handle: handle)
                            handle = ""
                        }
                        .disabled(handle.isEmpty)
                    }
                    if !store.friendStatusMessage.isEmpty {
                        Text(store.friendStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

struct ProfileView: View {
    @EnvironmentObject private var store: KeptStore
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

                        ProfileStatsStrip(snapshot: store.profileSnapshot)
                        CurrentCommitmentsView(pacts: store.todaysPacts) { pact in
                            store.checkIn(for: pact)
                        }
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
        HStack(alignment: .center, spacing: 14) {
            ProfileAvatar(user: user, avatarData: avatarData, size: 76)

            VStack(alignment: .leading, spacing: 6) {
                Text(user.displayName)
                    .font(.system(.title2, design: .rounded, weight: .black))
                    .foregroundStyle(KeptColor.ink)
                    .lineLimit(1)
                Text(user.handle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(hex: user.accentColorHex))
                    .lineLimit(1)
                Text(user.bio.isEmpty ? "No bio yet." : user.bio)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(spacing: 8) {
                ScoreRing(score: snapshot.integrityScore, lineWidth: 6)
                    .frame(width: 62, height: 62)
                Button(action: edit) {
                    Image(systemName: "pencil")
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.white)
                        .frame(width: 32, height: 32)
                        .background(Color.black, in: Circle())
                }
                .accessibilityLabel("Edit profile")
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.black, lineWidth: 2)
        )
    }
}

struct ProfileStatsStrip: View {
    let snapshot: ProfileSnapshot

    var body: some View {
        HStack(spacing: 10) {
            CompactProfileMetric(title: "Active", value: "\(snapshot.activePactCount)", color: KeptColor.violet)
            CompactProfileMetric(title: "Streak", value: "\(snapshot.currentStreak)d", color: KeptColor.citron)
            CompactProfileMetric(title: "Kept", value: "\(Int((snapshot.completionRate * 100).rounded()))%", color: KeptColor.green)
        }
    }
}

struct CompactProfileMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.black))
                .foregroundStyle(KeptColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black, lineWidth: 1.3)
        )
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
                    let status = PactEvaluator.statusTextAndColor(pact: pact, checkIn: checkIn(pact))
                    let isOpen = status.text == "Open"
                    
                    HStack(spacing: 12) {
                        Image(systemName: pact.iconSymbol)
                            .foregroundStyle(Color.black)
                            .frame(width: 34, height: 34)
                            .background(Color(hex: pact.accentColorHex), in: Circle())
                            .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pact.title)
                                .font(.headline)
                            Text(pact.conditions.count == 1 ? pact.conditions[0].title : "\(pact.conditions.count) Conditions")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(status.text)
                            .font(.caption.weight(.black))
                            .foregroundStyle(isOpen ? Color.black.opacity(0.6) : Color.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isOpen ? Color.black.opacity(0.06) : status.color, in: Capsule())
                            .overlay(Capsule().stroke(Color.black, lineWidth: 1.5))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .keptGlass(cornerRadius: 24)
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
                            .foregroundStyle(item.isPositive ? KeptColor.green : KeptColor.coral)
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
        .keptGlass(cornerRadius: 24)
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
        .keptGlass(cornerRadius: 24)
    }
}

struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: KeptStore
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
                            .foregroundStyle(KeptColor.coral)
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
    @EnvironmentObject private var store: KeptStore
    @State private var permissionStatus = "Checking"
    @State private var defaultReminder = Calendar.current.date(from: DateComponents(hour: 20, minute: 0)) ?? Date()
    @State private var showingConfirmWipe = false

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

                if store.isCurrentUserDemo {
                    Section("Demo Data") {
                        Button(role: .destructive) {
                            showingConfirmWipe = true
                        } label: {
                            Label("Wipe demo data", systemImage: "trash.fill")
                        }
                    }
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
            .confirmationDialog("Wipe Demo Data?", isPresented: $showingConfirmWipe, titleVisibility: .visible) {
                Button("Wipe demo data", role: .destructive) {
                    store.clearDemoData()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all local demo pacts, check-ins, notifications, and reset your session.")
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
            if let avatarData, let image = PlatformImage.from(data: avatarData) {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let avatarURL = user.avatarURL, avatarURL.scheme != "kept-local-avatar" {
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
        .overlay(Circle().stroke(Color.black, lineWidth: 2))
        .accessibilityLabel("\(user.displayName) avatar")
    }

    private var fallback: some View {
        Image(systemName: user.avatarSymbol)
            .font(.system(size: size * 0.42, weight: .black))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: user.accentColorHex), in: Circle())
            .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
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
                .foregroundStyle(KeptColor.coral)
            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .black))
                .foregroundStyle(KeptColor.ink)
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
        let status = PactEvaluator.statusTextAndColor(pact: pact, checkIn: checkIn)
        let isOpen = checkIn == nil

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(pact.conditions.count == 1 ? pact.conditions[0].title : "\(pact.conditions.count) Conditions", systemImage: pact.iconSymbol)
                    .font(.caption.weight(.black))
                    .foregroundStyle(Color(hex: pact.accentColorHex))
                Spacer()
                Text(status.text)
                    .font(.caption.weight(.black))
                    .foregroundStyle(isOpen ? Color.black.opacity(0.6) : Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isOpen ? Color.black.opacity(0.06) : status.color, in: Capsule())
                    .overlay(Capsule().stroke(Color.black, lineWidth: 1.5))
            }
            Text(pact.title)
                .font(.title2.weight(.black))
                .foregroundStyle(KeptColor.ink)
            Text(pact.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                ForEach(pact.participants.prefix(4)) { participant in
                    Avatar(symbol: participant.profile.avatarSymbol, color: participant.isOwner ? KeptColor.coral : KeptColor.cyan, size: 34)
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(KeptColor.ink)
            }
        }
        .padding()
        .keptGlass(cornerRadius: 28, interactive: true)
    }
}

struct PactRow: View {
    let pact: Pact
    let checkIn: CheckIn?

    var body: some View {
        let status = PactEvaluator.statusTextAndColor(pact: pact, checkIn: checkIn)
        let isOpen = checkIn == nil
        
        let iconName: String = {
            if isOpen { return "clock.fill" }
            if status.text == "WORD KEPT" { return "checkmark.circle.fill" }
            if status.text == "PACT BROKEN" { return "exclamationmark.triangle.fill" }
            return "minus.circle.fill"
        }()
        
        let iconColor: Color = {
            if isOpen { return Color.black.opacity(0.2) }
            return status.color
        }()

        return HStack(spacing: 12) {
            Image(systemName: pact.iconSymbol)
                .foregroundStyle(Color.black)
                .frame(width: 34, height: 34)
                .background(Color(hex: pact.accentColorHex), in: Circle())
                .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 3) {
                Text(pact.title)
                    .font(.headline)
                Text(pact.dateRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
        }
    }
}

struct PactHero: View {
    let pact: Pact

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(pact.conditions.count == 1 ? pact.conditions[0].title : "\(pact.conditions.count) Conditions", systemImage: pact.iconSymbol)
                .font(.caption.weight(.black))
                .foregroundStyle(Color(hex: pact.accentColorHex))
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
        .background(Color.white)
        .cornerRadius(28)
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.black, lineWidth: 2)
        )
    }
}

struct FriendRow: View {
    let friend: KeptFriend
    var accept: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Avatar(symbol: friend.profile.avatarSymbol, color: friend.status == .accepted ? KeptColor.green : KeptColor.coral)
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
                    .foregroundStyle(KeptColor.green)
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
            .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
            .accessibilityHidden(true)
    }
}

#Preview {
    ContentView()
        .environmentObject(KeptStore.preview)
}
