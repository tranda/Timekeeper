import SwiftUI

@main
struct TimeKeeperApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 920, minHeight: 620)
        }
        .windowResizability(.contentSize)
    }
}