//
//  LocationStore.swift
//  City Cemetery
//
//  Where the phone is and which way it faces, for the blue dot and the
//  walk-to arrow. Only runs while a map or a walk is on screen.
//

import Foundation
import CoreLocation
import Observation

@MainActor
@Observable
final class LocationStore: NSObject, CLLocationManagerDelegate {
    private(set) var location: CLLocation?
    /// Degrees from true north the phone's top points.
    private(set) var heading: Double?
    private(set) var status: CLAuthorizationStatus = .notDetermined
    private let manager = CLLocationManager()
    private var users = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 1
        manager.headingFilter = 2
        status = manager.authorizationStatus
    }

    var isAuthorized: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }
    var isDenied: Bool { status == .denied || status == .restricted }

    func request() {
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    /// Balanced start/stop so two screens can share the fix.
    func start() {
        users += 1
        request()
        guard users == 1 else { return }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            status = s
            if isAuthorized, users > 0 {
                manager.startUpdatingLocation()
                if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        Task { @MainActor in location = l }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in heading = h }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    // MARK: - Geometry

    static func distance(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Initial bearing from a to b, degrees clockwise from north.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    /// "85 ft", "0.3 mi" — the walking scale.
    static func distanceText(_ meters: CLLocationDistance) -> String {
        let feet = meters * 3.28084
        if feet < 1000 { return "\(Int(feet.rounded())) ft" }
        let miles = meters / 1609.344
        return String(format: miles < 10 ? "%.1f mi" : "%.0f mi", miles)
    }
}
