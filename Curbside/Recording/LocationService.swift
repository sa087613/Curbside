import CoreLocation
import CurbsideCore
import Foundation

/// Wraps CLLocationManager for drive recording. Lives on the main actor because
/// CLLocationManager delivers delegate callbacks on the thread that created it.
@MainActor
final class LocationService: NSObject {
    private let manager = CLLocationManager()
    private var authorizationWaiters: [CheckedContinuation<CLAuthorizationStatus, Never>] = []
    private var referenceDate = Date()
    private var onSample: ((LocationSample) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    /// Shows the "While Using the App" prompt the first time; afterwards returns the current status.
    func requestAuthorizationIfNeeded() async -> CLAuthorizationStatus {
        guard manager.authorizationStatus == .notDetermined else { return manager.authorizationStatus }
        return await withCheckedContinuation { continuation in
            authorizationWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Starts high-accuracy updates. Times are reported relative to `referenceDate`.
    func start(referenceDate: Date, onSample: @escaping (LocationSample) -> Void) {
        self.referenceDate = referenceDate
        self.onSample = onSample
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        onSample = nil
    }

    private func handle(_ locations: [CLLocation]) {
        for location in locations {
            // Core Location often replays a cached fix first; skip anything from before the drive.
            guard location.timestamp >= referenceDate.addingTimeInterval(-2) else { continue }
            onSample?(LocationSample(
                t: location.timestamp.timeIntervalSince(referenceDate),
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracy: location.horizontalAccuracy,
                speed: location.speed,
                speedAccuracy: location.speedAccuracy,
                course: location.course,
                courseAccuracy: location.courseAccuracy
            ))
        }
    }

    private func handleAuthorizationChange() {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        let waiters = authorizationWaiters
        authorizationWaiters.removeAll()
        waiters.forEach { $0.resume(returning: status) }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated { handle(locations) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { handleAuthorizationChange() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient (e.g. kCLErrorLocationUnknown); Core Location keeps trying.
    }
}
