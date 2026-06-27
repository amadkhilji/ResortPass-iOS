//
//  PlacesModels.swift
//  ResortPass
//

import Foundation

struct Place: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    let name: String
    let type: String?
    let detailedType: String?
    let url: String?
    let parentId: Int?
    let parentType: String?
    let stateCode: String?
    let countryCode: String?
    let cityName: String?
    let latitude: Double?
    let longitude: Double?
    let distanceSearchOnly: Bool?
    let indexName: String?
    let objectID: String?
    let queryID: String?
}
