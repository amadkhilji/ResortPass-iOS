//
//  SearchViewModel.swift
//  ResortPass
//

import Foundation
import Combine
import CoreLocation
import MapKit

@MainActor
protocol SearchViewModelProtocol: ObservableObject {
    var searchQuery: String { get set }
    var popularPlaces: [Place] { get set }
    var nearbyPlaces: [Place] { get set }
    var searchResults: [Place] { get set }
    var isLoading: Bool { get set }
    var errorMessage: String? { get set }
    var places: [Place] { get }
    
    func loadNearbyLocations(latitude: Double, longitude: Double) async
    func fetchPlaces(query: String, reset: Bool) async
    func loadMoreIfNeeded(for place: Place)
    func retrySearch()
}

@MainActor
final class SearchViewModel: SearchViewModelProtocol {
    @Published var searchQuery: String = ""
    
    @Published var popularPlaces: [Place] = []
    @Published var nearbyPlaces: [Place] = []
    @Published var searchResults: [Place] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    // Computed property, dynamically return correct places
    var places: [Place] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return searchResults
        } else {
            return nearbyPlaces.isEmpty ? popularPlaces : nearbyPlaces
        }
    }
    
    private let networkClient: any NetworkClientProtocol
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    // Pagination attributes
    private var currentPage: Int = 0
    private let limit: Int = 10
    private var hasMorePages: Bool = true
    private var isFetchingPage: Bool = false
    
    init(networkClient: (any NetworkClientProtocol)? = nil) {
        self.networkClient = networkClient ?? NetworkClient()
        self.popularPlaces = LocationManager.defaultLocations
        
        setupSearchPipeline()
    }
    
    private func setupSearchPipeline() {
        $searchQuery
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .handleEvents(receiveOutput: { [weak self] trimmed in
                guard let self else { return }
                if trimmed.isEmpty {
                    self.searchTask?.cancel()
                    self.searchResults = []
                    self.isLoading = false
                    self.errorMessage = nil
                    self.hasMorePages = false
                } else {
                    self.isLoading = true
                    self.errorMessage = nil
                }
            })
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] trimmed in
                guard let self else { return }
                guard !trimmed.isEmpty else { return }
                self.searchTask?.cancel()
                self.searchTask = Task {
                    await self.fetchPlaces(query: trimmed, reset: true)
                }
            }
            .store(in: &cancellables)
    }
    
    func loadNearbyLocations(latitude: Double, longitude: Double) async {
        // Avoid overwriting if user has already typed a query
        guard searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let city: String?
        
        if #available(iOS 26.0, *) {
            let location = CLLocation(latitude: latitude, longitude: longitude)
            if let request = MKReverseGeocodingRequest(location: location) {
                do {
                    let mapItems = try await request.mapItems
                    city = mapItems.first?.addressRepresentations?.cityName
                } catch {
                    print("MapKit reverse geocoding failed: \(error.localizedDescription)")
                    city = nil
                }
            } else {
                city = nil
            }
        } else {
            let geocoder = CLGeocoder()
            let location = CLLocation(latitude: latitude, longitude: longitude)
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                city = placemarks.first?.locality
            } catch {
                print("CLGeocoder reverse geocoding failed: \(error.localizedDescription)")
                city = nil
            }
        }
        
        guard let resolvedCity = city, !resolvedCity.isEmpty else {
            self.nearbyPlaces = []
            return
        }
        
        do {
            let urlString = "\(APIConstants.Search.autocomplete)?terms=\(resolvedCity.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? resolvedCity)&limit=\(limit)&offset=0"
            
            guard let url = URL(string: urlString) else {
                self.nearbyPlaces = []
                return
            }
            
            let request = URLRequest(url: url)
            let fetchedPlaces: [Place] = try await networkClient.perform(request)
            
            guard searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            
            var uniqueFetchedPlaces: [Place] = []
            var fetchedIds = Set<Int>()
            for place in fetchedPlaces {
                guard place.latitude != nil, place.longitude != nil else { continue }
                if fetchedIds.insert(place.id).inserted {
                    uniqueFetchedPlaces.append(place)
                }
            }
            
            self.nearbyPlaces = uniqueFetchedPlaces
        } catch {
            print("Nearby search fetch failed: \(error.localizedDescription)")
            guard searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            self.nearbyPlaces = []
        }
    }
    
    func fetchPlaces(query: String, reset: Bool) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !reset {
            guard !isFetchingPage else { return }
        }
        
        // Ensure the fetch query matches what's currently in the search input
        guard trimmedQuery == searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return
        }
        
        if reset {
            currentPage = 0
            hasMorePages = true
            isFetchingPage = false
        }
        
        guard hasMorePages else { return }
        isFetchingPage = true
        
        if reset {
            isLoading = true
        }
        errorMessage = nil
        
        let offset = currentPage * limit
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "\(APIConstants.Search.autocomplete)?terms=\(encodedQuery)&limit=\(limit)&offset=\(offset)"
        
        guard let url = URL(string: urlString) else {
            self.errorMessage = NetworkError.invalidURL.localizedDescription
            self.isLoading = false
            self.isFetchingPage = false
            return
        }
        
        let request = URLRequest(url: url)
        
        do {
            let fetchedPlaces: [Place] = try await networkClient.perform(request)
            
            if Task.isCancelled || trimmedQuery != searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) {
                if trimmedQuery == searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) {
                    isLoading = false
                    isFetchingPage = false
                }
                return
            }
            
            hasMorePages = fetchedPlaces.count >= limit
            
            var uniqueFetchedPlaces: [Place] = []
            var fetchedIds = Set<Int>()
            for place in fetchedPlaces {
                guard place.latitude != nil, place.longitude != nil else { continue }
                if fetchedIds.insert(place.id).inserted {
                    uniqueFetchedPlaces.append(place)
                }
            }
            
            if reset {
                self.searchResults = uniqueFetchedPlaces
            } else {
                var existingIds = Set(self.searchResults.map { $0.id })
                let newUniquePlaces = uniqueFetchedPlaces.filter { existingIds.insert($0.id).inserted }
                self.searchResults.append(contentsOf: newUniquePlaces)
            }
            
            currentPage += 1
            isLoading = false
            isFetchingPage = false
        } catch {
            let isCancellation = error is CancellationError || 
                                 (error as? URLError)?.code == .cancelled ||
                                 (error as NSError).code == NSURLErrorCancelled
            
            if isCancellation || Task.isCancelled || trimmedQuery != searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) {
                if trimmedQuery == searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) {
                    isLoading = false
                    isFetchingPage = false
                }
                return
            }
            
            if reset {
                self.errorMessage = error.localizedDescription
            }
            isLoading = false
            isFetchingPage = false
        }
    }
    
    // Pagination trigger when scrolling
    func loadMoreIfNeeded(for place: Place) {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Default locations are not paginated
            return
        }
        
        guard places.count >= 2 else { return }
        let thresholdIndex = places.count - 2
        if let placeIndex = places.firstIndex(where: { $0.id == place.id }), placeIndex >= thresholdIndex {
            Task {
                await fetchPlaces(query: searchQuery, reset: false)
            }
        }
    }
    
    func retrySearch() {
        searchTask?.cancel()
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            searchTask = Task {
                await fetchPlaces(query: trimmed, reset: true)
            }
        } else {
            self.searchResults = []
            self.isLoading = false
            self.errorMessage = nil
            self.hasMorePages = false
        }
    }
}
