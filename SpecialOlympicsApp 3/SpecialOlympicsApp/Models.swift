import Foundation
import Combine
import UserNotifications

enum MemberRole: String, CaseIterable, Identifiable, Hashable {
    case athlete = "Athlete"
    case volunteer = "Volunteer"
    case admin = "Admin / Head Coach"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .athlete: "figure.run"
        case .volunteer: "heart.fill"
        case .admin: "person.badge.key.fill"
        }
    }
}

enum Sport: String, CaseIterable, Identifiable, Hashable {
    case floorball = "Floorball"
    case basketball = "Basketball"
    case golf = "Golf"
    case bowling = "Bowling"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .floorball: "figure.hockey"
        case .basketball: "basketball.fill"
        case .golf: "figure.golf"
        case .bowling: "figure.bowling"
        }
    }

    /// What a coach fills in after a game. Floorball and floor hockey share one sheet.
    var kinds: [StatKind] {
        switch self {
        case .floorball:
            return [
                StatKind(key: "goals", label: "Goals", min: 0, max: 20),
                StatKind(key: "assists", label: "Assists", min: 0, max: 20),
                StatKind(key: "shots", label: "Shots on goal", min: 0, max: 40),
                StatKind(key: "saves", label: "Saves", min: 0, max: 50),
                StatKind(key: "penalties", label: "Penalty minutes", min: 0, max: 20)
            ]
        case .basketball:
            return [
                StatKind(key: "points", label: "Points", min: 0, max: 100),
                StatKind(key: "rebounds", label: "Rebounds", min: 0, max: 40),
                StatKind(key: "assists", label: "Assists", min: 0, max: 30),
                StatKind(key: "steals", label: "Steals", min: 0, max: 15),
                StatKind(key: "blocks", label: "Blocks", min: 0, max: 15)
            ]
        case .golf:
            return [
                StatKind(key: "score", label: "Score", min: 1, max: 200),
                StatKind(key: "putts", label: "Putts", min: 0, max: 80),
                StatKind(key: "pars", label: "Pars", min: 0, max: 18)
            ]
        case .bowling:
            return [
                StatKind(key: "score", label: "Score", min: 0, max: 300),
                StatKind(key: "strikes", label: "Strikes", min: 0, max: 12),
                StatKind(key: "spares", label: "Spares", min: 0, max: 10)
            ]
        }
    }

    var sheetNote: String {
        switch self {
        case .floorball:
            "Floorball and hockey use this same match sheet: goals, assists, shots on goal, saves, and penalty minutes."
        case .basketball:
            "Basketball box score: points, rebounds, assists, steals, and blocks."
        case .golf:
            "Golf scorecard: total strokes, putts, and pars. A lower score means fewer strokes."
        case .bowling:
            "Bowling score sheet: game score out of 300, plus strikes and spares."
        }
    }
}

struct StatKind: Identifiable, Hashable {
    var key: String
    var label: String
    var min: Int
    var max: Int
    var id: String { key }
}

enum ApplicationStatus: String, Hashable {
    case pending = "Waiting for coach"
    case approved = "Approved"
    case declined = "Not approved"
}

struct TeamApplication: Identifiable, Hashable {
    let id: UUID
    var sport: Sport
    var status: ApplicationStatus
}

struct Person: Identifiable, Hashable {
    let id: UUID
    var name: String
    var role: MemberRole
    var age: Int
    var contact: String
    var organization: String
    var applications: [TeamApplication]
}

struct Event: Identifiable, Hashable {
    let id: UUID
    var title: String
    var date: Date
    var location: String
    var sport: Sport?
    var reminderMinutes: Int
    var attendeeIDs: [UUID]
}

struct CommunityMessage: Identifiable, Hashable {
    let id: UUID
    var title: String
    var body: String
    var date: Date
    var sport: Sport?
}

struct StatLine: Identifiable, Hashable {
    let id: UUID
    var athleteID: UUID
    var eventID: UUID
    var sport: Sport
    var date: Date
    var values: [String: Int]
}

struct Notice: Identifiable, Hashable {
    let id: UUID
    var personID: UUID
    var title: String
    var body: String
    var date: Date
}

