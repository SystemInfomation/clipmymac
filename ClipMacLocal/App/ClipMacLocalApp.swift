import SwiftUI

// MARK: - ClipMac Local App

@main
struct ClipMacLocalApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("ClipMac Local") {
            ContentView()
                .environmentObject(appDelegate.captureEngine)
                .environmentObject(appDelegate.library)
                .environmentObject(appDelegate.settings)
                .environmentObject(appDelegate.permissionsManager)
                .environmentObject(appDelegate.audioEngine)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Capture") {
                Button("Save Last Clip") {
                    appDelegate.saveClip()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Start / Stop Recording") {
                    appDelegate.toggleCapture()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appDelegate.settings)
                .environmentObject(appDelegate.captureEngine)
                .environmentObject(appDelegate.permissionsManager)
                .environmentObject(appDelegate.audioEngine)
        }
    }
}
