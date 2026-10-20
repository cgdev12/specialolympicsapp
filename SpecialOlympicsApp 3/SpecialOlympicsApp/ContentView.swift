import SwiftUI
import Charts
import UserNotifications

private enum JoinStep {
    case details
    case verifyContact
    case enterCode
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var role: MemberRole?
    @State private var name = ""
    @State private var age = ""
    @State private var contact = ""
    @State private var organization = ""
    @State private var selectedSports: Set<Sport> = []
    @State private var joinStep: JoinStep = .details
    @State private var repeatedContact = ""
    @State private var sentCode: String?
    @State private var enteredCode = ""
    @State private var confirmError: String?
    @State private var tab = 0
    @State private var eventGroup: EventGroup = .main
    @State private var updateGroup: EventGroup = .main
    @State private var selectedEvent: Event?
    @State private var statsEvent: Event?
    @State private var showNewEvent = false
    @State private var showNewMessage = false

    var body: some View {
        Group {
            if model.currentUser == nil {
                onboarding
            } else {
                appTabs
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(.blue)
        .onAppear {
            UNUserNotificationCenter.current().delegate = NotificationRelay.shared
        }
        .sheet(item: $selectedEvent) { event in
            EventDetail(eventID: event.id)
        }
        .sheet(item: $statsEvent) { event in
            StatEntrySheet(eventID: event.id)
        }
        .sheet(isPresented: $showNewEvent) {
            NewEventView(group: eventGroup) { model.addEvent($0) }
        }
        .sheet(isPresented: $showNewMessage) {
            NewMessageView(group: updateGroup) { model.addMessage($0) }
        }
        .sheet(isPresented: thankYouBinding) {
            ThankYouLetter(name: model.currentUser?.name ?? name)
        }
    }

    private var thankYouBinding: Binding<Bool> {
        Binding(get: { model.showThankYou }, set: { model.showThankYou = $0 })
    }

    private var profileReady: Bool {
        nameIssue == nil && ageIssue == nil && contactIssue == nil &&
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !age.isEmpty &&
        !contact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var nameIssue: String? { InputCheck.nameIssue(name) }
    private var ageIssue: String? { InputCheck.ageIssue(age) }
    private var contactIssue: String? { InputCheck.contactIssue(contact) }

    private var onboarding: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "medal.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.yellow)
                    Text("Every athlete. Every volunteer. Every moment matters.")
                        .font(.title2.bold())
                    Text("Create your profile to connect with your team and receive updates.")
                        .foregroundStyle(.secondary)
                    if role == nil {
                        rolePicker
                    } else {
                        switch joinStep {
                        case .details: profileForm
                        case .verifyContact: verifyContactForm
                        case .enterCode: enterCodeForm
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Welcome")
        }
    }

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("I am joining as...")
                .font(.headline)
            ForEach(MemberRole.allCases) { choice in
                Button {
                    role = choice
                    joinStep = .details
                } label: {
                    HStack {
                        Image(systemName: choice.icon).font(.title2)
                        Text(choice.rawValue).font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var profileForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Joining as \(role?.rawValue ?? "")", systemImage: role?.icon ?? "person")
                .font(.headline)
                .foregroundStyle(.blue)
            labeledField("Your name", text: $name, issue: nameIssue, contentType: .name)
            labeledField("Your age", text: $age, issue: ageIssue, keyboard: .numberPad)
            labeledField("Email or phone number for updates", text: $contact, issue: contactIssue, contentType: .emailAddress, keyboard: .emailAddress)
            if role == .volunteer {
                TextField("Company or school (optional)", text: $organization)
                    .textFieldStyle(.roundedBorder)
            }
            if role == .athlete {
                Text("Apply for teams")
                    .font(.headline)
                Text("A coach approves each team. Floorball and hockey are the same team.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                SportChips(selection: $selectedSports)
            }
            Button("Continue") {
                joinStep = .verifyContact
                repeatedContact = ""
                sentCode = nil
                enteredCode = ""
                confirmError = nil
            }
            .buttonStyle(.borderedProminent)
            .disabled(!profileReady)
            Button("Choose a different role") {
                role = nil
                joinStep = .details
            }
            .font(.footnote)
        }
    }

    private var verifyContactForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirm your email or phone")
                .font(.headline)
            Text("You entered \(contact.trimmingCharacters(in: .whitespacesAndNewlines)). Type it again so we send the confirmation to a real address or number.")
                .foregroundStyle(.secondary)
            labeledField("Type your email or phone again", text: $repeatedContact, issue: repeatedIssue, contentType: .emailAddress, keyboard: .emailAddress)
            Button("Send confirmation") {
                let code = String(format: "%06d", Int.random(in: 0...999999))
                sentCode = code
                enteredCode = ""
                confirmError = nil
                model.sendConfirmation(contact: contact.trimmingCharacters(in: .whitespacesAndNewlines), code: code)
                joinStep = .enterCode
            }
            .buttonStyle(.borderedProminent)
            .disabled(!contactsMatch)
            Button("Back") { joinStep = .details }
                .font(.footnote)
        }
    }

    private var contactsMatch: Bool {
        InputCheck.contactIssue(repeatedContact) == nil &&
        !repeatedContact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        InputCheck.sameContact(contact, repeatedContact)
    }

    private var repeatedIssue: String? {
        if let issue = InputCheck.contactIssue(repeatedContact) { return issue }
        let trimmed = repeatedContact.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if !InputCheck.sameContact(contact, repeatedContact) {
            return "Type the same email or phone number you entered above."
        }
        return nil
    }

    private var enterCodeForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enter the code we sent")
                .font(.headline)
            Text("A confirmation message was sent to \(contact.trimmingCharacters(in: .whitespacesAndNewlines)). Enter the 6 numbers from that message. If you allow notifications, the same code arrives in a banner.")
                .foregroundStyle(.secondary)
            if let sentCode {
                SentMessageCard(contact: contact.trimmingCharacters(in: .whitespacesAndNewlines), code: sentCode)
            }
            labeledField("6-digit code", text: codeBinding, issue: codeIssue, keyboard: .numberPad)
            if let confirmError {
                Text(confirmError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button("Confirm and continue") { finishSignup() }
                .buttonStyle(.borderedProminent)
                .disabled(enteredCode.count != 6)
            Button("Send a new code") {
                let code = String(format: "%06d", Int.random(in: 0...999999))
                sentCode = code
                enteredCode = ""
                confirmError = nil
                model.sendConfirmation(contact: contact.trimmingCharacters(in: .whitespacesAndNewlines), code: code)
            }
            .font(.footnote)
            Button("Back") { joinStep = .verifyContact }
                .font(.footnote)
        }
    }

    private var codeBinding: Binding<String> {
        Binding(
            get: { enteredCode },
            set: { newValue in
                if newValue.contains(where: \.isLetter) {
                    confirmError = "Enter the code as numbers, not letters."
                } else if confirmError == "Enter the code as numbers, not letters." {
                    confirmError = nil
                }
                enteredCode = String(newValue.filter(\.isNumber).prefix(6))
            }
        )
    }

    private var codeIssue: String? {
        if enteredCode.isEmpty { return nil }
        if enteredCode.count < 6 { return "Enter all 6 numbers." }
        return nil
    }

    private func finishSignup() {
        guard enteredCode == sentCode else {
            confirmError = "That code does not match the message we sent."
            return
        }
        guard let years = Int(age.trimmingCharacters(in: .whitespacesAndNewlines)), let role else { return }
        model.completeSignup(
            role: role,
            name: name,
            age: years,
            contact: contact,
            organization: organization,
            sports: selectedSports
        )
    }

    private func resetJoinForm() {
        role = nil
        name = ""
        age = ""
        contact = ""
        organization = ""
        selectedSports = []
        joinStep = .details
        repeatedContact = ""
        sentCode = nil
        enteredCode = ""
        confirmError = nil
    }

    private func labeledField(
        _ title: String,
        text: Binding<String>,
        issue: String?,
        contentType: UITextContentType? = nil,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(title, text: text)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            if let issue {
                Text(issue)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var appTabs: some View {
        TabView(selection: $tab) {
            NavigationStack { eventsPage }
                .tabItem { Label("Events", systemImage: "calendar.badge.clock") }
                .tag(0)
            NavigationStack { calendarPage }
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(1)
            NavigationStack { communityPage }
                .tabItem { Label("Updates", systemImage: "megaphone.fill") }
                .tag(2)
            NavigationStack { profilePage }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(3)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: model.currentUser?.role.icon ?? "person")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading) {
                Text("Hi, \(model.currentUser?.name ?? "")")
                    .font(.headline)
                Text(model.currentUser?.role.rawValue ?? "")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var eventsPage: some View {
        VStack(spacing: 0) {
            GroupTabs(selection: $eventGroup)
                .padding(.horizontal)
                .padding(.bottom, 8)
            List {
                Section { header }
                if let reason = lockReason(for: eventGroup) {
                    Section { Text(reason).foregroundStyle(.secondary) }
                } else {
                    let upcoming = groupedEvents(eventGroup).filter { $0.date > Date() }
                    Section(eventGroup == .main ? "Main events" : "\(eventGroup.rawValue) events") {
                        if upcoming.isEmpty {
                            Text("No upcoming events in this group yet.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(upcoming) { event in
                            Button { selectedEvent = event } label: { EventRow(event: event) }
                                .buttonStyle(.plain)
                        }
                    }
                    if model.canEditStats {
                        let all = groupedEvents(eventGroup)
                        Section("Stat sheets") {
                            Text("Enter or change stats for any event, at any time.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if all.isEmpty {
                                Text("Post an event, then enter its stat sheet.")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(all) { event in
                                Button { statsEvent = event } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(event.title).font(.headline)
                                        Text(event.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Text("Enter or edit stats")
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if model.currentUser?.role == .volunteer, eventGroup == .main {
                    Section {
                        Button { model.showThankYou = true } label: {
                            Label("Read your latest thank-you letter", systemImage: "envelope.open.fill")
                        }
                    }
                }
            }
        }
        .navigationTitle("Special Olympics")
        .toolbar {
            if model.currentUser?.role == .admin {
                ToolbarItem(placement: .automatic) {
                    Button { showNewEvent = true } label: { Label("Post event", systemImage: "plus") }
                }
            }
        }
    }

    private var calendarPage: some View {
        let visible = currentCalendarEvents
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Team events land here with a reminder, the same way a calendar alert does.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                EventCalendar(events: visible) { selectedEvent = $0 }
                    .padding(.horizontal)
                VStack(alignment: .leading, spacing: 10) {
                    Text("On your calendar")
                        .font(.headline)
                    let upcoming = visible.filter { $0.date > Date().addingTimeInterval(-3600) }.sorted { $0.date < $1.date }
                    if upcoming.isEmpty {
                        Text("Nothing on your calendar yet. Main events show up for every athlete. Team events show up after a coach approves you.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(upcoming) { event in
                        Button { selectedEvent = event } label: { EventRow(event: event) }
                            .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Calendar")
    }

    private var communityPage: some View {
        VStack(spacing: 0) {
            GroupTabs(selection: $updateGroup)
                .padding(.horizontal)
                .padding(.bottom, 8)
            List {
                if let me = model.currentUser {
                    let mine = model.notices.filter { $0.personID == me.id }
                    if !mine.isEmpty {
                        Section("Messages for you") {
                            ForEach(mine) { notice in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(notice.title).font(.headline)
                                    Text(notice.body)
                                    Text(notice.date, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                if let reason = lockReason(for: updateGroup) {
                    Section { Text(reason).foregroundStyle(.secondary) }
                } else {
                    let posts = model.messages
                        .filter { $0.sport == updateGroup.sport }
                        .sorted { $0.date > $1.date }
                    Section(updateGroup == .main ? "Main updates" : "\(updateGroup.rawValue) updates") {
                        if posts.isEmpty {
                            Text("No updates for this group yet.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(posts) { message in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(message.title).font(.headline)
                                Text(message.body)
                                Text(message.date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Updates")
        .toolbar {
            if model.currentUser?.role == .admin {
                ToolbarItem(placement: .automatic) {
                    Button { showNewMessage = true } label: { Label("Post update", systemImage: "square.and.pencil") }
                }
            }
        }
    }

    private var profilePage: some View {
        List {
            Section("Your profile") {
                header
                if let me = model.currentUser {
                    Text("Age: \(me.age)")
                    Text("Updates: \(me.contact)")
                    if !me.organization.isEmpty {
                        Text(me.organization)
                    }
                }
            }
            if model.currentUser?.role == .admin {
                Section("Approve athletes for each team") {
                    if model.applicationRows.isEmpty {
                        Text("No applications yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.applicationRows) { row in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(row.name).font(.headline)
                            Text("\(row.sport.rawValue) · \(row.status.rawValue)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("Approve") {
                                    model.setApplication(personID: row.personID, sport: row.sport, status: .approved)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(row.status == .approved)
                                Button("Decline") {
                                    model.setApplication(personID: row.personID, sport: row.sport, status: .declined)
                                }
                                .disabled(row.status == .declined)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section("Athlete graphs") {
                    Text("Only you can enter or change stats, and you can do it at any time. Athletes can view the graph and cannot change it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(model.athletes) { athlete in
                        NavigationLink(athlete.name) {
                            AthleteStatsPage(athleteID: athlete.id)
                        }
                    }
                }
            }
            if model.currentUser?.role == .athlete, let me = model.currentUser {
                Section("Your teams") {
                    Text("Floorball and hockey are the same team. A coach approves each application.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(Sport.allCases) { sport in
                        HStack {
                            Label(sport.rawValue, systemImage: sport.icon)
                            Spacer()
                            if let status = model.status(for: sport, personID: me.id) {
                                Text(status.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("Apply") { model.apply(to: sport) }
                            }
                        }
                    }
                }
                Section("Your stats") {
                    Text("Only a coach can add or change stats.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    StatGraph(athleteID: me.id, editableNote: false)
                }
                Section("Showing up") {
                    Text("Attendance streak: \(athleteStreak) events")
                        .font(.headline)
                    Text("The streak counts past events you said you were coming to.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Badges earned") {
                    BadgeRow(streak: athleteStreak, hasStats: !model.statLines.filter { $0.athleteID == me.id }.isEmpty)
                }
            }
            if model.currentUser?.role == .volunteer {
                Section {
                    Button { model.showThankYou = true } label: {
                        Label("Your thank-you letter", systemImage: "heart.text.square.fill")
                    }
                }
            }
        }
        .navigationTitle("Profile")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Sign out") {
                    model.signOut()
                    resetJoinForm()
                }
            }
        }
    }

    private var athleteStreak: Int {
        guard let me = model.currentUser else { return 0 }
        return model.events.filter { $0.date < Date() && $0.attendeeIDs.contains(me.id) }.count
    }

    private var currentCalendarEvents: [Event] {
        guard let me = model.currentUser else { return [] }
        return model.calendarEvents(for: me)
    }

    private func groupedEvents(_ group: EventGroup) -> [Event] {
        model.events.filter { $0.sport == group.sport }.sorted { $0.date < $1.date }
    }

    private func lockReason(for group: EventGroup) -> String? {
        guard let me = model.currentUser, me.role == .athlete, let sport = group.sport else { return nil }
        switch model.status(for: sport, personID: me.id) {
        case .approved:
            return nil
        case .pending:
            return "Waiting for a coach to approve you for \(sport.rawValue). Team events and updates stay hidden until then."
        case .declined:
            return "A coach has not approved you for \(sport.rawValue)."
        case nil:
            return "Apply for \(sport.rawValue) from your profile. A coach approves each team."
        }
    }
}

struct GroupTabs: View {
    @Binding var selection: EventGroup

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EventGroup.allCases) { group in
                    Button(group.rawValue) { selection = group }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selection == group ? Color.blue : Color.blue.opacity(0.12), in: Capsule())
                        .foregroundStyle(selection == group ? Color.white : Color.blue)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct SportChips: View {
    @Binding var selection: Set<Sport>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
            ForEach(Sport.allCases) { sport in
                Button {
                    if selection.contains(sport) { selection.remove(sport) } else { selection.insert(sport) }
                } label: {
                    Label(sport.rawValue, systemImage: selection.contains(sport) ? "checkmark.circle.fill" : sport.icon)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(selection.contains(sport) ? Color.blue : Color.blue.opacity(0.1), in: Capsule())
                        .foregroundStyle(selection.contains(sport) ? Color.white : Color.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct EventRow: View {
    let event: Event

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "calendar")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.headline)
                Text(event.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                Text(event.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(reminderPhrase(event.reminderMinutes, sport: event.sport), systemImage: "bell.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            Spacer()
            Text("\(event.attendeeIDs.count)")
                .font(.headline)
                .foregroundStyle(.blue)
        }
    }
}

struct EventDetail: View {
    let eventID: UUID
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showStats = false

    private var event: Event? { model.events.first { $0.id == eventID } }

    var body: some View {
        NavigationStack {
            Group {
                if let event {
                    List {
                        Section {
                            Text(event.title).font(.title2.bold())
                            Label(event.sport?.rawValue ?? "Main event", systemImage: "person.3.fill")
                            Label(event.date.formatted(date: .long, time: .shortened), systemImage: "calendar")
                            Label(event.location, systemImage: "mappin.and.ellipse")
                            Label(reminderPhrase(event.reminderMinutes, sport: event.sport), systemImage: "bell.fill")
                        }
                        Section("Are you coming?") {
                            HStack(spacing: 12) {
                                RSVPChoiceButton(
                                    title: "Yes",
                                    subtitle: "I am coming",
                                    icon: "checkmark.circle.fill",
                                    selected: model.response(for: event.id) == .coming
                                ) {
                                    model.setComing(true, eventID: event.id)
                                }
                                RSVPChoiceButton(
                                    title: "No",
                                    subtitle: "I can’t make it",
                                    icon: "xmark.circle.fill",
                                    selected: model.response(for: event.id) == .notComing
                                ) {
                                    model.setComing(false, eventID: event.id)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                        Section("Attendance") {
                            HStack {
                                StatBadge(count: model.people(ids: event.attendeeIDs, role: .volunteer).count, label: "Volunteers", icon: "heart.fill")
                                StatBadge(count: model.people(ids: event.attendeeIDs, role: .athlete).count, label: "Athletes", icon: "figure.run")
                                StatBadge(count: event.declinedIDs.count, label: "Can’t make it", icon: "xmark.circle.fill")
                            }
                            if model.currentUser?.role == .admin {
                                AttendeeList(title: "Athletes coming", people: model.people(ids: event.attendeeIDs, role: .athlete), icon: "figure.run")
                                AttendeeList(title: "Volunteers coming", people: model.people(ids: event.attendeeIDs, role: .volunteer), icon: "heart.fill")
                            }
                            AttendeeList(
                                title: "Can’t make it",
                                people: model.people(ids: event.declinedIDs),
                                icon: "xmark.circle"
                            )
                        }
                        Section("Stat sheet") {
                            if model.canEditStats {
                                Button("Enter or edit the stat sheet") { showStats = true }
                                Text("You can enter or change these numbers at any time, including for main events.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if let me = model.currentUser, let line = model.statLine(eventID: event.id, athleteID: me.id) {
                                StatReadout(group: event.group, line: line)
                                Text("Only a coach can change these numbers.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Your coach has not entered your stats for this event yet.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("This event is no longer available.")
                }
            }
            .navigationTitle("Event")
            .toolbar {
                ToolbarItem(placement: .automatic) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showStats) {
                StatEntrySheet(eventID: eventID)
            }
        }
    }
}

struct RSVPChoiceButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title).font(.headline)
                Text(subtitle).font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .padding(.vertical, 12)
            .background(selected ? Color.blue : Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(selected ? Color.white : Color.blue)
        }
        .buttonStyle(.plain)
    }
}

struct AttendeeList: View {
    let title: String
    let people: [Person]
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            if people.isEmpty {
                Text("No one yet").foregroundStyle(.secondary)
            } else {
                ForEach(people) { person in
                    Label("\(person.name) · \(person.role.rawValue)", systemImage: icon)
                }
            }
        }
    }
}

struct StatBadge: View {
    let count: Int
    let label: String
    let icon: String

    var body: some View {
        VStack {
            Image(systemName: icon)
            Text("\(count)").font(.title.bold())
            Text(label).font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct EventCalendar: View {
    let events: [Event]
    let onSelect: (Event) -> Void
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    private var days: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        let count = calendar.range(of: .day, in: .month, for: .now)?.count ?? 30
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, symbol in
                Text(symbol).font(.caption.bold()).foregroundStyle(.secondary)
            }
            ForEach(days, id: \.self) { day in
                let matching = events.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
                Button {
                    if let event = matching.first { onSelect(event) }
                } label: {
                    VStack(spacing: 4) {
                        Text("\(Calendar.current.component(.day, from: day))")
                        Circle()
                            .fill(matching.isEmpty ? Color.clear : Color.blue)
                            .frame(width: 6, height: 6)
                    }
                    .frame(height: 38)
                }
                .buttonStyle(.plain)
                .disabled(matching.isEmpty)
            }
        }
    }
}

struct SentMessageCard: View {
    let contact: String
    let code: String

    private var isEmail: Bool { contact.contains("@") }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(isEmail ? "Confirmation email" : "Confirmation text", systemImage: isEmail ? "envelope.fill" : "message.fill")
                .font(.headline)
            Text("To: \(contact)")
                .font(.subheadline)
            Text("Your Special Olympics confirmation code is \(code). Enter it in the app so we know this \(isEmail ? "email" : "phone number") is real.")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct NewEventView: View {
    @Environment(\.dismiss) private var dismiss
    let group: EventGroup
    let onCreate: (Event) -> Void
    @State private var title = ""
    @State private var location = ""
    @State private var date = Date()
    @State private var reminder: ReminderLead = .hour

    var body: some View {
        NavigationStack {
            Form {
                TextField("Event title", text: $title)
                DatePicker("Date and time", selection: $date)
                TextField("Location", text: $location)
                Picker("Reminder", selection: $reminder) {
                    ForEach(ReminderLead.allCases) { lead in
                        Text(lead.label).tag(lead)
                    }
                }
                Section {
                    Text(group == .main
                         ? "This goes on the main calendar. Every athlete gets the reminder."
                         : "This goes on the \(group.rawValue) calendar. Approved athletes on that team get the reminder.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    Text("You can enter or change the stat sheet for this event at any time after posting.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(group == .main ? "Main event" : "\(group.rawValue) event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        onCreate(Event(
                            id: UUID(),
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            date: date,
                            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
                            sport: group.sport,
                            reminderMinutes: reminder.rawValue,
                            attendeeIDs: []
                        ))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct NewMessageView: View {
    @Environment(\.dismiss) private var dismiss
    let group: EventGroup
    let onCreate: (CommunityMessage) -> Void
    @State private var title = ""
    @State private var bodyText = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Update title", text: $title)
                TextEditor(text: $bodyText).frame(minHeight: 130)
                Section {
                    Text(group == .main
                         ? "This update goes to everyone."
                         : "This update goes only to the \(group.rawValue) group.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(group == .main ? "Main update" : "\(group.rawValue) update")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        onCreate(CommunityMessage(
                            id: UUID(),
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
                            date: Date(),
                            sport: group.sport
                        ))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct StatEntrySheet: View {
    let eventID: UUID
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var athleteID: UUID?
    @State private var values: [String: String] = [:]
    @State private var letterWarning: String?
    @State private var attempted = false
    @State private var showConfirm = false
    @FocusState private var focused: Bool

    private var event: Event? { model.events.first { $0.id == eventID } }

    var body: some View {
        NavigationStack {
            Group {
                if !model.canEditStats {
                    Text("Only a coach can enter stats.")
                        .foregroundStyle(.secondary)
                } else if let event {
                    form(event: event, group: event.group)
                } else {
                    Text("This event is no longer available.")
                }
            }
            .navigationTitle("Stat sheet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
        }
        .onAppear { prepare() }
    }

    private func form(event: Event, group: EventGroup) -> some View {
        let athletes = model.eligibleAthletes(for: group)
        return Form {
            Section {
                Text(group.sheetNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(event.title)
                Text(event.date.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            if athletes.isEmpty {
                Section {
                    Text(group.sport.map { "Approve an athlete for \($0.rawValue) before entering stats." }
                         ?? "No athletes are signed up yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Athlete") {
                    Picker("Athlete", selection: $athleteID) {
                        ForEach(athletes) { athlete in
                            let saved = model.statLine(eventID: event.id, athleteID: athlete.id) != nil
                            Text(saved ? "\(athlete.name) · sheet saved" : athlete.name).tag(Optional(athlete.id))
                        }
                    }
                    .onChange(of: athleteID) { _, _ in loadExisting(group: group) }
                }
                Section("Numbers only") {
                    if let letterWarning {
                        Text(letterWarning)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    ForEach(group.kinds) { kind in
                        VStack(alignment: .leading, spacing: 4) {
                            TextField(kind.label, text: numberBinding(kind.key))
                                .keyboardType(.numberPad)
                                .focused($focused)
                            Text("\(kind.min)–\(kind.max)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let issue = liveIssue(kind) {
                                Text(issue)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    Text("Enter 0 if the athlete had none. Letters are not accepted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button("Review these numbers") {
                        attempted = true
                        focused = false
                        if parsed(group) != nil { showConfirm = true }
                    }
                }
            }
        }
        .sheet(isPresented: $showConfirm) {
            if let athleteID, let ready = parsed(group) {
                NavigationStack {
                    StatConfirmView(eventID: event.id, athleteID: athleteID, group: group, values: ready) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func prepare() {
        guard let group = event?.group else { return }
        if values.isEmpty {
            for kind in group.kinds { values[kind.key] = "" }
        }
        if athleteID == nil {
            athleteID = model.eligibleAthletes(for: group).first?.id
        }
        loadExisting(group: group)
    }

    private func loadExisting(group: EventGroup) {
        guard let athleteID else { return }
        if let line = model.statLine(eventID: eventID, athleteID: athleteID) {
            for kind in group.kinds {
                values[kind.key] = String(line.values[kind.key] ?? 0)
            }
        } else {
            for kind in group.kinds { values[kind.key] = "" }
        }
        attempted = false
        letterWarning = nil
    }

    private func numberBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { values[key, default: ""] },
            set: { newValue in
                if newValue.contains(where: \.isLetter) {
                    letterWarning = "Use numbers only, not letters."
                } else {
                    letterWarning = nil
                }
                values[key] = newValue.filter(\.isNumber)
            }
        )
    }

    private func liveIssue(_ kind: StatKind) -> String? {
        let raw = values[kind.key, default: ""]
        if raw.isEmpty { return attempted ? "Enter \(kind.label) as a number." : nil }
        return InputCheck.wholeNumberIssue(raw, label: kind.label, min: kind.min, max: kind.max)
    }

    private func parsed(_ group: EventGroup) -> [String: Int]? {
        var result: [String: Int] = [:]
        for kind in group.kinds {
            let raw = values[kind.key, default: ""]
            if InputCheck.wholeNumberIssue(raw, label: kind.label, min: kind.min, max: kind.max) != nil { return nil }
            guard let number = Int(raw) else { return nil }
            result[kind.key] = number
        }
        return result
    }
}

struct StatConfirmView: View {
    let eventID: UUID
    let athleteID: UUID
    let group: EventGroup
    let values: [String: Int]
    let finish: () -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Text("Check that every value is a real number before it is saved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(model.people.first { $0.id == athleteID }?.name ?? "Athlete").font(.headline)
                Text(model.events.first { $0.id == eventID }?.title ?? "Event")
                Text(model.events.first { $0.id == eventID }?.date.formatted(date: .abbreviated, time: .omitted) ?? "")
                    .foregroundStyle(.secondary)
            }
            Section("Stat sheet") {
                ForEach(group.kinds) { kind in
                    HStack {
                        Text(kind.label)
                        Spacer()
                        Text("\(values[kind.key] ?? 0)")
                            .font(.headline.monospacedDigit())
                    }
                }
            }
            if let message {
                Section { Text(message).foregroundStyle(.red) }
            }
            Section {
                Button("These numbers are correct") {
                    if let error = model.saveStatLine(eventID: eventID, athleteID: athleteID, values: values) {
                        message = error
                    } else {
                        finish()
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Go back and edit") { dismiss() }
            }
        }
        .navigationTitle("Confirm stats")
    }
}

struct StatReadout: View {
    let group: EventGroup
    let line: StatLine

    var body: some View {
        ForEach(group.kinds) { kind in
            HStack {
                Text(kind.label)
                Spacer()
                Text("\(line.values[kind.key] ?? 0)")
                    .font(.headline.monospacedDigit())
            }
        }
    }
}

/// Coach-only editor for one saved stat sheet entry: the date and every number can change at any time.
struct StatLineEditSheet: View {
    let lineID: UUID
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var values: [String: String] = [:]
    @State private var letterWarning: String?
    @State private var attempted = false
    @State private var message: String?
    @State private var loaded = false
    @FocusState private var focused: Bool

    private var line: StatLine? { model.statLines.first { $0.id == lineID } }

    var body: some View {
        NavigationStack {
            Group {
                if !model.canEditStats {
                    Text("Only a coach can change stats.")
                        .foregroundStyle(.secondary)
                } else if let line {
                    form(line: line)
                } else {
                    Text("This stat sheet is no longer available.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit stat sheet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
        }
        .onAppear { load() }
    }

    private func form(line: StatLine) -> some View {
        let group = line.group
        return Form {
            Section {
                Text(model.people.first { $0.id == line.athleteID }?.name ?? "Athlete").font(.headline)
                Text(model.eventTitle(line.eventID))
                Text(group.sheetNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Date") {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Text("This moves the point on the graph. You can set any date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Numbers only") {
                if let letterWarning {
                    Text(letterWarning)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                ForEach(group.kinds) { kind in
                    VStack(alignment: .leading, spacing: 4) {
                        TextField(kind.label, text: numberBinding(kind.key))
                            .keyboardType(.numberPad)
                            .focused($focused)
                        Text("\(kind.min)–\(kind.max)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let issue = liveIssue(kind) {
                            Text(issue)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                Text("Enter 0 if the athlete had none. Letters are not accepted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message {
                Section { Text(message).foregroundStyle(.red) }
            }
            Section {
                Button("Save changes") {
                    attempted = true
                    focused = false
                    guard let ready = parsed(group) else { return }
                    if let error = model.updateStatLine(lineID: lineID, date: date, values: ready) {
                        message = error
                    } else {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func load() {
        guard !loaded, let line else { return }
        loaded = true
        date = line.date
        for kind in line.group.kinds {
            values[kind.key] = String(line.values[kind.key] ?? 0)
        }
    }

    private func numberBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { values[key, default: ""] },
            set: { newValue in
                if newValue.contains(where: \.isLetter) {
                    letterWarning = "Use numbers only, not letters."
                } else {
                    letterWarning = nil
                }
                values[key] = newValue.filter(\.isNumber)
            }
        )
    }

    private func liveIssue(_ kind: StatKind) -> String? {
        let raw = values[kind.key, default: ""]
        if raw.isEmpty { return attempted ? "Enter \(kind.label) as a number." : nil }
        return InputCheck.wholeNumberIssue(raw, label: kind.label, min: kind.min, max: kind.max)
    }

    private func parsed(_ group: EventGroup) -> [String: Int]? {
        var result: [String: Int] = [:]
        for kind in group.kinds {
            let raw = values[kind.key, default: ""]
            if InputCheck.wholeNumberIssue(raw, label: kind.label, min: kind.min, max: kind.max) != nil { return nil }
            guard let number = Int(raw) else { return nil }
            result[kind.key] = number
        }
        return result
    }
}

struct AthleteStatsPage: View {
    let athleteID: UUID
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            if let athlete = model.people.first(where: { $0.id == athleteID }) {
                Section {
                    Text(athlete.name).font(.headline)
                    Text(model.canEditStats
                         ? "Tap any stat sheet entry below to change its date or numbers, at any time."
                         : "Read only. Only a coach can change these numbers.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                StatGraph(athleteID: athleteID, editableNote: true)
            }
        }
        .navigationTitle("Stats")
    }
}

struct PlotPoint: Identifiable {
    let id: UUID
    let date: Date
    let value: Int
}

struct StatGraph: View {
    let athleteID: UUID
    let editableNote: Bool
    @EnvironmentObject private var model: AppModel
    @State private var group: EventGroup?
    @State private var statKey = ""

    private var person: Person? { model.people.first { $0.id == athleteID } }

    private var groups: [EventGroup] {
        guard let person else { return [] }
        if person.role == .athlete {
            return EventGroup.allCases.filter { item in
                guard let sport = item.sport else { return true }
                return model.status(for: sport, personID: person.id) == .approved
            }
        }
        return EventGroup.allCases
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if groups.isEmpty {
                Text("When a coach approves a team, stats for that team show up here.")
                    .foregroundStyle(.secondary)
            } else if let group {
                Picker("Team", selection: $group) {
                    ForEach(groups) { item in
                        Text(item.rawValue).tag(Optional(item))
                    }
                }
                .pickerStyle(.segmented)
                Text(group.sheetNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(group.kinds) { kind in
                            Button {
                                statKey = kind.key
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(statKey == kind.key ? Color.blue : Color.gray.opacity(0.35))
                                        .frame(width: 8, height: 8)
                                    Text(kind.label)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(statKey == kind.key ? Color.blue.opacity(0.12) : Color.clear, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if let kind = group.kinds.first(where: { $0.key == statKey }) {
                    StatGraphDetail(athleteID: athleteID, group: group, kind: kind)
                }
                Text(editableNote && model.canEditStats
                     ? "Tap a stat sheet entry below to change its date or numbers."
                     : "Only a coach can add or change these numbers.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .onAppear { pickDefaults() }
        .onChange(of: group) { _, newGroup in
            guard let newGroup else { return }
            if !newGroup.kinds.contains(where: { $0.key == statKey }) {
                statKey = newGroup.kinds.first?.key ?? ""
            }
        }
    }

    private func pickDefaults() {
        if group == nil || groups.contains(group!) == false {
            group = groups.first
            statKey = groups.first?.kinds.first?.key ?? ""
        } else if statKey.isEmpty {
            statKey = group?.kinds.first?.key ?? ""
        }
    }

}

struct StatGraphDetail: View {
    let athleteID: UUID
    let group: EventGroup
    let kind: StatKind
    @EnvironmentObject private var model: AppModel
    @State private var editingLine: StatLine?

    private var points: [PlotPoint] {
        model.lines(for: athleteID, group: group).map { line in
            PlotPoint(id: line.id, date: line.date, value: line.values[kind.key] ?? 0)
        }
    }

    private var lines: [StatLine] {
        model.lines(for: athleteID, group: group)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date is the horizontal axis. \(kind.label) is the vertical axis.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if points.isEmpty {
                Text("No \(group.displayName.lowercased()) stats yet. A coach adds them from the event’s stat sheet.")
                    .foregroundStyle(.secondary)
            } else {
                chart
                    .frame(height: 240)
                if points.count < 2 {
                    Text("One event is a point. After the next event, the points connect into a line.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if group == .golf && kind.key == "score" {
                    Text("A lower score means fewer strokes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if group == .bowling && kind.key == "score" {
                    Text("A bowling score is out of 300.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !lines.isEmpty {
                Text("Stat sheet")
                    .font(.headline)
                    .padding(.top, 4)
                ForEach(lines) { line in
                    if model.canEditStats {
                        Button { editingLine = line } label: {
                            sheetRow(line, editable: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        sheetRow(line, editable: false)
                    }
                }
            }
        }
        .sheet(item: $editingLine) { line in
            StatLineEditSheet(lineID: line.id)
        }
    }

    private func sheetRow(_ line: StatLine, editable: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.eventTitle(line.eventID)).font(.subheadline.bold())
                Text(line.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(group.kinds) { item in
                    HStack {
                        Text(item.label)
                        Spacer()
                        Text("\(line.values[item.key] ?? 0)")
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                }
                if editable {
                    Text("Tap to change the date or numbers")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            if editable {
                Image(systemName: "pencil.circle.fill")
                    .foregroundStyle(.blue)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var chart: some View {
        let peak = max(points.map(\.value).max() ?? 0, 1)
        let top = niceCeiling(max(peak, kind.min))
        let dates = points.map(\.date)
        let start = dates.min() ?? Date()
        let end = dates.max() ?? Date()
        let span = max(end.timeIntervalSince(start), 86_400)
        let pad = span * 0.12
        return Chart(points) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value(kind.label, point.value)
            )
            .foregroundStyle(.blue)
            .interpolationMethod(.linear)
            PointMark(
                x: .value("Date", point.date),
                y: .value(kind.label, point.value)
            )
            .foregroundStyle(.blue)
        }
        .chartXScale(domain: start.addingTimeInterval(-pad)...end.addingTimeInterval(pad))
        .chartYScale(domain: 0...Double(top))
        .chartXAxisLabel("Date")
        .chartYAxisLabel(kind.label)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: min(points.count, 4))) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel()
            }
        }
    }

    private func niceCeiling(_ value: Int) -> Int {
        let steps = [1, 2, 5, 10, 15, 20, 25, 50, 100, 150, 200, 300]
        return steps.first { $0 >= value } ?? value
    }
}

struct BadgeRow: View {
    let streak: Int
    let hasStats: Bool

    var body: some View {
        HStack(spacing: 18) {
            if hasStats { Badge(icon: "chart.line.uptrend.xyaxis", name: "Growing") }
            if streak > 0 { Badge(icon: "flame.fill", name: "Streak") }
            Badge(icon: "star.fill", name: "Team player")
        }
    }
}

struct Badge: View {
    let icon: String
    let name: String

    var body: some View {
        VStack {
            Image(systemName: icon).font(.title2).foregroundStyle(.yellow)
            Text(name).font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ThankYouLetter: View {
    @Environment(\.dismiss) private var dismiss
    let name: String

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "heart.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.pink)
                Text("Dear \(name),")
                    .font(.title2)
                    .italic()
                Text("Thank you for your help and commitment at practice. Your time, kindness, and encouragement make every athlete feel welcome and supported. We are so grateful to have you on our team!")
                    .font(.title3)
                    .italic()
                Spacer()
                Text("With gratitude,\nSpecial Olympics")
                    .italic()
            }
            .padding(28)
            .navigationTitle("A note for you")
            .toolbar {
                ToolbarItem(placement: .automatic) { Button("Done") { dismiss() } }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environmentObject(AppModel())
    }
}
