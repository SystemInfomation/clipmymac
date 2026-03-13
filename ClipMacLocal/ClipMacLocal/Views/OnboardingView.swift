import SwiftUI

// MARK: - Onboarding View

/// Shown at first launch when screen recording permission hasn't been granted.
struct OnboardingView: View {

    @EnvironmentObject var permissionsManager: PermissionsManager
    @State private var animateIcon: Bool = false
    @State private var isRequesting: Bool = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(hex: "1a1a2e"), Color(hex: "16213e"), Color(hex: "0f3460")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // App icon with pulse animation
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.2))
                        .frame(width: 120, height: 120)
                        .scaleEffect(animateIcon ? 1.15 : 1.0)
                        .opacity(animateIcon ? 0.4 : 0.8)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: animateIcon)

                    Circle()
                        .fill(Color(hex: "e94560").opacity(0.9))
                        .frame(width: 88, height: 88)
                        .shadow(color: .red.opacity(0.5), radius: 20)

                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                }
                .padding(.bottom, 32)

                // Title
                Text("Welcome to ClipMac Local")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("Your instant-replay recorder for macOS")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.top, 8)
                    .padding(.bottom, 40)

                // Permission cards
                VStack(spacing: 16) {
                    PermissionCard(
                        icon: "display",
                        title: "Screen Recording",
                        description: "Required to capture your screen content in the background.",
                        status: permissionsManager.screenRecordingStatus,
                        action: {
                            Task { await permissionsManager.requestScreenRecordingPermission() }
                        },
                        openSettings: {
                            permissionsManager.openScreenRecordingSettings()
                        }
                    )

                    PermissionCard(
                        icon: "mic",
                        title: "Microphone (Optional)",
                        description: "Needed only if you want to record your voice alongside screen audio.",
                        status: permissionsManager.microphoneStatus,
                        action: {
                            Task { await permissionsManager.requestMicrophonePermission() }
                        },
                        openSettings: {
                            permissionsManager.openMicrophoneSettings()
                        }
                    )
                }
                .padding(.horizontal, 40)

                Spacer()

                // Continue button
                Button(action: {
                    isRequesting = true
                    Task {
                        await permissionsManager.requestScreenRecordingPermission()
                        isRequesting = false
                    }
                }) {
                    HStack(spacing: 10) {
                        if isRequesting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.7)
                                .tint(.white)
                        }
                        Text(permissionsManager.screenRecordingStatus == .granted ? "Continue to App →" : "Grant Permissions")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        permissionsManager.screenRecordingStatus == .granted
                            ? Color(hex: "4CAF50")
                            : Color(hex: "e94560")
                    )
                    .foregroundColor(.white)
                    .cornerRadius(14)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .disabled(isRequesting)
            }
        }
        .frame(width: 480, height: 600)
        .onAppear { animateIcon = true }
    }
}

// MARK: - Permission Card

private struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let status: PermissionStatus
    let action: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(iconBackground)
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(2)
            }

            Spacer()

            // Status button
            Group {
                switch status {
                case .granted:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.green)
                case .denied:
                    Button("Open Settings", action: openSettings)
                        .buttonStyle(SmallButtonStyle(color: .orange))
                case .notDetermined:
                    Button("Allow", action: action)
                        .buttonStyle(SmallButtonStyle(color: Color(hex: "e94560")))
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var iconBackground: Color {
        switch status {
        case .granted: return .green.opacity(0.2)
        case .denied:  return .orange.opacity(0.2)
        default:       return .white.opacity(0.1)
        }
    }

    private var iconColor: Color {
        switch status {
        case .granted: return .green
        case .denied:  return .orange
        default:       return .white.opacity(0.8)
        }
    }
}

// MARK: - Small Button Style

struct SmallButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1.0))
            .foregroundColor(.white)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
