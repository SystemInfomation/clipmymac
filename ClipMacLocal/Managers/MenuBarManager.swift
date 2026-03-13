import Foundation
import AppKit
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.clipmaclocal", category: "MenuBarManager")

// MARK: - Menu Bar Manager

/// Manages the menu bar status item with live recording indicator.
@MainActor
final class MenuBarManager: ObservableObject {

    // MARK: Private

    private var statusItem: NSStatusItem?
    private var statusBarMenu: NSMenu?
    private var pulseTimer: Timer?
    private var isDotVisible: Bool = true

    // MARK: Callbacks

    var onSaveClip: (() -> Void)?
    var onOpenLibrary: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onToggleCapture: (() -> Void)?

    // MARK: - Setup

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        updateIcon(isRecording: false, bufferSeconds: 0)
    }

    // MARK: - Update Icon

    func updateIcon(isRecording: Bool, bufferSeconds: Double) {
        guard let button = statusItem?.button else { return }

        if isRecording {
            // Build attributed title with red dot + seconds
            if isDotVisible {
                let title = NSMutableAttributedString()
                let dotAttrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor.systemRed,
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
                ]
                title.append(NSAttributedString(string: "⏺ ", attributes: dotAttrs))
                let secondsAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                ]
                title.append(NSAttributedString(string: "\(Int(bufferSeconds))s", attributes: secondsAttrs))
                button.attributedTitle = title
            } else {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                ]
                button.attributedTitle = NSAttributedString(string: " \(Int(bufferSeconds))s", attributes: attrs)
            }
        } else {
            // Static icon when not recording
            if let image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "ClipMac") {
                image.isTemplate = true
                button.image = image
                button.title = ""
                button.attributedTitle = NSAttributedString(string: "")
            }
        }
    }

    // MARK: - Pulse Animation

    func startPulseAnimation() {
        pulseTimer?.invalidate()
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isDotVisible.toggle()
            }
        }
    }

    func stopPulseAnimation() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        isDotVisible = true
    }

    // MARK: - Build Menu

    func buildMenu() {
        let menu = NSMenu()

        // Header item
        let headerItem = NSMenuItem()
        headerItem.title = "ClipMac Local"
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())

        // Save clip
        let saveItem = NSMenuItem(title: "Save Last Clip  ⌘⇧C", action: #selector(menuSaveClip), keyEquivalent: "")
        saveItem.target = self
        menu.addItem(saveItem)

        // Toggle capture
        let toggleItem = NSMenuItem(title: "Stop Recording", action: #selector(menuToggleCapture), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.tag = 100
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        // Open Library
        let libraryItem = NSMenuItem(title: "Open Library…", action: #selector(menuOpenLibrary), keyEquivalent: "l")
        libraryItem.keyEquivalentModifierMask = [.command]
        libraryItem.target = self
        menu.addItem(libraryItem)

        // Settings
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit ClipMac Local", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        statusItem?.menu = menu
        self.statusBarMenu = menu
    }

    func updateMenuRecordingState(isRecording: Bool) {
        guard let menu = statusBarMenu,
              let toggleItem = menu.item(withTag: 100) else { return }
        toggleItem.title = isRecording ? "Stop Recording" : "Start Recording"
    }

    // MARK: - Menu Actions

    @objc private func menuSaveClip() {
        onSaveClip?()
    }

    @objc private func menuToggleCapture() {
        onToggleCapture?()
    }

    @objc private func menuOpenLibrary() {
        onOpenLibrary?()
    }

    @objc private func menuOpenSettings() {
        onOpenSettings?()
    }
}
