import Foundation
import ScreenCaptureKit
import AVFoundation
import AppKit
import OSLog

private let logger = Logger(subsystem: "com.clipmaclocal", category: "PermissionsManager")

// MARK: - Permission Status

enum PermissionStatus {
    case notDetermined
    case granted
    case denied
}

// MARK: - Permissions Manager

@MainActor
final class PermissionsManager: ObservableObject {

    // MARK: Published

    @Published var screenRecordingStatus: PermissionStatus = .notDetermined
    @Published var microphoneStatus: PermissionStatus = .notDetermined
    @Published var allPermissionsGranted: Bool = false

    // MARK: - Check All Permissions

    func checkAllPermissions() async {
        await checkScreenRecordingPermission()
        await checkMicrophonePermission()
        allPermissionsGranted = (screenRecordingStatus == .granted)
    }

    // MARK: - Screen Recording

    func checkScreenRecordingPermission() async {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            screenRecordingStatus = .granted
            logger.info("Screen recording permission granted")
        } catch {
            screenRecordingStatus = .denied
            logger.warning("Screen recording permission denied: \(error.localizedDescription)")
        }
    }

    func requestScreenRecordingPermission() async {
        // Trigger the system permission dialog by attempting to use SCShareableContent
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            screenRecordingStatus = .granted
        } catch {
            screenRecordingStatus = .denied
        }
        allPermissionsGranted = (screenRecordingStatus == .granted)
    }

    // MARK: - Microphone

    func checkMicrophonePermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            microphoneStatus = .granted
        case .denied, .restricted:
            microphoneStatus = .denied
        case .notDetermined:
            microphoneStatus = .notDetermined
        @unknown default:
            microphoneStatus = .notDetermined
        }
    }

    func requestMicrophonePermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneStatus = granted ? .granted : .denied
        logger.info("Microphone permission \(granted ? "granted" : "denied")")
    }

    // MARK: - Open System Settings

    func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }
}
