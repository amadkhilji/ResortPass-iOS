//
//  HotelListViewModel.swift
//  ResortPass
//

import Foundation
import Combine

@MainActor
final class HotelListViewModel: ObservableObject {
    @Published var hotels: [Hotel] = []
    @Published var isLoadingInitial: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var errorMessage: String? = nil
    @Published var locationName: String
    
    private let latitude: Double
    private let longitude: Double
    private let networkClient: any NetworkClientProtocol
    
    // Pagination parameters
    private var offset: Int = 0
    private let limit: Int = 30
    private var total: Int = 0
    private var isFetching: Bool = false
    
    var hasMoreHotels: Bool {
        return hotels.count < total
    }
    
    init(
        latitude: Double,
        longitude: Double,
        locationName: String,
        networkClient: (any NetworkClientProtocol)? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.networkClient = networkClient ?? NetworkClient()
    }
    
    func fetchHotels(reset: Bool = false) async {
        guard !isFetching else { return }
        
        if reset {
            offset = 0
            total = 0
        }
        
        if !reset && !hasMoreHotels && !hotels.isEmpty {
            return
        }
        
        isFetching = true
        errorMessage = nil
        
        if reset {
            isLoadingInitial = true
        } else {
            isLoadingMore = true
        }
        
        guard let url = URL(string: APIConstants.Search.hotels) else {
            self.errorMessage = NetworkError.invalidURL.localizedDescription
            self.isLoadingInitial = false
            self.isLoadingMore = false
            self.isFetching = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let query = LocationQuery(latitude: latitude, longitude: longitude)
        let requestBody = HotelRequest(location: query, limit: limit, offset: offset)
        
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(requestBody)
        } catch {
            self.errorMessage = "Failed to prepare request parameters."
            self.isLoadingInitial = false
            self.isLoadingMore = false
            self.isFetching = false
            return
        }
        
        do {
            let response: HotelResponse = try await self.networkClient.perform(request)
            
            if Task.isCancelled {
                self.isLoadingInitial = false
                self.isLoadingMore = false
                self.isFetching = false
                return
            }
            
            self.total = response.total
            
            if reset {
                self.hotels = response.hotels
            } else {
                // Deduplicate to avoid conflicts on UI
                var existingIds = Set(self.hotels.map { $0.id })
                let newUniqueHotels = response.hotels.filter { existingIds.insert($0.id).inserted }
                self.hotels.append(contentsOf: newUniqueHotels)
            }
            
            self.offset = self.hotels.count
            self.isLoadingInitial = false
            self.isLoadingMore = false
            self.isFetching = false
        } catch {
            self.isLoadingInitial = false
            self.isLoadingMore = false
            self.isFetching = false
            
            let isCancellation = error is CancellationError || 
                                 (error as? URLError)?.code == .cancelled ||
                                 (error as NSError).code == NSURLErrorCancelled
            
            if !isCancellation && !Task.isCancelled {
                if reset {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    // Pagination trigger when scrolling
    func loadMoreIfNeeded(for hotel: Hotel) {
        guard hotels.count >= 4 else { return }
        let thresholdIndex = hotels.count - 4
        if let hotelIndex = hotels.firstIndex(where: { $0.id == hotel.id }), hotelIndex >= thresholdIndex {
            Task {
                await fetchHotels(reset: false)
            }
        }
    }
    
    func retryFetch() {
        Task {
            await fetchHotels(reset: true)
        }
    }
}
