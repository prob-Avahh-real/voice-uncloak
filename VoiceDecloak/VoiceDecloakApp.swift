import SwiftUI

@main
struct VoiceUncloakApp: App {
    @StateObject private var viewModel = ProcessingViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .preferredColorScheme(.dark)
        }
    }
}
