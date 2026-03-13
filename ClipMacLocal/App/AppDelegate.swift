import SwiftUI
import AppKit
import ScreenCaptureKit
import UserNotifications
import OSLog

private let logger = Logger(subsystem: "com.clipmaclocal", category: "AppDelegate")

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    // MARK: Managers

    let captureEngine = CaptureEngine()
    let replayBuffer = ReplayBuffer()
    let audioEngine = AudioCaptureEngine()
    let permissionsManager = PermissionsManager()
    let menuBarManager = MenuBarManager()
    let hudManager = HUDWindowManager()
    let settings = AppSettings.shared

    lazy var library: ClipLibrary = ClipLibrary(storageDirectory: settings.storageDirectory)

    // MARK: Private

    private var menuBarUpdateTimer: Timer?
    private var bufferUpdateTask: Task<Void, Never>?

    // MARK: - applicationDidFinishLaunching

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Wire up the capture engine → replay buffer
        captureEngine.replayBuffer = replayBuffer
        captureEngine.audioEngine = audioEngine

        // Menu bar
        menuBarManager.setup()
        menuBarManager.onSaveClip = { [weak self] in self?.saveClip() }
        menuBarManager.onOpenLibrary = { [weak self] in self?.openLibraryWindow() }
        menuBarManager.onOpenSettings = { [weak self] in self?.openSettingsWindow() }
        menuBarManager.onToggleCapture = { [weak self] in self?.toggleCapture() }

        // Hotkeys
        HotkeyManager.shared.onSaveClip = { [weak self] in self?.saveClip() }
        HotkeyManager.shared.register(saveClipHotkey: settings.saveClipHotkey)

        // HUD
        hudManager.onSaveClip = { [weak self] in self?.saveClip() }
        if settings.showOnscreenHUD {
            hudManager.show(captureEngine: captureEngine, settings: settings)
        }

        // Permissions check & auto-start
        Task { @MainActor in
            await permissionsManager.checkAllPermissions()
            if permissionsManager.screenRecordingStatus == .granted {
                await startCapture()
            }
        }

        // Menu bar update timer
        startMenuBarUpdateTimer()

        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Auto-cleanup
        if settings.autoCleanupDays > 0 {
            library.performAutoCleanup(olderThan: settings.autoCleanupDays)
        }
    }

    // MARK: - applicationWillTerminate

    func applicationWillTerminate(_ notification: Notification) {
        Task { await captureEngine.stopCapture() }
        audioEngine.stopMicrophone()
        menuBarUpdateTimer?.invalidate()
        bufferUpdateTask?.cancel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Keep running as menu bar app
    }

    // MARK: - Capture Control

    func startCapture() async {
        do {
            replayBuffer.targetDuration = settings.bufferDuration + 5
            try await captureEngine.startCapture()
            if settings.captureMicrophone {
                try? audioEngine.startMicrophone()
            }
            menuBarManager.startPulseAnimation()
            menuBarManager.updateMenuRecordingState(isRecording: true)
            logger.info("Capture started successfully")
        } catch {
            logger.error("Failed to start capture: \(error.localizedDescription)")
            showCaptureError(error)
        }
    }

    func stopCapture() async {
        await captureEngine.stopCapture()
        audioEngine.stopMicrophone()
        menuBarManager.stopPulseAnimation()
        menuBarManager.updateMenuRecordingState(isRecording: false)
        menuBarManager.updateIcon(isRecording: false, bufferSeconds: 0)
    }

    func toggleCapture() {
        Task { @MainActor in
            if captureEngine.isCapturing {
                await stopCapture()
            } else {
                await startCapture()
            }
        }
    }

    // MARK: - Save Clip

    func saveClip() {
        Task { @MainActor in
            guard captureEngine.isCapturing else {
                showAlert("Not Recording", message: "Start recording first before saving a clip.")
                return
            }

            do {
                let url = try await replayBuffer.exportClip(
                    lastSeconds: settings.bufferDuration,
                    configuration: settings.captureConfiguration,
                    progress: nil
                )
                let clip = try await library.addClip(from: url, duration: settings.bufferDuration)
                if settings.showSaveNotification {
                    sendSaveNotification(for: clip)
                }
                logger.info("Clip saved: \(clip.title)")
            } catch {
                logger.error("Save clip error: \(error.localizedDescription)")
                showAlert("Save Failed", message: error.localizedDescription)
            }
        }
    }

    // MARK: - Notifications

    private func sendSaveNotification(for clip: Clip) {
        let content = UNMutableNotificationContent.clipSaved(
            title: "Clip Saved! 🎬",
            body: "\(clip.formattedDuration) · \(clip.formattedFileSize) → \(settings.storageDirectory.lastPathComponent)"
        )
        let request = UNNotificationRequest(identifier: clip.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Menu Bar Updates

    private func startMenuBarUpdateTimer() {
        menuBarUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let buffered = self.replayBuffer.bufferedDuration
                self.menuBarManager.updateIcon(
                    isRecording: self.captureEngine.isCapturing,
                    bufferSeconds: min(buffered, self.settings.bufferDuration)
                )
            }
        }
        menuBarUpdateTimer?.fire()
    }

    // MARK: - Window Management

    func openLibraryWindow() {
        NSApp.windows.filter { $0.title == "ClipMac Local" }.first?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openSettingsWindow() {
        // Settings is shown as a sheet from the main window
        openLibraryWindow()
    }

    // MARK: - Error Handling

    private func showCaptureError(_ error: Error) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Capture Error"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Screen Recording Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                self.permissionsManager.openScreenRecordingSettings()
            }
        }
    }

    private func showAlert(_ title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
