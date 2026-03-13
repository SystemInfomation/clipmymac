import SwiftUI

// MARK: - Clip Thumbnail View

struct ClipThumbnailView: View {
    let clip: Clip
    let isSelected: Bool
    let isHovered: Bool

    @State private var thumbnail: NSImage? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail area
            ZStack(alignment: .bottomTrailing) {
                thumbnailImage
                    .frame(height: 130)
                    .clipped()

                // Duration badge
                Text(clip.formattedDuration)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .padding(8)

                // Play button on hover
                if isHovered {
                    Circle()
                        .fill(.white.opacity(0.9))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.black)
                                .offset(x: 2)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .background(Color(nsColor: .darkGray).opacity(0.3))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 12))

            // Info bar
            VStack(alignment: .leading, spacing: 4) {
                Text(clip.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack {
                    Text(clip.formattedDate)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(clip.formattedFileSize)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 0))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: isSelected ? .accentColor.opacity(0.4) : .black.opacity(isHovered ? 0.25 : 0.12),
                radius: isHovered ? 12 : 6, y: isHovered ? 6 : 3)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onAppear { loadThumbnail() }
    }

    // MARK: - Thumbnail Image

    @ViewBuilder
    private var thumbnailImage: some View {
        if let image = thumbnail {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color(nsColor: .darkGray).opacity(0.2)
                Image(systemName: "film")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary.opacity(0.4))
            }
        }
    }

    // MARK: - Load Thumbnail

    private func loadThumbnail() {
        guard thumbnail == nil, let thumbURL = clip.thumbnailURL else { return }
        DispatchQueue.global(qos: .utility).async {
            if let image = NSImage(contentsOf: thumbURL) {
                DispatchQueue.main.async { self.thumbnail = image }
            }
        }
    }
}
