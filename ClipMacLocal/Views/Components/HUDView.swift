import SwiftUI
import AppKit

// MARK: - HUD Window Manager

/// Floating on-screen HUD showing the save button over other apps.
final class HUDWindowManager {

    private var hudWindow: NSWindow?
    private var hostingView: NSHostingView<HUDView>?

    var onSaveClip: (() -> Void)?

    func show(captureEngine: CaptureEngine, settings: AppSettings) {
        guard hudWindow == nil else { return }

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let windowWidth: CGFloat = 180
        let windowHeight: CGFloat = 64
        let windowX = screenFrame.maxX - windowWidth - 20
        let windowY = screenFrame.minY + 100

        let window = NSWindow(
            contentRect: NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let hudView = HUDView(onSave: { [weak self] in self?.onSaveClip?() })
            .environmentObject(captureEngine)
            .environmentObject(settings)

        let hosting = NSHostingView(rootView: hudView)
        hosting.frame = window.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(hosting)
        self.hostingView = hosting

        window.makeKeyAndOrderFront(nil)
        self.hudWindow = window
    }

    func hide() {
        hudWindow?.close()
        hudWindow = nil
        hostingView = nil
    }

    func toggle(captureEngine: CaptureEngine, settings: AppSettings) {
        if hudWindow != nil {
            hide()
        } else {
            show(captureEngine: captureEngine, settings: settings)
        }
    }
}

// MARK: - HUD View

struct HUDView: View {
    @EnvironmentObject var captureEngine: CaptureEngine
    @EnvironmentObject var settings: AppSettings
    let onSave: () -> Void

    @State private var isHovered: Bool = false
    @State private var isSaving: Bool = false

    var body: some View {
        Button(action: {
            guard !isSaving && captureEngine.isCapturing else { return }
            isSaving = true
            onSave()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { isSaving = false }
        }) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    if captureEngine.isCapturing {
                        Circle()
                            .fill(Color.red.opacity(0.4))
                            .frame(width: 14, height: 14)
                            .scaleEffect(isHovered ? 1.3 : 1.0)
                    }
                }

                if isSaving {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.5)
                        .tint(.white)
                } else {
                    Text("Save \(Int(settings.bufferDuration))s")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(
                        captureEngine.isCapturing
                            ? Color.black.opacity(isHovered ? 0.85 : 0.75)
                            : Color.black.opacity(0.5)
                    )
                    .shadow(color: captureEngine.isCapturing ? .red.opacity(0.4) : .clear, radius: isHovered ? 12 : 6)
            )
            .overlay(
                Capsule()
                    .strokeBorder(captureEngine.isCapturing ? Color.red.opacity(0.6) : Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .disabled(!captureEngine.isCapturing || isSaving)
    }
}
