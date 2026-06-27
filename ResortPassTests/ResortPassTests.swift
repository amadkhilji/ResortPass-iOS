//
//  ResortPassTests.swift
//  ResortPassTests
//

import Testing
import UIKit
import CoreLocation
@testable import ResortPass

// MARK: - Mocks

struct MockNetworkClient: NetworkClientProtocol, Sendable {
    let responseData: Data?
    let shouldFail: Bool
    
    init(responseData: Data? = nil, shouldFail: Bool = false) {
        self.responseData = responseData
        self.shouldFail = shouldFail
    }
    
    func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        if shouldFail {
            throw NSError(domain: "Network", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mock connection error"])
        }
        guard let data = responseData else {
            throw NetworkError.noData
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Tests Suite

@MainActor struct ResortPassTests {
    
    // MARK: - Image Cache Tests
    
    @Test func testImageCacheStoreAndRetrieve() async throws {
        let imageCache = ImageCacheManager.shared
        await imageCache.clearAll()
        
        let mockImageURL = "https://example.com/images/pool.jpg"
        let mockImageData = "mock-jpeg-data".data(using: .utf8)!
        
        // Create a mock UIImage
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let mockImage = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        
        await imageCache.set(mockImageData, mockImage, for: mockImageURL)
        
        // Check Memory Cache
        let memoryImage = await imageCache.getFromMemory(for: mockImageURL)
        #expect(memoryImage != nil)
        
        // Check Disk Cache
        let diskData = await imageCache.getFromDisk(for: mockImageURL)
        #expect(diskData == mockImageData)
    }
    
    // MARK: - View Model Tests
    
    @Test func testAutocompleteViewModelDefaultLocations() async throws {
        let viewModel = SearchViewModel(networkClient: MockNetworkClient())
        
        let places = viewModel.places
        let searchQuery = viewModel.searchQuery
        
        #expect(searchQuery.isEmpty)
        #expect(places.count == LocationManager.defaultLocations.count)
        #expect(places.first?.name == "New York, New York")
    }
    
    @Test func testAutocompleteViewModelSearchSuccess() async throws {
        let samplePlaces = [
            Place(
                id: 1,
                name: "Miami Beach, Florida",
                type: "city",
                detailedType: "city",
                url: nil,
                parentId: nil,
                parentType: nil,
                stateCode: "FL",
                countryCode: "US",
                cityName: "Miami Beach",
                latitude: 25.7906,
                longitude: -80.1300,
                distanceSearchOnly: nil,
                indexName: nil,
                objectID: nil,
                queryID: nil
            )
        ]
        
        let jsonData = try JSONEncoder().encode(samplePlaces)
        let mockClient = MockNetworkClient(responseData: jsonData)
        
        let viewModel = SearchViewModel(networkClient: mockClient)
        viewModel.searchQuery = "Miami"
        
        // Perform search
        await viewModel.fetchPlaces(query: "Miami", reset: true)
        
        let places = viewModel.places
        let isLoading = viewModel.isLoading
        let error = viewModel.errorMessage
        
        #expect(places.count == 1)
        #expect(places.first?.name == "Miami Beach, Florida")
        #expect(isLoading == false)
        #expect(error == nil)
    }
    
    @Test func testHotelListViewModelFetchSuccess() async throws {
        let sampleProducts = [
            Product(
                id: 123,
                name: "Day Pass",
                price: 75.0,
                availability: "available",
                quantity: 10,
                productTypeName: "Day Pass"
            )
        ]
        
        let sampleHotels = [
            Hotel(
                id: 1990,
                active: true,
                name: "TWA Hotel",
                rating: 4.5,
                avgRating: 4.5,
                reviews: 120,
                desktopImg: "https://example.com/twa.jpg",
                distanceMiles: 2.5,
                hotelStar: 4,
                amenities: [],
                image: [],
                products: sampleProducts,
                cityName: "Queens",
                stateCode: "NY",
                shortDesc: "Beautiful vintage hotel."
            )
        ]
        
        let response = HotelResponse(
            stage: 1,
            total: 1,
            pages: 1,
            page: 0,
            hitsPerPage: 30,
            offset: 0,
            limit: 30,
            queryID: "mock-query",
            indexName: "mock-index",
            hotels: sampleHotels
        )
        
        let jsonData = try JSONEncoder().encode(response)
        let mockClient = MockNetworkClient(responseData: jsonData)
        
        let viewModel = HotelListViewModel(
            latitude: 40.645,
            longitude: -73.778,
            locationName: "JFK Airport",
            networkClient: mockClient
        )
        
        await viewModel.fetchHotels(reset: true)
        
        let hotels = viewModel.hotels
        let isLoading = viewModel.isLoadingInitial
        let displayProduct = hotels.first?.displayProduct
        
        #expect(hotels.count == 1)
        #expect(hotels.first?.name == "TWA Hotel")
        #expect(displayProduct?.price == 75.0)
        #expect(isLoading == false)
    }
    
    // MARK: - Location Manager Tests
    
    @Test func testLocationManagerDefaults() async throws {
        let locationManager = LocationManager()
        #expect(locationManager.authorizationStatus == .notDetermined)
        #expect(locationManager.userLocation == nil)
    }
    
    // MARK: - Network Client & URLCache Tests
    
    @Test func testNetworkClientSuccess() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = NetworkClient(session: session)
        
        let testData = "{\"id\": 1, \"name\": \"Test Place\"}".data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, testData)
        }
        
        struct DummyModel: Codable {
            let id: Int
            let name: String
        }
        
        let request = URLRequest(url: URL(string: "https://example.com/api/test")!)
        let result: DummyModel = try await client.perform(request)
        
        #expect(result.id == 1)
        #expect(result.name == "Test Place")
    }
    
