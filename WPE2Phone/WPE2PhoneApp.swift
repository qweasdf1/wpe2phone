import SwiftUI

@main
struct WPE2PhoneApp: App {
    @StateObject private var store = WallpaperStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