struct ApplicationRow: Identifiable, Hashable {
    var personID: UUID
    var name: String
    var sport: Sport
    var status: ApplicationStatus
    var id: String { "\(personID.uuidString)-\(sport.rawValue)" }
}

enum EventGroup: String, CaseIterable, Identifiable {
    case main = "Main"
    case floorball = "Floorball"
    case basketball = "Basketball"
    case golf = "Golf"
    case bowling = "Bowling"

    var id: String { rawValue }

    var sport: Sport? {
        Sport(rawValue: rawValue)
    }
}

enum ReminderLead: Int, CaseIterable, Identifiable {
    case atTime = 0
    case fifteen = 15
    case hour = 60
    case day = 1440

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .atTime: "At time of event"
        case .fifteen: "15 minutes before"
        case .hour: "1 hour before"
        case .day: "1 day before"
        }
    }
}

enum InputCheck {
    static func nameIssue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.contains("@") { return "Enter your name, not an email." }
        if trimmed.allSatisfy({ $0.isNumber || $0 == " " }) { return "Enter your name, not an age." }
        if trimmed.contains(where: \.isNumber) { return "Enter your name, not a number." }
        return trimmed.range(of: #"^[\p{L}][\p{L} .'\-]*$"#, options: .regularExpression) == nil ? "Use letters for your name." : nil
    }

    static func ageIssue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.contains("@") { return "Enter your age, not an email." }
        if trimmed.contains(where: \.isLetter) { return "Enter your age as a number, not letters." }
        guard trimmed.allSatisfy(\.isNumber), let years = Int(trimmed) else { return "Enter your full age as a number." }
        guard (1...1000).contains(years) else { return "Enter an age from 1 to 1,000." }
        return nil
    }

    static func contactIssue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if isEmail(trimmed) || isPhone(trimmed) { return nil }
        let digits = trimmed.filter(\.isNumber)
        let hasLetter = trimmed.contains(where: \.isLetter)
        if trimmed.contains("@") { return "Enter a full email, like name123@email.com." }
        if !hasLetter, let years = Int(digits), digits.count <= 4, (1...1000).contains(years) {
            return "Enter a full phone number or email, not an age."
        }
        if hasLetter, digits.isEmpty { return "Enter a full email or phone number, not a name." }
        return "Enter a full email or phone number."
    }

    static func wholeNumberIssue(_ value: String, label: String, min: Int, max: Int) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Enter \(label) as a number." }
        if trimmed.contains(where: \.isLetter) { return "Enter \(label) as a number, not letters." }
        if trimmed.contains(where: { !$0.isNumber }) { return "Enter \(label) as a whole number, not letters or symbols." }
        guard let number = Int(trimmed) else { return "Enter \(label) as a whole number." }
        if number < min || number > max { return "Enter \(label) from \(min) to \(max)." }
        return nil
    }

    static func isEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let local = String(parts[0])
        let domain = String(parts[1])
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard labels.count >= 2, let tld = labels.last, tld.count >= 2, tld.allSatisfy(\.isLetter) else { return false }
        let localOK = local.contains(where: { $0.isLetter || $0.isNumber }) && local.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(.init(charactersIn: "._%+-")).contains($0)
        }
        let domainOK = labels.dropLast().allSatisfy { label in
            label.count >= 2 && label.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.union(.init(charactersIn: "-")).contains($0)
            }
        }
        return localOK && domainOK
    }

    static func isPhone(_ value: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "0123456789+()- .")
        let digits = value.filter(\.isNumber)
        return value.unicodeScalars.allSatisfy { allowed.contains($0) } && (10...15).contains(digits.count)
    }

    static func sameContact(_ first: String, _ second: String) -> Bool {
        let left = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = second.trimmingCharacters(in: .whitespacesAndNewlines)
        if isEmail(left) || isEmail(right) { return left.lowercased() == right.lowercased() }
        let leftDigits = left.filter(\.isNumber)
        let rightDigits = right.filter(\.isNumber)
        return !leftDigits.isEmpty && leftDigits == rightDigits
    }
}

