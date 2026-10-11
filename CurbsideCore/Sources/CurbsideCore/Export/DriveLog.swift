import Foundation

/// Everything recorded during one drive. This is the debug export format and the input
/// to the replay harness.
public struct DriveLog: Codable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var driveID: UUID
    public var startDate: Date
    public var endDate: Date
    public var deviceModel: String
    public var appVersion: String
    /// Config the app used live. Optional so old exports still load after config fields change.
    public var config: DetectionConfig?
    /// Events the app found live, for comparison with a replay.
    public var liveEvents: [DrivingEvent]?
    public var locations: [LocationSample]
    public var motion: [MotionSample]

    public init(driveID: UUID, startDate: Date, endDate: Date, deviceModel: String, appVersion: String,
                config: DetectionConfig?, liveEvents: [DrivingEvent]?,
                locations: [LocationSample], motion: [MotionSample]) {
        self.formatVersion = Self.currentFormatVersion
        self.driveID = driveID
        self.startDate = startDate
        self.endDate = endDate
        self.deviceModel = deviceModel
        self.appVersion = appVersion
        self.config = config
        self.liveEvents = liveEvents
        self.locations = locations
        self.motion = motion
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, driveID, startDate, endDate, deviceModel, appVersion, config, liveEvents, locations, motion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decode(Int.self, forKey: .formatVersion)
        driveID = try c.decode(UUID.self, forKey: .driveID)
        startDate = try c.decode(Date.self, forKey: .startDate)
        endDate = try c.decode(Date.self, forKey: .endDate)
        deviceModel = try c.decodeIfPresent(String.self, forKey: .deviceModel) ?? "unknown"
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion) ?? "unknown"
        // Tolerate older/newer shapes: these are informational only.
        config = try? c.decodeIfPresent(DetectionConfig.self, forKey: .config)
        liveEvents = try? c.decodeIfPresent([DrivingEvent].self, forKey: .liveEvents)
        locations = try c.decode([LocationSample].self, forKey: .locations)
        motion = try c.decode([MotionSample].self, forKey: .motion)
    }

    public static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    public static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public func encoded() throws -> Data { try Self.makeEncoder().encode(self) }

    public static func decode(_ data: Data) throws -> DriveLog { try makeDecoder().decode(DriveLog.self, from: data) }

    /// Runs this drive through the detector.
    public func detect(config: DetectionConfig = .default, signalTap: ((SignalFrame) -> Void)? = nil) -> DetectionResult {
        EventDetector.run(locations: locations, motion: motion, config: config, signalTap: signalTap)
    }
}

/// Basic distance/speed stats from GPS.
public struct DriveMetrics: Codable, Sendable, Equatable {
    public var distanceMeters: Double
    public var durationSeconds: Double
    public var maxSpeedMps: Double

    public var distanceMiles: Double { distanceMeters / Units.metersPerMile }

    public init(distanceMeters: Double, durationSeconds: Double, maxSpeedMps: Double) {
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.maxSpeedMps = maxSpeedMps
    }

    /// Sums distance between accurate fixes, skipping jumps that imply impossible speeds.
    public static func compute(locations: [LocationSample], duration: Double,
                               maxAccuracyMeters: Double = 25) -> DriveMetrics {
        var distance = 0.0
        var maxSpeed = 0.0
        var previous: LocationSample?
        for s in locations where s.horizontalAccuracy >= 0 && s.horizontalAccuracy <= maxAccuracyMeters {
            if s.hasValidSpeed { maxSpeed = max(maxSpeed, s.speed) }
            if let p = previous {
                let d = haversineMeters(lat1: p.latitude, lon1: p.longitude, lat2: s.latitude, lon2: s.longitude)
                let dt = s.t - p.t
                // A jump implying > 70 m/s is a bad fix: skip it and measure from the last good one.
                guard dt > 0, d / dt < 70 else { continue }
                distance += d
            }
            previous = s
        }
        return DriveMetrics(distanceMeters: distance, durationSeconds: duration, maxSpeedMps: maxSpeed)
    }
}
