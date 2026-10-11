import CurbsideCore
import Foundation
import SwiftData

/// A recorded drive. The raw sensor log lives in a JSON file (`logFileName`) next to the store.
@Model
final class Drive {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date
    var distanceMeters: Double
    var maxSpeedMps: Double
    var motionSampleCount: Int
    var locationCount: Int
    var calibratedFraction: Double
    var logFileName: String
    // Stored as JSON: SwiftData's handling of arrays of Codable structs with enums is fragile.
    private var eventsData: Data
    private var rejectedData: Data
    private var notesData: Data

    init(id: UUID, startDate: Date, endDate: Date, metrics: DriveMetrics, result: DetectionResult,
         motionSampleCount: Int, locationCount: Int, logFileName: String) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.distanceMeters = metrics.distanceMeters
        self.maxSpeedMps = metrics.maxSpeedMps
        self.motionSampleCount = motionSampleCount
        self.locationCount = locationCount
        self.calibratedFraction = result.calibratedFraction
        self.logFileName = logFileName
        let encoder = JSONEncoder()
        self.eventsData = (try? encoder.encode(result.events)) ?? Data()
        self.rejectedData = (try? encoder.encode(result.rejected)) ?? Data()
        self.notesData = (try? encoder.encode(result.notes)) ?? Data()
    }

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }

    var events: [DrivingEvent] { (try? JSONDecoder().decode([DrivingEvent].self, from: eventsData)) ?? [] }
    var rejected: [RejectedCandidate] { (try? JSONDecoder().decode([RejectedCandidate].self, from: rejectedData)) ?? [] }
    var notes: [DetectorNote] { (try? JSONDecoder().decode([DetectorNote].self, from: notesData)) ?? [] }

    var logURL: URL { DriveFiles.url(for: logFileName) }
}

/// Raw drive logs, stored in Documents/Drives so they also show up in the Files app.
enum DriveFiles {
    static var directory: URL {
        let dir = URL.documentsDirectory.appending(path: "Drives", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for fileName: String) -> URL {
        directory.appending(path: fileName)
    }

    /// Encodes and writes off the main thread. Returns the file name.
    static func write(_ log: DriveLog) async throws -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let name = "drive-\(formatter.string(from: log.startDate))-\(log.driveID.uuidString.prefix(4)).json"
        let url = url(for: name)
        try await Task.detached(priority: .utility) {
            try log.encoded().write(to: url, options: .atomic)
        }.value
        return name
    }

    static func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}

enum DeviceInfo {
    /// e.g. "iPhone16,2".
    static var modelIdentifier: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }

    static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}