enum SeedID {
    static let maya = UUID(uuidString: "A0000001-0000-0000-0000-000000000001")!
    static let kai = UUID(uuidString: "A0000001-0000-0000-0000-000000000002")!
    static let sam = UUID(uuidString: "A0000001-0000-0000-0000-000000000003")!
    static let jordan = UUID(uuidString: "A0000001-0000-0000-0000-000000000004")!
}

@MainActor
final class AppModel: ObservableObject {
    @Published var sessionPersonID: UUID?
    @Published var people: [Person]
    @Published var events: [Event]
    @Published var messages: [CommunityMessage]
    @Published var statLines: [StatLine]
    @Published var notices: [Notice]
    @Published var showThankYou = false

    init() {
        let seeded = SeedData.make()
        people = seeded.people
        events = seeded.events
        messages = seeded.messages
        statLines = seeded.statLines
        notices = []
    }

    var currentUser: Person? {
        guard let sessionPersonID else { return nil }
        return people.first { $0.id == sessionPersonID }
    }

    var athletes: [Person] {
        people.filter { $0.role == .athlete }.sorted { $0.name < $1.name }
    }

    var applicationRows: [ApplicationRow] {
        people.filter { $0.role == .athlete }.flatMap { person in
            person.applications.map {
                ApplicationRow(personID: person.id, name: person.name, sport: $0.sport, status: $0.status)
            }
        }
        .sorted { left, right in
            let rank: (ApplicationStatus) -> Int = { status in
                switch status {
                case .pending: 0
                case .approved: 1
                case .declined: 2
                }
            }
            if rank(left.status) != rank(right.status) { return rank(left.status) < rank(right.status) }
            if left.name != right.name { return left.name < right.name }
            return left.sport.rawValue < right.sport.rawValue
        }
    }

    func completeSignup(role: MemberRole, name: String, age: Int, contact: String, organization: String, sports: Set<Sport>) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContact = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = people.firstIndex(where: { $0.role == role && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
            people[index].age = age
            people[index].contact = trimmedContact
            people[index].organization = organization.trimmingCharacters(in: .whitespacesAndNewlines)
            if role == .athlete {
                for sport in sports where !people[index].applications.contains(where: { $0.sport == sport }) {
                    people[index].applications.append(TeamApplication(id: UUID(), sport: sport, status: .pending))
                }
            }
            sessionPersonID = people[index].id
        } else {
            let applications = sports.map { TeamApplication(id: UUID(), sport: $0, status: .pending) }
            let person = Person(
                id: UUID(),
                name: trimmedName,
                role: role,
                age: age,
                contact: trimmedContact,
                organization: organization.trimmingCharacters(in: .whitespacesAndNewlines),
                applications: role == .athlete ? applications : []
            )
            people.append(person)
            sessionPersonID = person.id
        }
        refreshReminders()
    }

