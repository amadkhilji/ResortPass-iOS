//
//  APIConstants.swift
//  ResortPass
//

import Foundation

enum APIConstants {
    static let baseURL = "https://staging-app.resortpass.com/api"
    
    enum Search {
        static let autocomplete = "\(APIConstants.baseURL)/search/places/autocomplete"
        static let hotels = "\(APIConstants.baseURL)/search/algolia_hotels_v7"
    }
}
