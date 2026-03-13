import SwiftUI
import ScreenCaptureKit
import ServiceManagement

// MARK: - Settings View

struct SettingsView: View {

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var captureEngine: CaptureEngine
    @EnvironmentObject var audioEngine: AudioCaptureEngine
    @EnvironmentObject var permissionsManager: PermissionsManager

    @State private var selectedTab: SettingsTab = .capture
    @State private var isPickingFolder: Bool = false

    enum SettingsTab: String, CaseIterable, Identifiable {
        case capture = "Capture"
        case audio = "Audio"
        case storage = "Storage"
        case hotkeys = "Hotkeys"
        case appearance = "Appearance"
        case about = "About"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .capture:    return "display"
            case .audio:      return "waveform"
            case .storage:    return "folder"
            case .hotkeys:    return "keyboard"
            case .appearance: return "paintpalette"
            case .about:      return "info.circle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar tabs
            VStack(alignment: .leading, spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    SettingsTabButton(
                        tab: tab,
                        isSelected: selectedTab == tab
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    }
                }
                Spacer()
            }
            .padding(12)
            .frame(width: 170)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content
            ScrollView {
                Group {
                    switch selectedTab {
                    case .capture:    captureTab
                    case .audio:      audioTab
                    case .storage:    storageTab
                    case .hotkeys:    hotkeysTab
                    case .appearance: appearanceTab
                    case .about:      aboutTab
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 660, height: 500)
    }

    // MARK: - Capture Tab

    private var captureTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(title: "Buffer", icon: "clock.arrow.circlepath")

            VStack(spacing: 16) {
                SettingsRow(label: "Buffer Duration", description: "How many seconds to keep in memory for instant save") {
                    HStack {
                        Slider(value: $settings.bufferDuration, in: 15...120, step: 5)
                            .frame(width: 160)
                        Text("\(Int(settings.bufferDuration))s")
                            .font(.system(size: 13, design: .monospaced))
                            .frame(width: 36)
                    }
                }
            }

            SectionHeader(title: "Quality", icon: "slider.horizontal.3")

            VStack(spacing: 16) {
                SettingsRow(label: "Resolution") {
                    Picker("", selection: $settings.resolutionPreset) {
                        ForEach(ResolutionPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }

                SettingsRow(label: "Frame Rate") {
                    Picker("", selection: $settings.frameRate) {
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }

                SettingsRow(label: "Bitrate", description: "Higher = better quality, larger files") {
                    Picker("", selection: $settings.bitRate) {
                        Text("4 Mbps").tag(4_000_000)
                        Text("8 Mbps").tag(8_000_000)
                        Text("16 Mbps").tag(16_000_000)
                        Text("32 Mbps").tag(32_000_000)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
            }

            SectionHeader(title: "Capture Mode", icon: "desktopcomputer")

            VStack(spacing: 16) {
                SettingsRow(label: "Mode") {
                    Picker("", selection: $settings.captureMode) {
                        ForEach(CaptureConfiguration.CaptureMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }

                if settings.captureMode == .specificApp {
                    SettingsRow(label: "Application") {
                        Picker("", selection: $settings.selectedAppBundleID) {
                            Text("Select app…").tag("")
                            ForEach(captureEngine.availableApps, id: \.bundleIdentifier) { app in
                                Text(app.applicationName).tag(app.bundleIdentifier ?? "")
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)
                    }
                }

                if captureEngine.availableDisplays.count > 1 {
                    SettingsRow(label: "Display") {
                        Picker("", selection: $settings.selectedDisplayID) {
                            ForEach(captureEngine.availableDisplays, id: \.displayID) { display in
                                Text("Display \(display.displayID)").tag(display.displayID)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }
                }
            }

            SectionHeader(title: "Permissions", icon: "lock.shield")

            VStack(spacing: 12) {
                PermissionRow(
                    title: "Screen Recording",
                    status: permissionsManager.screenRecordingStatus
                ) {
                    permissionsManager.openScreenRecordingSettings()
                }
                PermissionRow(
                    title: "Microphone",
                    status: permissionsManager.microphoneStatus
                ) {
                    permissionsManager.openMicrophoneSettings()
                }
            }
        }
    }

    // MARK: - Audio Tab

    private var audioTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(title: "Audio Sources", icon: "speaker.wave.3")

            VStack(spacing: 16) {
                SettingsRow(label: "System Audio", description: "Capture game and application audio") {
                    Toggle("", isOn: $settings.captureSystemAudio)
                        .toggleStyle(.switch)
                }

                Divider()

                SettingsRow(label: "Microphone", description: "Record your voice alongside system audio") {
                    Toggle("", isOn: $settings.captureMicrophone)
                        .toggleStyle(.switch)
                }

                if settings.captureMicrophone {
                    HStack {
                        Text("Level")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Spacer()
                        AudioLevelMeter(level: audioEngine.microphoneLevel)
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    // MARK: - Storage Tab

    private var storageTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(title: "Storage Location", icon: "folder.fill")

            VStack(spacing: 16) {
                SettingsRow(label: "Save Folder") {
                    HStack {
                        Text(settings.storageDirectory.path)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 200, alignment: .leading)

                        Button("Choose…") {
                            isPickingFolder = true
                        }
                        .fileImporter(
                            isPresented: $isPickingFolder,
                            allowedContentTypes: [.folder]
                        ) { result in
                            if case .success(let url) = result {
                                settings.storageDirectory = url
                            }
                        }
                    }
                }

                Divider()

                SettingsRow(label: "Auto-Cleanup", description: "Automatically delete clips older than this many days (0 = never)") {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(settings.autoCleanupDays) },
                            set: { settings.autoCleanupDays = Int($0) }
                        ), in: 0...90, step: 1)
                        .frame(width: 120)
                        Text(settings.autoCleanupDays == 0 ? "Never" : "\(settings.autoCleanupDays)d")
                            .font(.system(size: 13, design: .monospaced))
                            .frame(width: 48)
                    }
                }
            }

            SectionHeader(title: "Launch", icon: "power")

            SettingsRow(label: "Launch at Login", description: "Start ClipMac Local automatically when you log in") {
                Toggle("", isOn: $settings.launchAtLogin)
                    .toggleStyle(.switch)
                    .onChange(of: settings.launchAtLogin) { enabled in
                        configureSMAppService(enabled: enabled)
                    }
            }
        }
    }

    // MARK: - Hotkeys Tab

    private var hotkeysTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(title: "Global Shortcuts", icon: "keyboard.badge.ellipsis")

            VStack(spacing: 16) {
                SettingsRow(label: "Save Clip", description: "Instantly save the last \(Int(settings.bufferDuration)) seconds") {
                    HotkeyBadge(config: settings.saveClipHotkey)
                }
            }

            Text("To change a hotkey, edit the code in HotkeyManager.swift and update the HotkeyConfig.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Appearance Tab

    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(title: "Theme", icon: "circle.lefthalf.filled")

            VStack(spacing: 16) {
                SettingsRow(label: "App Theme") {
                    Picker("", selection: $settings.appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
            }

            SectionHeader(title: "Notifications", icon: "bell.badge")

            VStack(spacing: 16) {
                SettingsRow(label: "Clip Saved Toast", description: "Show a notification when a clip is saved") {
                    Toggle("", isOn: $settings.showSaveNotification)
                        .toggleStyle(.switch)
                }

                SettingsRow(label: "On-Screen HUD", description: "Show a floating save button overlay") {
                    Toggle("", isOn: $settings.showOnscreenHUD)
                        .toggleStyle(.switch)
                }
            }
        }
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(alignment: .center, spacing: 20) {
            Image(systemName: "record.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(colors: [.red, Color(hex: "e94560")], startPoint: .top, endPoint: .bottom)
                )

            VStack(spacing: 6) {
                Text("ClipMac Local")
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Text("Version 1.0.0")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                Text("Free, open-source, and 100% local")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                FeatureRow(icon: "shield.fill", text: "No internet required — all data stays on your Mac")
                FeatureRow(icon: "lock.fill", text: "Zero cloud, zero tracking, zero telemetry")
                FeatureRow(icon: "bolt.fill", text: "Hardware-accelerated with ScreenCaptureKit + Metal")
                FeatureRow(icon: "infinity", text: "Unlimited storage, no subscription needed")
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Launch at Login

    private func configureSMAppService(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("SMAppService error: \(error)")
            }
        }
    }
}

// MARK: - Supporting Components

private struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.accentColor)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }
}

struct SettingsRow<Content: View>: View {
    let label: String
    var description: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                if let desc = description {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 200, alignment: .leading)

            Spacer()

            content()
        }
    }
}

private struct SettingsTabButton: View {
    let tab: SettingsView.SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .frame(width: 18)
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Spacer()
            }
            .foregroundColor(isSelected ? .accentColor : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PermissionRow: View {
    let title: String
    let status: PermissionStatus
    let action: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))

            Spacer()

            switch status {
            case .granted:
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))
            case .denied:
                Button("Open Settings", action: action)
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
            case .notDetermined:
                Text("Not Requested")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HotkeyBadge: View {
    let config: HotkeyConfig

    var body: some View {
        Text(config.displayString)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlColor))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
            )
    }
}

struct AudioLevelMeter: View {
    let level: Float  // 0.0 – 1.0
    private let barCount = 20

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                let threshold = Float(i) / Float(barCount)
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(index: i, threshold: threshold))
                    .frame(width: 4, height: 14)
                    .opacity(level > threshold ? 1.0 : 0.25)
            }
        }
    }

    private func barColor(index: Int, threshold: Float) -> Color {
        if threshold < 0.6 { return .green }
        if threshold < 0.8 { return .yellow }
        return .red
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }
}
