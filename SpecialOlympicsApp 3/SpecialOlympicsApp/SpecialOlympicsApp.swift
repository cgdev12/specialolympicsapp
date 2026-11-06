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
                    ContentView()
                        .environmentObject(model)
                }
            }
            .environmentObject(authentication)
            .task { await authentication.restoreSession() }
        }
    }
}