    func signOut() {
        sessionPersonID = nil
        showThankYou = false
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    func apply(to sport: Sport) {
        guard let me = currentUser, me.role == .athlete else { return }
        guard let index = people.firstIndex(where: { $0.id == me.id }) else { return }
        guard !people[index].applications.contains(where: { $0.sport == sport }) else { return }
        people[index].applications.append(TeamApplication(id: UUID(), sport: sport, status: .pending))
    }

    func setApplication(personID: UUID, sport: Sport, status: ApplicationStatus) {
        guard currentUser?.role == .admin else { return }
        guard let index = people.firstIndex(where: { $0.id == personID }) else { return }
        guard let appIndex = people[index].applications.firstIndex(where: { $0.sport == sport }) else { return }
        people[index].applications[appIndex].status = status
        if personID == sessionPersonID {
            refreshReminders()
        }
    }

    func status(for sport: Sport, personID: UUID) -> ApplicationStatus? {
        people.first { $0.id == personID }?.applications.first { $0.sport == sport }?.status
    }

    func canSeeEvent(_ event: Event, person: Person) -> Bool {
        if person.role != .athlete { return true }
        guard let sport = event.sport else { return true }
        return status(for: sport, personID: person.id) == .approved
    }

    func canSeeMessage(_ message: CommunityMessage, person: Person) -> Bool {
        if person.role != .athlete { return true }
        guard let sport = message.sport else { return true }
        return status(for: sport, personID: person.id) == .approved
    }

    func calendarEvents(for person: Person) -> [Event] {
        if person.role == .athlete {
            return events.filter { canSeeEvent($0, person: person) }
        }
        return events
    }

    func addEvent(_ event: Event) {
        guard currentUser?.role == .admin else { return }
        events.append(event)
        refreshReminders()
    }

    func addMessage(_ message: CommunityMessage) {
        guard currentUser?.role == .admin else { return }
        messages.insert(message, at: 0)
        let audience = message.sport?.rawValue ?? "everyone"
        let body = "\(message.title): \(message.body)"
        for person in people where person.role == .athlete && canSeeMessage(message, person: person) {
            postNotice(personID: person.id, title: "Update for \(audience)", body: body)
        }
        notify(title: "Update posted", body: "Sent to \(audience). \(message.title)")
    }

    func setComing(_ coming: Bool, eventID: UUID) {
        guard let me = currentUser else { return }
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        if me.role == .athlete && !canSeeEvent(events[index], person: me) { return }
        events[index].attendeeIDs.removeAll { $0 == me.id }
        if coming {
            events[index].attendeeIDs.append(me.id)
            if me.role == .volunteer { showThankYou = true }
        }
    }

    func approvedAthletes(for sport: Sport) -> [Person] {
        athletes.filter { status(for: sport, personID: $0.id) == .approved }
    }

    func statLine(eventID: UUID, athleteID: UUID) -> StatLine? {
        statLines.first { $0.eventID == eventID && $0.athleteID == athleteID }
    }

    func saveStatLine(eventID: UUID, athleteID: UUID, values: [String: Int]) -> String? {
        guard currentUser?.role == .admin else { return "Only a coach can enter stats." }
        guard let event = events.first(where: { $0.id == eventID }) else { return "That event is missing." }
        guard let sport = event.sport else { return "Main events do not have a team stat sheet." }
        guard event.date <= Date() else { return "Enter stats after the event happens." }
        guard approvedAthletes(for: sport).contains(where: { $0.id == athleteID }) else {
            return "Approve this athlete for the team before entering stats."
        }
        var clean: [String: Int] = [:]
        for kind in sport.kinds {
            guard let number = values[kind.key] else { return "Enter \(kind.label) as a number." }
            if let issue = InputCheck.wholeNumberIssue(String(number), label: kind.label, min: kind.min, max: kind.max) {
                return issue
            }
            clean[kind.key] = number
        }
        if let index = statLines.firstIndex(where: { $0.eventID == eventID && $0.athleteID == athleteID }) {
            statLines[index].values = clean
            statLines[index].date = event.date
            statLines[index].sport = sport
        } else {
            statLines.append(StatLine(id: UUID(), athleteID: athleteID, eventID: eventID, sport: sport, date: event.date, values: clean))
        }
        let athleteName = people.first { $0.id == athleteID }?.name ?? "Athlete"
        let summary = sport.kinds.map { "\($0.label) \(clean[$0.key] ?? 0)" }.joined(separator: ", ")
        let body = "\(athleteName), \(event.title): \(summary)"
        postNotice(personID: athleteID, title: "Your coach entered stats", body: body)
        if let adminID = sessionPersonID {
            postNotice(personID: adminID, title: "Stats confirmed", body: body)
        }
        notify(title: "Stats confirmed", body: body)
        return nil
    }

    func lines(for athleteID: UUID, sport: Sport) -> [StatLine] {
        statLines.filter { $0.athleteID == athleteID && $0.sport == sport }.sorted { $0.date < $1.date }
    }

    func eventTitle(_ id: UUID) -> String {
        events.first { $0.id == id }?.title ?? "Event"
    }

    func people(ids: [UUID], role: MemberRole) -> [Person] {
        ids.compactMap { id in people.first { $0.id == id && $0.role == role } }
    }

    func postNotice(personID: UUID, title: String, body: String) {
        notices.insert(Notice(id: UUID(), personID: personID, title: title, body: body, date: Date()), at: 0)
    }

    func refreshReminders() {
        guard let me = currentUser, me.role == .athlete else { return }
        let mine = calendarEvents(for: me).filter { $0.date > Date() }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let center = UNUserNotificationCenter.current()
            let identifiers = mine.map { "event-\($0.id.uuidString)-\(me.id.uuidString)" }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            for event in mine {
                var fire = event.date.addingTimeInterval(TimeInterval(-event.reminderMinutes * 60))
                if fire < Date() { fire = Date().addingTimeInterval(3) }
                let content = UNMutableNotificationContent()
                content.title = event.sport?.rawValue ?? "Main event"
                content.body = "\(event.title) at \(event.location)"
                content.sound = .default
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "event-\(event.id.uuidString)-\(me.id.uuidString)",
                    content: content,
                    trigger: trigger
                )
                center.add(request)
            }
        }
    }

    func sendConfirmation(contact: String, code: String) {
        let title = contact.contains("@") ? "Confirm your email" : "Confirm your phone number"
        notify(title: title, body: "Your Special Olympics code is \(code).")
    }

    func notify(title: String, body: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}