    @Test func testResortPassURLCacheHeaderInjection() async throws {
        let cache = ResortPassURLCache()
        cache.removeAllCachedResponses()
        
        let url = URL(string: "https://example.com/api/cache-test")!
        let request = URLRequest(url: url)
        
        // 1. Test injection of max-age when Cache-Control is completely missing
        let responseWithoutHeaders = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [:]
        )!
        let cachedResponse = CachedURLResponse(response: responseWithoutHeaders, data: Data("cached-data".utf8))
        cache.storeCachedResponse(cachedResponse, for: request)
        
        let retrieved = cache.cachedResponse(for: request)
        #expect(retrieved != nil)
        
        let httpResponse = retrieved?.response as? HTTPURLResponse
        let cacheControl = httpResponse?.value(forHTTPHeaderField: "Cache-Control")
        #expect(cacheControl == "max-age=300")
        
        // 2. Test that existing Cache-Control is preserved and NOT overwritten
        let responseWithCacheControl = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Cache-Control": "max-age=600"]
        )!
        let cachedResponse2 = CachedURLResponse(response: responseWithCacheControl, data: Data("cached-data-2".utf8))
        cache.storeCachedResponse(cachedResponse2, for: request)
        
        let retrieved2 = cache.cachedResponse(for: request)
        let httpResponse2 = retrieved2?.response as? HTTPURLResponse
        #expect(httpResponse2?.value(forHTTPHeaderField: "Cache-Control") == "max-age=600")
        
        // 3. Test that existing validation indicators like ETag prevent injection
        let responseWithETag = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["ETag": "\"w-12345\""]
        )!
        let cachedResponse3 = CachedURLResponse(response: responseWithETag, data: Data("cached-data-3".utf8))
        cache.storeCachedResponse(cachedResponse3, for: request)
        
        let retrieved3 = cache.cachedResponse(for: request)
        let httpResponse3 = retrieved3?.response as? HTTPURLResponse
        #expect(httpResponse3?.value(forHTTPHeaderField: "Cache-Control") == nil)
        #expect(httpResponse3?.value(forHTTPHeaderField: "ETag") == "\"w-12345\"")
    }
}

// MARK: - Mock URL Protocol for testing NetworkClient

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            return
        }
        
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    override func stopLoading() {}
}
