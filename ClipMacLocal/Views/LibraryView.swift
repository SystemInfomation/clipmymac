import SwiftUI
import AVKit
import UserNotifications

// MARK: - Library View

struct LibraryView: View {

    @EnvironmentObject var library: ClipLibrary
    @EnvironmentObject var captureEngine: CaptureEngine
    @EnvironmentObject var settings: AppSettings

    @State private var selectedClip: Clip? = nil
    @State private var hoveredClipID: UUID? = nil
    @State private var showingPlayer: Bool = false
    @State private var showingDeleteAlert: Bool = false
    @State private var clipToDelete: Clip? = nil
    @State private var selectedClips: Set<UUID> = []
    @State private var columnCount: Int = 3
    @State private var isSaving: Bool = false
    @State private var saveProgress: Double = 0
    @State private var saveErrorMessage: String? = nil

    private let minColumnWidth: CGFloat = 220

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            mainContent
        }
        .navigationTitle("")
        .toolbar { toolbarItems }
        .sheet(isPresented: $showingPlayer) {
            if let clip = selectedClip {
                PlayerView(clip: clip)
                    .frame(minWidth: 900, minHeight: 560)
            }
        }
        .alert("Delete Clip", isPresented: $showingDeleteAlert, presenting: clipToDelete) { clip in
            Button("Delete", role: .destructive) { library.deleteClip(clip) }
            Button("Cancel", role: .cancel) {}
        } message: { clip in
            Text("Are you sure you want to delete \"\(clip.title)\"? This cannot be undone.")
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Stats header
            VStack(alignment: .leading, spacing: 4) {
                Text("ClipMac Local")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                HStack(spacing: 12) {
                    StatBadge(value: "\(library.clips.count)", label: "clips")
                    StatBadge(value: ByteCountFormatter.string(fromByteCount: library.totalSize, countStyle: .file), label: "total")
                }
            }
            .padding(16)

            Divider()

            // Recording status
            RecordingStatusCard(captureEngine: captureEngine, isSaving: $isSaving, saveProgress: $saveProgress)
                .padding(12)

            CaptureControlCard(captureEngine: captureEngine, settings: settings)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

            Divider()

            // Sort order
            VStack(alignment: .leading, spacing: 8) {
                Text("SORT BY")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                ForEach(ClipSortOrder.allCases) { order in
                    SortOrderRow(order: order, isSelected: library.sortOrder == order) {
                        library.sortOrder = order
                    }
                }
            }
            .padding(.bottom, 8)

            Spacer()

            // Save button
            SaveClipButton(isSaving: $isSaving, saveProgress: $saveProgress, saveErrorMessage: $saveErrorMessage)
                .padding(16)
        }
        .frame(width: 220)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Search bar
            SearchBar(text: $library.searchQuery)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            if library.isLoading {
                ProgressView("Loading clips…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if library.displayedClips.isEmpty {
                emptyState
            } else {
                clipGrid
            }
        }
    }

    // MARK: - Clip Grid

    private var clipGrid: some View {
        GeometryReader { proxy in
            let columns = max(1, Int(proxy.size.width / 240))
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns),
                    spacing: 12
                ) {
                    ForEach(library.displayedClips) { clip in
                        ClipThumbnailView(
                            clip: clip,
                            isSelected: selectedClips.contains(clip.id),
                            isHovered: hoveredClipID == clip.id
                        )
                        .onTapGesture {
                            selectedClip = clip
                            showingPlayer = true
                        }
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                hoveredClipID = hovering ? clip.id : nil
                            }
                        }
                        .contextMenu {
                            clipContextMenu(for: clip)
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack")
                .font(.system(size: 52))
                .foregroundColor(.secondary.opacity(0.4))

            VStack(spacing: 8) {
                Text(library.searchQuery.isEmpty ? "No Clips Yet" : "No Results")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)

                Text(library.searchQuery.isEmpty
                     ? "Start recording and press ⌘⇧C to save a clip"
                     : "Try a different search term")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func clipContextMenu(for clip: Clip) -> some View {
        Button {
            selectedClip = clip
            showingPlayer = true
        } label: {
            Label("Play", systemImage: "play.fill")
        }

        Button {
            NSWorkspace.shared.selectFile(clip.fileURL.path, inFileViewerRootedAtPath: clip.fileURL.deletingLastPathComponent().path)
        } label: {
            Label("Show in Finder", systemImage: "finder")
        }

        Button {
            let picker = NSSharingServicePicker(items: [clip.fileURL])
            if let window = NSApp.keyWindow {
                picker.show(relativeTo: .zero, of: window.contentView!, preferredEdge: .minY)
            }
        } label: {
            Label("Share…", systemImage: "square.and.arrow.up")
        }

        Divider()

        Button(role: .destructive) {
            clipToDelete = clip
            showingDeleteAlert = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Text("Library")
                .font(.system(size: 16, weight: .semibold))
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await library.loadFromDisk() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh Library")
        }
    }
}

