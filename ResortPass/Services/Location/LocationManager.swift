//
//  LocationManager.swift
//  ResortPass
//

import Foundation
import Combine
import CoreLocation

protocol CLLocationManagerProtocol: AnyObject {
    var delegate: CLLocationManagerDelegate? { get set }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestWhenInUseAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
}

extension CLLocationManager: CLLocationManagerProtocol {}

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    private let locationManager: any CLLocationManagerProtocol
    
    init(locationManager: any CLLocationManagerProtocol = CLLocationManager()) {
        self.locationManager = locationManager
        super.init()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        self.authorizationStatus = locationManager.authorizationStatus
    }
    
    func requestLocation() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.locationManager.startUpdatingLocation()
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = location.coordinate
        Task { @MainActor in
            self.userLocation = coordinate
            // Stop GPS after first location lock to save battery
            self.locationManager.stopUpdatingLocation()
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager failed with error: \(error.localizedDescription)")
    }
    
    // MARK: - Default Locations
    
    static var defaultLocations: [Place] {
        return [
            Place(
                id: 1001,
                name: "New York, New York",
                type: "city",
                detailedType: "city",
                url: "/hotel-day-passes/New-York-1001",
                parentId: 38,
                parentType: "state",
                stateCode: "NY",
                countryCode: "US",
                cityName: "New York",
                latitude: 40.7128,
                longitude: -74.0060,
                distanceSearchOnly: false,
                indexName: "staging_locations",
                objectID: "New York, New York",
                queryID: nil
            ),
            Place(
                id: 1007,
                name: "San Francisco, California",
                type: "city",
                detailedType: "city",
                url: "/hotel-day-passes/San-Francisco-1007",
                parentId: 4,
                parentType: "state",
                stateCode: "CA",
                countryCode: "US",
                cityName: "San Francisco",
                latitude: 37.7749,
                longitude: -122.4194,
                distanceSearchOnly: false,
                indexName: "staging_locations",
                objectID: "San Francisco, California",
                queryID: nil
            ),
            Place(
                id: 1004,
                name: "Los Angeles, California",
                type: "city",
                detailedType: "city",
                url: "/hotel-day-passes/Los-Angeles-1004",
                parentId: 4,
                parentType: "state",
                stateCode: "CA",
                countryCode: "US",
                cityName: "Los Angeles",
                latitude: 34.0522,
                longitude: -118.2437,
                distanceSearchOnly: false,
                indexName: "staging_locations",
                objectID: "Los Angeles, California",
                queryID: nil
            ),
            Place(
                id: 1003,
                name: "Las Vegas, Nevada",
                type: "city",
                detailedType: "city",
                url: "/hotel-day-passes/Las-Vegas-1003",
                parentId: 32,
                parentType: "state",
                stateCode: "NV",
                countryCode: "US",
                cityName: "Las Vegas",
                latitude: 36.1716,
                longitude: -115.1391,
                distanceSearchOnly: false,
                indexName: "staging_locations",
                objectID: "Las Vegas, Nevada",
                queryID: nil
            ),
            
            Place(
                id: 1005,
                name: "Honolulu, Hawaii",
                type: "city",
                detailedType: "city",
                url: "/hotel-day-passes/Honolulu-1005",
                parentId: 12,
                parentType: "state",
                stateCode: "HI",
                countryCode: "US",
                cityName: "Honolulu",
                latitude: 21.3069,
                longitude: -157.8583,
                distanceSearchOnly: false,
                indexName: "staging_locations",
                objectID: "Honolulu, Hawaii",
                queryID: nil
            ),
            Place(
                id: 1008,
                name: "Miami, Florida",
                type: "city",
                detailedType: "city",
                url: "/hotel-day-passes/Miami-1008",
                parentId: 10,
                parentType: "state",
                stateCode: "FL",
                countryCode: "US",
                cityName: "Miami",
                latitude: 25.7617,
                longitude: -80.1918,
                distanceSearchOnly: false,
                indexName: "staging_locations",
                objectID: "Miami, Florida",
                queryID: nil
            )
        ]
    }
}

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
