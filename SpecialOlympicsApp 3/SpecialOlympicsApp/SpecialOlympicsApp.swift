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
                } else {
                    ContentView(initialRole: authentication.onboardingRole)
                        .environmentObject(model)
                }
            }
            .environmentObject(authentication)
            .task { await authentication.restoreSession() }
        }
    }
}