// MARK: - Recording Status Card

private struct RecordingStatusCard: View {
    @ObservedObject var captureEngine: CaptureEngine
    @Binding var isSaving: Bool
    @Binding var saveProgress: Double

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(captureEngine.isCapturing ? Color.red : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
                .shadow(color: captureEngine.isCapturing ? .red.opacity(0.6) : .clear, radius: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(captureEngine.isCapturing ? "Recording" : "Idle")
                    .font(.system(size: 12, weight: .semibold))
                Text(captureEngine.isCapturing ? "\(Int(captureEngine.framesPerSecond)) fps" : "Not capturing")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isSaving {
                ProgressView(value: saveProgress)
                    .frame(width: 40)
                    .progressViewStyle(.circular)
                    .scaleEffect(0.6)
            }
        }
        .padding(12)
        .background(captureEngine.isCapturing ? Color.red.opacity(0.08) : Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Capture Control Card

private struct CaptureControlCard: View {
    @ObservedObject var captureEngine: CaptureEngine
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Capture Controls")
                    .font(.system(size: 12, weight: .semibold))
                if captureEngine.isStarting {
                    ProgressView()
                        .scaleEffect(0.6)
                }
                Spacer()
                Text(captureEngine.isCapturing ? "Live" : "Stopped")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(captureEngine.isCapturing ? Color.red.opacity(0.15) : Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }

            TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                let buffered = captureEngine.replayBuffer?.bufferedDuration ?? 0
                let maxBuffer = max(settings.bufferDuration, 1)
                let fraction = min(1.0, buffered / maxBuffer)
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                    Text("Buffer: \(Int(buffered))s / \(Int(settings.bufferDuration))s")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 6) {
                StatusPill(label: "System Audio", isOn: settings.captureSystemAudio)
                StatusPill(label: "Mic", isOn: settings.captureMicrophone)
            }

            if let error = captureEngine.captureError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button(action: toggleCapture) {
                    Text(captureEngine.isCapturing ? "Stop" : "Start")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(captureEngine.isCapturing ? Color.red.opacity(0.2) : Color.accentColor.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(captureEngine.isStarting)

                Button("Refresh", action: refreshSources)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(height: 28)
                    .padding(.horizontal, 10)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func toggleCapture() {
        if captureEngine.isCapturing {
            Task { @MainActor in
                await captureEngine.stopCapture()
            }
        } else {
            Task { @MainActor in
                captureEngine.configuration = settings.captureConfiguration
                do {
                    try await captureEngine.startCapture()
                } catch {
                    captureEngine.captureError = error.localizedDescription
                }
            }
        }
    }

    private func refreshSources() {
        Task { @MainActor in
            await captureEngine.refreshAvailableContent()
        }
    }
}

private struct StatusPill: View {
    let label: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isOn ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isOn ? .primary : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Save Clip Button

private struct SaveClipButton: View {
    @EnvironmentObject var captureEngine: CaptureEngine
    @EnvironmentObject var library: ClipLibrary
    @EnvironmentObject var settings: AppSettings
    @Binding var isSaving: Bool
    @Binding var saveProgress: Double
    @Binding var saveErrorMessage: String?

    var body: some View {
        VStack(spacing: 8) {
            if let error = saveErrorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button(action: saveClip) {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                            .tint(.white)
                    } else {
                        Image(systemName: "scissors")
                    }
                    Text(isSaving ? "Saving…" : "Save Last \(Int(settings.bufferDuration))s")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(captureEngine.isCapturing ? Color.accentColor : Color.secondary.opacity(0.3))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(!captureEngine.isCapturing || isSaving)
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }
    }

    private func saveClip() {
        guard !isSaving else { return }
        isSaving = true
        saveErrorMessage = nil
        saveProgress = 0

        Task {
            do {
                let url = try await captureEngine.replayBuffer?.exportClip(
                    lastSeconds: settings.bufferDuration,
                    configuration: settings.captureConfiguration,
                    progress: { p in
                        Task { @MainActor in saveProgress = p }
                    }
                )
                if let url = url {
                    _ = try await library.addClip(from: url, duration: settings.bufferDuration)
                    if settings.showSaveNotification {
                        sendSaveNotification()
                    }
                }
                await MainActor.run { isSaving = false }
            } catch {
                await MainActor.run {
                    saveErrorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }

    private func sendSaveNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Clip Saved!"
        content.body = "Last \(Int(settings.bufferDuration))s saved to \(settings.storageDirectory.lastPathComponent)"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Sort Order Row

private struct SortOrderRow: View {
    let order: ClipSortOrder
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(order.rawValue)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .accentColor : .primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat Badge

private struct StatBadge: View {
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 14))

            TextField("Search clips…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}