enum SeedData {
    static func make() -> (people: [Person], events: [Event], messages: [CommunityMessage], statLines: [StatLine]) {
        let people = [
            Person(id: SeedID.maya, name: "Maya Chen", role: .athlete, age: 19, contact: "maya@example.com", organization: "", applications: [
                TeamApplication(id: UUID(), sport: .bowling, status: .approved),
                TeamApplication(id: UUID(), sport: .golf, status: .pending)
            ]),
            Person(id: SeedID.kai, name: "Kai Brooks", role: .athlete, age: 22, contact: "kai@example.com", organization: "", applications: [
                TeamApplication(id: UUID(), sport: .floorball, status: .approved),
                TeamApplication(id: UUID(), sport: .basketball, status: .pending)
            ]),
            Person(id: SeedID.sam, name: "Sam Ortiz", role: .athlete, age: 17, contact: "sam@example.com", organization: "", applications: [
                TeamApplication(id: UUID(), sport: .basketball, status: .approved)
            ]),
            Person(id: SeedID.jordan, name: "Jordan Lee", role: .volunteer, age: 28, contact: "jordan@example.com", organization: "North High", applications: [])
        ]

        let floorballDates = [dayOffset(-21), dayOffset(-14), dayOffset(-7)]
        let floorballEvents = [
            makeEvent("Floorball vs East", date: floorballDates[0], location: "Ice Hall A", sport: .floorball, attendees: [SeedID.kai]),
            makeEvent("Floorball vs West", date: floorballDates[1], location: "Ice Hall A", sport: .floorball, attendees: [SeedID.kai]),
            makeEvent("Floorball practice game", date: floorballDates[2], location: "Ice Hall B", sport: .floorball, attendees: [SeedID.kai])
        ]
        let bowlingDates = [dayOffset(-20), dayOffset(-13), dayOffset(-6)]
        let bowlingEvents = [
            makeEvent("Bowling week 1", date: bowlingDates[0], location: "Sunset Lanes", sport: .bowling, attendees: [SeedID.maya]),
            makeEvent("Bowling week 2", date: bowlingDates[1], location: "Sunset Lanes", sport: .bowling, attendees: [SeedID.maya]),
            makeEvent("Bowling week 3", date: bowlingDates[2], location: "Sunset Lanes", sport: .bowling, attendees: [SeedID.maya])
        ]
        let basketballEvents = [
            makeEvent("Basketball vs Central", date: dayOffset(-16), location: "Northside Gym", sport: .basketball, attendees: [SeedID.sam]),
            makeEvent("Basketball vs Harbor", date: dayOffset(-9), location: "Northside Gym", sport: .basketball, attendees: [SeedID.sam])
        ]
        let upcoming = [
            makeEvent("Community bowling night", date: dayOffset(4), location: "Sunset Lanes", sport: nil, attendees: [SeedID.jordan]),
            makeEvent("Floorball home game", date: dayOffset(6), location: "Ice Hall A", sport: .floorball, attendees: []),
            makeEvent("Basketball skills clinic", date: dayOffset(10), location: "Northside Gym", sport: .basketball, attendees: []),
            makeEvent("Golf skills day", date: dayOffset(-5), location: "River Greens", sport: .golf, attendees: []),
            makeEvent("Golf outing", date: dayOffset(12), location: "River Greens", sport: .golf, attendees: [])
        ]
        let events = floorballEvents + bowlingEvents + basketballEvents + upcoming

        let kaiGoals = [1, 2, 4]
        let kaiAssists = [0, 1, 1]
        let kaiShots = [4, 6, 8]
        var lines: [StatLine] = []
        for index in floorballEvents.indices {
            lines.append(StatLine(
                id: UUID(),
                athleteID: SeedID.kai,
                eventID: floorballEvents[index].id,
                sport: .floorball,
                date: floorballEvents[index].date,
                values: ["goals": kaiGoals[index], "assists": kaiAssists[index], "shots": kaiShots[index], "saves": 0, "penalties": index == 1 ? 2 : 0]
            ))
        }
        let mayaScores = [96, 112, 126]
        let mayaStrikes = [1, 2, 3]
        let mayaSpares = [3, 4, 4]
        for index in bowlingEvents.indices {
            lines.append(StatLine(
                id: UUID(),
                athleteID: SeedID.maya,
                eventID: bowlingEvents[index].id,
                sport: .bowling,
                date: bowlingEvents[index].date,
                values: ["score": mayaScores[index], "strikes": mayaStrikes[index], "spares": mayaSpares[index]]
            ))
        }
        let samPoints = [6, 11]
        let samRebounds = [3, 5]
        for index in basketballEvents.indices {
            lines.append(StatLine(
                id: UUID(),
                athleteID: SeedID.sam,
                eventID: basketballEvents[index].id,
                sport: .basketball,
                date: basketballEvents[index].date,
                values: ["points": samPoints[index], "rebounds": samRebounds[index], "assists": index + 1, "steals": 1, "blocks": index]
            ))
        }

        let messages = [
            CommunityMessage(id: UUID(), title: "Welcome to the fall season!", body: "We’re excited to see everyone at the first practice. Bring water and your uniform.", date: dayOffset(-2), sport: nil),
            CommunityMessage(id: UUID(), title: "Bring your stick", body: "Floorball and hockey athletes: this is the same team. Sticks are at the rink.", date: dayOffset(-1), sport: .floorball),
            CommunityMessage(id: UUID(), title: "Court shoes on Friday", body: "Basketball athletes, wear indoor shoes to the clinic.", date: dayOffset(-1, hour: 12), sport: .basketball),
            CommunityMessage(id: UUID(), title: "Lane assignments", body: "Bowling athletes check in 15 minutes early at Sunset Lanes.", date: dayOffset(-3), sport: .bowling),
            CommunityMessage(id: UUID(), title: "Range balls", body: "Golf athletes, clubs are provided if you do not have your own.", date: dayOffset(-4), sport: .golf)
        ]
        return (people, events, messages, lines)
    }

    private static func makeEvent(_ title: String, date: Date, location: String, sport: Sport?, attendees: [UUID]) -> Event {
        Event(id: UUID(), title: title, date: date, location: location, sport: sport, reminderMinutes: ReminderLead.hour.rawValue, attendeeIDs: attendees)
    }

    private static func dayOffset(_ days: Int, hour: Int = 18) -> Date {
        let calendar = Calendar.current
        let shifted = calendar.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: shifted) ?? shifted
    }
}

func reminderPhrase(_ minutes: Int, sport: Sport?) -> String {
    let when: String
    switch minutes {
    case 0: when = "at the time of the event"
    case 15: when = "15 minutes before"
    case 60: when = "1 hour before"
    case 1440: when = "1 day before"
    default: when = "\(minutes) minutes before"
    }
    if sport == nil {
        return "Every athlete gets a reminder \(when), like a calendar alert."
    }
    return "Approved \(sport?.rawValue ?? "team") athletes get a reminder \(when), like a calendar alert."
}

final class NotificationRelay: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRelay()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
