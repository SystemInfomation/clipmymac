import Foundation
import CoreMedia

// MARK: - Clip Model

/// Represents a saved video clip in the library.
struct Clip: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var fileURL: URL
    var duration: TimeInterval
    var fileSize: Int64
    var createdAt: Date
    var thumbnailURL: URL?
    var tags: [String] = []

    // MARK: Computed

    var formattedDuration: String {
        let secs = Int(duration)
        if secs < 60 {
            return "\(secs)s"
        }
        let m = secs / 60
        let s = secs % 60
        return String(format: "%d:%02d", m, s)
    }

    var formattedFileSize: String {
        let mb = Double(fileSize) / 1_048_576
        if mb < 1 {
            return String(format: "%.0f KB", mb * 1024)
        } else if mb < 1024 {
            return String(format: "%.1f MB", mb)
        } else {
            return String(format: "%.2f GB", mb / 1024)
        }
    }

    var formattedDate: String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: createdAt, relativeTo: Date())
    }

    // MARK: Coding

    enum CodingKeys: String, CodingKey {
        case id, title, fileURL, duration, fileSize, createdAt, thumbnailURL, tags
    }

    init(id: UUID = UUID(),
         title: String,
         fileURL: URL,
         duration: TimeInterval,
         fileSize: Int64,
         createdAt: Date = Date(),
         thumbnailURL: URL? = nil,
         tags: [String] = []) {
        self.id = id
        self.title = title
        self.fileURL = fileURL
        self.duration = duration
        self.fileSize = fileSize
        self.createdAt = createdAt
        self.thumbnailURL = thumbnailURL
        self.tags = tags
    }
}

// MARK: - Sort Options

enum ClipSortOrder: String, CaseIterable, Identifiable {
    case newest = "Newest First"
    case oldest = "Oldest First"
    case longest = "Longest First"
    case shortest = "Shortest First"
    case largest = "Largest First"
    case smallest = "Smallest First"

    var id: String { rawValue }
}
