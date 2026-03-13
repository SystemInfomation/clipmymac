import Foundation
import Combine
import AppKit

// MARK: - App Settings

/// Central settings store using @AppStorage / UserDefaults.
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    // MARK: - Buffer & Capture

    @Published var bufferDuration: Double {
        didSet { UserDefaults.standard.set(bufferDuration, forKey: "bufferDuration") }
    }

    @Published var captureMode: CaptureConfiguration.CaptureMode {
        didSet { UserDefaults.standard.set(captureMode.rawValue, forKey: "captureMode") }
    }

    @Published var selectedDisplayID: CGDirectDisplayID {
        didSet { UserDefaults.standard.set(Int(selectedDisplayID), forKey: "selectedDisplayID") }
    }

    @Published var selectedAppBundleID: String {
        didSet { UserDefaults.standard.set(selectedAppBundleID, forKey: "selectedAppBundleID") }
    }

    // MARK: - Quality

    @Published var resolutionPreset: ResolutionPreset {
        didSet { UserDefaults.standard.set(resolutionPreset.rawValue, forKey: "resolutionPreset") }
    }

    @Published var frameRate: Int {
        didSet { UserDefaults.standard.set(frameRate, forKey: "frameRate") }
    }

    @Published var bitRate: Int {
        didSet { UserDefaults.standard.set(bitRate, forKey: "bitRate") }
    }

    // MARK: - Audio

    @Published var captureSystemAudio: Bool {
        didSet { UserDefaults.standard.set(captureSystemAudio, forKey: "captureSystemAudio") }
    }

    @Published var captureMicrophone: Bool {
        didSet { UserDefaults.standard.set(captureMicrophone, forKey: "captureMicrophone") }
    }

    // MARK: - Storage

    @Published var storageDirectory: URL {
        didSet { UserDefaults.standard.set(storageDirectory.path, forKey: "storageDirectory") }
    }

    @Published var autoCleanupDays: Int {
        didSet { UserDefaults.standard.set(autoCleanupDays, forKey: "autoCleanupDays") }
    }

    // MARK: - Hotkeys

    @Published var saveClipHotkey: HotkeyConfig {
        didSet {
            if let data = try? JSONEncoder().encode(saveClipHotkey) {
                UserDefaults.standard.set(data, forKey: "saveClipHotkey")
            }
        }
    }

    // MARK: - UI

    @Published var appTheme: AppTheme {
        didSet { UserDefaults.standard.set(appTheme.rawValue, forKey: "appTheme") }
    }

    @Published var accentColorIndex: Int {
        didSet { UserDefaults.standard.set(accentColorIndex, forKey: "accentColorIndex") }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            configureLaunchAtLogin(launchAtLogin)
        }
    }

    @Published var showOnscreenHUD: Bool {
        didSet { UserDefaults.standard.set(showOnscreenHUD, forKey: "showOnscreenHUD") }
    }

    @Published var showSaveNotification: Bool {
        didSet { UserDefaults.standard.set(showSaveNotification, forKey: "showSaveNotification") }
    }

    // MARK: - Init

    private init() {
        let defaults = UserDefaults.standard

        bufferDuration = defaults.double(forKey: "bufferDuration").nonZero ?? 30
        captureMode = CaptureConfiguration.CaptureMode(rawValue: defaults.string(forKey: "captureMode") ?? "") ?? .fullScreen
        selectedDisplayID = CGDirectDisplayID(defaults.integer(forKey: "selectedDisplayID")).nonZero ?? CGMainDisplayID()
        selectedAppBundleID = defaults.string(forKey: "selectedAppBundleID") ?? ""
        resolutionPreset = ResolutionPreset(rawValue: defaults.string(forKey: "resolutionPreset") ?? "") ?? .p1080
        frameRate = defaults.integer(forKey: "frameRate").nonZero ?? 60
        bitRate = defaults.integer(forKey: "bitRate").nonZero ?? 8_000_000
        captureSystemAudio = defaults.object(forKey: "captureSystemAudio") as? Bool ?? true
        captureMicrophone = defaults.bool(forKey: "captureMicrophone")
        autoCleanupDays = defaults.integer(forKey: "autoCleanupDays")
        saveClipHotkey = (defaults.data(forKey: "saveClipHotkey").flatMap { try? JSONDecoder().decode(HotkeyConfig.self, from: $0) }) ?? .defaultSaveClip
        appTheme = AppTheme(rawValue: defaults.string(forKey: "appTheme") ?? "") ?? .auto
        accentColorIndex = defaults.integer(forKey: "accentColorIndex")
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        showOnscreenHUD = defaults.object(forKey: "showOnscreenHUD") as? Bool ?? true
        showSaveNotification = defaults.object(forKey: "showSaveNotification") as? Bool ?? true

        // Storage directory
        let storedPath = defaults.string(forKey: "storageDirectory")
        if let path = storedPath, !path.isEmpty {
            storageDirectory = URL(fileURLWithPath: path)
        } else {
            let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Movies")
            storageDirectory = movies.appendingPathComponent("ClipMac Local")
        }

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Capture Configuration Builder

    var captureConfiguration: CaptureConfiguration {
        var config = CaptureConfiguration()
        config.captureMode = captureMode
        config.displayID = selectedDisplayID
        config.applicationBundleID = selectedAppBundleID.isEmpty ? nil : selectedAppBundleID
        config.frameRate = Double(frameRate)
        config.bitRate = bitRate
        let (w, h) = resolutionPreset.dimensions
        config.width = w
        config.height = h
        return config
    }

    // MARK: - Launch at Login

    private func configureLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            // SMAppService handled separately in AppDelegate
        }
    }
}

// MARK: - Resolution Preset

enum ResolutionPreset: String, CaseIterable, Identifiable {
    case p720 = "720p"
    case p1080 = "1080p"
    case p1440 = "1440p"
    case p4K = "4K"

    var id: String { rawValue }

    var dimensions: (Int, Int) {
        switch self {
        case .p720:  return (1280, 720)
        case .p1080: return (1920, 1080)
        case .p1440: return (2560, 1440)
        case .p4K:   return (3840, 2160)
        }
    }
}

// MARK: - App Theme

enum AppTheme: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"
    case auto = "Auto"
    var id: String { rawValue }
}

// MARK: - Helpers

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

private extension CGDirectDisplayID {
    var nonZero: CGDirectDisplayID? { self == 0 ? nil : self }
}
