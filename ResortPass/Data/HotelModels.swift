//
//  HotelModels.swift
//  ResortPass
//

import Foundation

// MARK: - Request Models

struct LocationQuery: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    
    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

struct HotelRequest: Codable, Sendable {
    let location: LocationQuery
    let limit: Int
    let offset: Int
    
    init(location: LocationQuery, limit: Int, offset: Int) {
        self.location = location
        self.limit = limit
        self.offset = offset
    }
}

// MARK: - Response Models

struct HotelResponse: Codable, Sendable {
    let stage: Int?
    let total: Int
    let pages: Int?
    let page: Int?
    let hitsPerPage: Int?
    let offset: Int
    let limit: Int
    let queryID: String?
    let indexName: String?
    let hotels: [Hotel]
    
}

struct Hotel: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    let active: Bool?
    let name: String
    let rating: Double?
    let avgRating: Double?
    let reviews: Int?
    let desktopImg: String?
    let distanceMiles: Double?
    let hotelStar: Int?
    let amenities: [Amenity]?
    let image: [HotelImage]?
    let products: [Product]?
    let cityName: String?
    let stateCode: String?
    let shortDesc: String?
    
    // Custom helper to resolve standard absolute picture URL
    var resolvedImageURL: URL? {
        // For search result list cards, prioritize the mobile-friendly card size ('results')
        if let firstImage = image?.first?.picture {
            print("******WTF is with these hidden images******\n\(firstImage.description)")
            
            var urlString: String? = nil
            if let resultsUrl = firstImage.results?.url, !resultsUrl.isEmpty {
                urlString = resultsUrl
            } else if let detailsUrl = firstImage.details?.url, !detailsUrl.isEmpty {
                urlString = detailsUrl
            } else if !firstImage.url.isEmpty {
                urlString = firstImage.url
            }
            
            if let urlString, !urlString.isEmpty {
                return URL(string: urlString)
            }
        }
        
        // Fallback to desktopImg if not available in image list
        if let desktopImg, !desktopImg.isEmpty {
            return URL(string: desktopImg)
        }
        
        return nil
    }
    
    // Helper to find the main/relevant product info
    var displayProduct: Product? {
        // Return first available product, preferably "Day Pass" or the cheapest product
        return products?.first(where: { $0.availability == "available" }) ?? products?.first
    }
    
    var displayRating: Double {
        if let rating = rating, rating > 0 { return rating }
        if let avgRating = avgRating, avgRating > 0 { return avgRating }
        return 0.0
    }
}

struct Amenity: Codable, Equatable, Sendable {
    let name: String
    let description: String?
    let iconText: String?
}

struct HotelImage: Codable, Equatable, Sendable {
    let picture: Picture?
}

struct Picture: Codable, Equatable, Sendable {
    let url: String
    let results: ResultURL?
    let details: ResultURL?
    
    var description: String {
        "url: \(url)\nresultsUrl: \(results?.url ?? "nil")\ndetailsUrl: \(details?.url ?? "nil"))"
    }
}

struct ResultURL: Codable, Equatable, Sendable {
    let url: String
}

struct Product: Codable, Equatable, Sendable {
    let id: Int
    let name: String
    let price: Double?
    let availability: String?
    let quantity: Int?
    let productTypeName: String?
}
