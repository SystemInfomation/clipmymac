import Foundation
import AVFoundation
import AppKit
import OSLog

private let logger = Logger(subsystem: "com.clipmaclocal", category: "ClipLibrary")

// MARK: - ClipLibrary

/// Observable library of saved clips with persistence and auto-cleanup.
@MainActor
final class ClipLibrary: ObservableObject {

    // MARK: Published

    @Published var clips: [Clip] = []
    @Published var isLoading: Bool = false
    @Published var searchQuery: String = ""
    @Published var sortOrder: ClipSortOrder = .newest

    // MARK: Private

    private let storageDirectory: URL
    private let metadataFile: URL
    private let thumbnailQueue = DispatchQueue(label: "com.clipmaclocal.thumbnails", qos: .utility)

    // MARK: Init

    init(storageDirectory: URL) {
        self.storageDirectory = storageDirectory
        self.metadataFile = storageDirectory.appendingPathComponent(".metadata.json")
        Task { await self.loadFromDisk() }
    }

    // MARK: Filtered / Sorted Clips

    var displayedClips: [Clip] {
        var result = clips
        if !searchQuery.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchQuery) ||
                $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchQuery) })
            }
        }
        switch sortOrder {
        case .newest:  result.sort { $0.createdAt > $1.createdAt }
        case .oldest:  result.sort { $0.createdAt < $1.createdAt }
        case .longest: result.sort { $0.duration > $1.duration }
        case .shortest: result.sort { $0.duration < $1.duration }
        case .largest: result.sort { $0.fileSize > $1.fileSize }
        case .smallest: result.sort { $0.fileSize < $1.fileSize }
        }
        return result
    }

    // MARK: Add Clip

    /// Adds a saved clip to the library after generating its thumbnail.
    func addClip(from sourceURL: URL, duration: TimeInterval) async throws -> Clip {
        let fileSize = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
        let title = "Clip \(DateFormatter.clipTitle.string(from: Date()))"
        let destURL = storageDirectory.appendingPathComponent(sourceURL.lastPathComponent)

        // Move file to library directory
        if sourceURL != destURL {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: sourceURL, to: destURL)
        }

        // Generate thumbnail asynchronously
        let thumbURL = await generateThumbnail(for: destURL)

        let clip = Clip(
            title: title,
            fileURL: destURL,
            duration: duration,
            fileSize: fileSize,
            thumbnailURL: thumbURL
        )
        clips.insert(clip, at: 0)
        saveToDisk()
        return clip
    }

    // MARK: Delete

    func deleteClip(_ clip: Clip) {
        clips.removeAll { $0.id == clip.id }
        try? FileManager.default.removeItem(at: clip.fileURL)
        if let thumbURL = clip.thumbnailURL {
            try? FileManager.default.removeItem(at: thumbURL)
        }
        saveToDisk()
    }

    func deleteClips(_ clipsToDelete: [Clip]) {
        for clip in clipsToDelete { deleteClip(clip) }
    }

    // MARK: Auto-Cleanup

    func performAutoCleanup(olderThan days: Int) {
        guard days > 0 else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let old = clips.filter { $0.createdAt < cutoff }
        deleteClips(old)
        logger.info("Auto-cleanup removed \(old.count) clips older than \(days) days")
    }

    // MARK: Thumbnail Generation

    private func generateThumbnail(for videoURL: URL) async -> URL? {
        return await withCheckedContinuation { continuation in
            thumbnailQueue.async {
                let asset = AVURLAsset(url: videoURL)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 320, height: 180)

                let time = CMTime(seconds: 0.5, preferredTimescale: 600)
                do {
                    let result = try generator.copyCGImage(at: time, actualTime: nil)
                    let nsImage = NSImage(cgImage: result, size: NSSize(width: 320, height: 180))
                    let thumbURL = videoURL.deletingPathExtension().appendingPathExtension("jpg")
                    if let tiffData = nsImage.tiffRepresentation,
                       let bitmapRep = NSBitmapImageRep(data: tiffData),
                       let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                        try? jpegData.write(to: thumbURL)
                        continuation.resume(returning: thumbURL)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    logger.error("Thumbnail generation failed: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: Persistence

    func loadFromDisk() async {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? Data(contentsOf: metadataFile),
              let saved = try? JSONDecoder().decode([Clip].self, from: data) else {
            // Scan directory for any existing MP4 files
            await scanDirectoryForClips()
            return
        }
        // Filter out clips whose files no longer exist
        clips = saved.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
    }

    private func scanDirectoryForClips() async {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey], options: [.skipsHiddenFiles]) else { return }
        let videoFiles = contents.filter { $0.pathExtension.lowercased() == "mp4" }
        var scanned: [Clip] = []
        for url in videoFiles {
            let attrs = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            let size = Int64(attrs?.fileSize ?? 0)
            let date = attrs?.creationDate ?? Date()
            let asset = AVURLAsset(url: url)
            let duration = try? await asset.load(.duration)
            let thumb = await generateThumbnail(for: url)
            let clip = Clip(
                title: url.deletingPathExtension().lastPathComponent,
                fileURL: url,
                duration: duration?.seconds ?? 0,
                fileSize: size,
                createdAt: date,
                thumbnailURL: thumb
            )
            scanned.append(clip)
        }
        clips = scanned.sorted { $0.createdAt > $1.createdAt }
        saveToDisk()
    }

    func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(clips)
            try data.write(to: metadataFile, options: .atomicWrite)
        } catch {
            logger.error("Failed to save library metadata: \(error.localizedDescription)")
        }
    }

    // MARK: Total Stats

    var totalSize: Int64 { clips.reduce(0) { $0 + $1.fileSize } }
    var totalDuration: TimeInterval { clips.reduce(0) { $0 + $1.duration } }
}

// MARK: - Date Formatter Helper

private extension DateFormatter {
    static let clipTitle: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return fmt
    }()
}
