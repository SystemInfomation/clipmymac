import SwiftUI
import AVKit

// MARK: - Player View

struct PlayerView: View {

    let clip: Clip

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer? = nil
    @State private var isPlaying: Bool = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var playbackSpeed: Float = 1.0
    @State private var volume: Float = 1.0
    @State private var showingControls: Bool = true
    @State private var controlsHideTimer: Timer? = nil
    @State private var isPiPActive: Bool = false
    @State private var timeObserver: Any? = nil

    private let speeds: [Float] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 4.0]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Video player
            if let player = player {
                VideoPlayerView(player: player)
                    .ignoresSafeArea()
            }

            // Gradient overlay at bottom
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
            .opacity(showingControls ? 1 : 0)

            // Controls overlay
            if showingControls {
                VStack(spacing: 0) {
                    // Top bar
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text(clip.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)

                        Spacer()

                        // Share button
                        Button {
                            let picker = NSSharingServicePicker(items: [clip.fileURL])
                            if let window = NSApp.keyWindow {
                                picker.show(relativeTo: .zero, of: window.contentView!, preferredEdge: .minY)
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    Spacer()

                    // Bottom controls
                    VStack(spacing: 12) {
                        // Timeline
                        TimelineSlider(value: $currentTime, duration: duration) { newTime in
                            player?.seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
                        }
                        .padding(.horizontal, 20)

                        // Time labels
                        HStack {
                            Text(formatTime(currentTime))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                            Spacer()
                            Text(formatTime(duration))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 20)

                        // Transport controls
                        HStack(spacing: 20) {
                            // Volume
                            HStack(spacing: 6) {
                                Image(systemName: volume > 0 ? "speaker.wave.2" : "speaker.slash")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.7))
                                Slider(value: $volume, in: 0...1)
                                    .frame(width: 80)
                                    .tint(.white)
                                    .onChange(of: volume) { player?.volume = $0 }
                            }

                            Spacer()

                            // Seek backward
                            Button {
                                let newTime = max(0, currentTime - 5)
                                player?.seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
                            } label: {
                                Image(systemName: "gobackward.5")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)

                            // Play/Pause
                            Button {
                                if isPlaying {
                                    player?.pause()
                                } else {
                                    if currentTime >= duration - 0.1 {
                                        player?.seek(to: .zero)
                                    }
                                    player?.play()
                                }
                                isPlaying.toggle()
                            } label: {
                                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 8)
                            }
                            .buttonStyle(.plain)

                            // Seek forward
                            Button {
                                let newTime = min(duration, currentTime + 5)
                                player?.seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
                            } label: {
                                Image(systemName: "goforward.5")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            // Speed picker
                            Menu("\(speedLabel(playbackSpeed))×") {
                                ForEach(speeds, id: \.self) { speed in
                                    Button("\(speedLabel(speed))×") {
                                        playbackSpeed = speed
                                        player?.rate = isPlaying ? speed : 0
                                    }
                                }
                            }
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 50)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .onAppear { setupPlayer() }
        .onDisappear { teardownPlayer() }
        .onHover { hovering in
            if hovering { showControlsTemporarily() }
        }
        .onTapGesture { showControlsTemporarily() }
        .animation(.easeInOut(duration: 0.2), value: showingControls)
    }

    // MARK: - Setup

    private func setupPlayer() {
        let avPlayer = AVPlayer(url: clip.fileURL)
        self.player = avPlayer

        // Get duration
        Task {
            if let asset = avPlayer.currentItem?.asset {
                let dur = try? await asset.load(.duration)
                DispatchQueue.main.async {
                    self.duration = dur?.seconds ?? 0
                }
            }
        }

        // Time observer
        timeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak avPlayer] time in
            currentTime = time.seconds
            isPlaying = avPlayer?.timeControlStatus == .playing
        }

        // Loop observer
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { _ in
            isPlaying = false
        }

        avPlayer.play()
        isPlaying = true
        showControlsTemporarily()
    }

    private func teardownPlayer() {
        controlsHideTimer?.invalidate()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player?.pause()
        player = nil
    }

    // MARK: - Controls Visibility

    private func showControlsTemporarily() {
        showingControls = true
        controlsHideTimer?.invalidate()
        controlsHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation { showingControls = false }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds)
        let m = s / 60
        let sec = s % 60
        return String(format: "%d:%02d", m, sec)
    }

    private func speedLabel(_ speed: Float) -> String {
        if speed == 1.0 { return "1" }
        if speed == Float(Int(speed)) { return "\(Int(speed))" }
        return String(format: "%.2g", speed)
    }
}

// MARK: - Timeline Slider

private struct TimelineSlider: View {
    @Binding var value: Double
    let duration: Double
    let onSeek: (Double) -> Void

    @State private var isDragging: Bool = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.3))
                    .frame(height: 4)

                // Progress
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white)
                    .frame(width: duration > 0 ? proxy.size.width * CGFloat(value / duration) : 0, height: 4)

                // Thumb
                Circle()
                    .fill(.white)
                    .frame(width: isDragging ? 14 : 10, height: isDragging ? 14 : 10)
                    .offset(x: duration > 0 ? proxy.size.width * CGFloat(value / duration) - (isDragging ? 7 : 5) : 0)
                    .shadow(color: .black.opacity(0.3), radius: 4)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        let newValue = max(0, min(duration, duration * Double(drag.location.x / proxy.size.width)))
                        value = newValue
                        onSeek(newValue)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(height: 20)
        .animation(.easeInOut(duration: 0.1), value: isDragging)
    }
}

// MARK: - VideoPlayerView (NSViewRepresentable)

struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}
