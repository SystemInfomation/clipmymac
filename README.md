# ClipMac Local

A **100% offline, local-only** instant-replay screen recorder for macOS — a free, open-source alternative to ClipMac.com, designed with zero cloud dependency, unlimited storage, and premium macOS design.

## Features

- 🎬 **Always-on background recording** using ScreenCaptureKit + Metal hardware acceleration
- ⏪ **Rolling replay buffer** — keeps the last 15–120 seconds in RAM (default: 30s)
- ⌨️ **Global hotkey** (⌘⇧C by default) instantly saves the last N seconds as a high-quality MP4
- 🎵 **Full system audio capture** + optional microphone input, mixed into the final MP4
- 🖥️ **Multi-display support** — capture full screen, a specific app, or a specific window
- 📚 **Beautiful clip library** with thumbnail grid, hover zoom, search, sort, and drag-and-drop
- 🎞️ **Built-in player** with timeline scrubbing, speed control (0.25×–4×), and PiP support
- 🔔 **Notification center** toast on save with clip details
- ⚙️ **Rich settings** panel: buffer length, quality presets, audio controls, hotkeys, storage, appearance
- 🚀 **Launch at login** via SMAppService (macOS 13+)
- 🍎 **100% local** — no accounts, no internet, no telemetry, no subscription

## Requirements

- **macOS 14.0 Sonoma** or later (macOS 15 Sequoia supported)
- **Xcode 16.0** or later
- Apple Silicon (M1/M2/M3/M4) or Intel Mac
- Screen Recording permission (prompted on first launch)

## Building

### 1. Clone the repository

```bash
git clone https://github.com/SystemInfomation/clipmymac.git
cd clipmymac
```

### 2. Open in Xcode

```bash
open ClipMacLocal.xcodeproj
```

### 3. Configure Signing

1. In Xcode, select the **ClipMacLocal** target
2. Under **Signing & Capabilities**, select your Team
3. Xcode will automatically manage provisioning profiles

### 4. Build and Run

Press **⌘R** to build and run.

## Permissions Setup

### Screen Recording (Required)

On first launch, ClipMac Local will show the onboarding screen and request screen recording access. If denied, a one-click button opens **System Settings → Privacy & Security → Screen Recording**.

To manually grant:
```
System Settings → Privacy & Security → Screen Recording → ClipMac Local ✓
```

### Microphone (Optional)

Enable in **Settings → Audio → Microphone**:
```
System Settings → Privacy & Security → Microphone → ClipMac Local ✓
```

## Testing Permissions

Reset permissions in Terminal to test the onboarding flow:

```bash
tccutil reset ScreenCapture com.clipmaclocal.app
tccutil reset Microphone com.clipmaclocal.app
```

## Project Structure

```
clipmymac/
├── ClipMacLocal.xcodeproj/        # Xcode project
├── ClipMacLocalTests/             # Unit tests
└── ClipMacLocal/
    ├── App/
    │   ├── ClipMacLocalApp.swift  # SwiftUI @main entry point
    │   ├── AppDelegate.swift      # NSApplicationDelegate, wires all components
    │   └── Extensions.swift       # Color(hex:), NSImage extensions
    ├── Engine/
    │   ├── CaptureEngine.swift    # ScreenCaptureKit stream management
    │   ├── ReplayBuffer.swift     # Circular ring buffer + AVAssetWriter export
    │   └── AudioCaptureEngine.swift # AVAudioEngine microphone capture
    ├── Models/
    │   ├── Clip.swift             # Clip data model (Codable)
    │   ├── ClipLibrary.swift      # Library persistence + thumbnail generation
    │   └── AppSettings.swift      # UserDefaults-backed settings
    ├── Managers/
    │   ├── PermissionsManager.swift # Screen + mic permission handling
    │   ├── MenuBarManager.swift   # NSStatusItem + pulsing red dot
    │   └── HotkeyManager.swift    # Carbon EventHotKey global shortcuts
    ├── Views/
    │   ├── ContentView.swift      # Main window (library or onboarding)
    │   ├── LibraryView.swift      # NavigationSplitView clip grid
    │   ├── PlayerView.swift       # Full-screen AVPlayer with custom controls
    │   ├── SettingsView.swift     # Tabbed settings panel
    │   ├── OnboardingView.swift   # First-run permission request UI
    │   └── Components/
    │       ├── ClipThumbnailView.swift # Grid card with hover effects
    │       └── HUDView.swift          # Floating on-screen HUD button
    └── Resources/
        ├── Info.plist
        ├── ClipMacLocal.entitlements
        └── Assets.xcassets/
```

## Performance Tips

### Apple Silicon (M-series)
- ScreenCaptureKit uses the Apple Silicon media engine for hardware encoding
- The replay buffer uses `<200 MB RAM` even at 4K 60 fps

### Intel Macs
- HEVC encoding falls back to CPU; change `AVVideoCodecType.hevc` to `.h264` in `ReplayBuffer.swift`
- Lower the bitrate (e.g., 4 Mbps) if you notice CPU spikes

## Customizing the Hotkey

Edit `HotkeyManager.swift`:

```swift
static let defaultSaveClip = HotkeyConfig(
    keyCode: UInt32(kVK_ANSI_C),
    modifiers: UInt32(cmdKey | shiftKey)   // ⌘⇧C
)
```

## License

MIT License — free to use, modify, and distribute.

---

*ClipMac Local is not affiliated with or endorsed by ClipMac.com. This is an independent open-source project.*
