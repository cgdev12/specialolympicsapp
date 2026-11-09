import SwiftUI

@main
struct SpecialOlympicsApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var authentication = Authentication()

    var body: some Scene {
        WindowGroup {
            Group {
                if authentication.currentUser == nil {
                    SignInView()
                } else if let email = authentication.currentUser?.email,
                          authentication.savedOnboardingProfile(for: email) == nil {
                    SignInView(profileSetup: true)
                } else {
                    ContentView()
                        .environmentObject(model)
                }
            }
            .environmentObject(authentication)
            .environmentObject(model)
            .task { await authentication.restoreSession() }
            .onChange(of: authentication.currentUser?.email, initial: true) { _, email in
                guard let email,
                      model.currentUser == nil,
                      let profile = authentication.savedOnboardingProfile(for: email) else { return }
                model.completeSignup(
                    // A portal-approved backend admin is the source of truth
                    // for Head Coach access. A local volunteer selection must
                    // never override that approval.
                    role: authentication.currentUser?.isAdmin == true ? .admin : profile.role,
                    name: profile.name,
                    age: profile.age,
                    contact: profile.phone,
                    organization: profile.organization,
                    sports: []
                )
            }
        }
    }
}
