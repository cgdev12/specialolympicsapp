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
                } else if authentication.sharedProfile == nil {
                    SignInView(profileSetup: true)
                } else {
                    ContentView()
                        .environmentObject(model)
                }
            }
            .environmentObject(authentication)
            .environmentObject(model)
            .task { await authentication.restoreSession() }
            .onChange(of: authentication.sharedProfile, initial: true) { _, profile in
                guard let profile else { return }
                model.beginSharedSession(profile: profile)
            }
        }
    }
}
