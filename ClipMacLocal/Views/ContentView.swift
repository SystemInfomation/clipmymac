import SwiftUI
import UserNotifications

// MARK: - Content View

/// Main window showing the library or onboarding.
struct ContentView: View {

    @EnvironmentObject var permissionsManager: PermissionsManager
    @EnvironmentObject var captureEngine: CaptureEngine
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var audioEngine: AudioCaptureEngine
    @State private var showingSettings: Bool = false

    var body: some View {
        Group {
            if permissionsManager.screenRecordingStatus != .granted {
                OnboardingView()
                    .environmentObject(permissionsManager)
            } else {
                LibraryView()
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                showingSettings = true
                            } label: {
                                Image(systemName: "gear")
                            }
                            .help("Settings")
                        }
                    }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(captureEngine)
                .environmentObject(permissionsManager)
                .environmentObject(audioEngine)
        }
        .onAppear {
            requestNotificationPermission()
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
