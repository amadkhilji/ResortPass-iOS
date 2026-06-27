//
//  NetworkClient.swift
//  ResortPass
//

import Foundation

protocol NetworkClientProtocol: Sendable {
    func perform<T: Decodable>(_ request: URLRequest) async throws -> T
}

enum NetworkError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, data: Data)
    case decodingError(Error)
    case noData
    case invalidURL
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from the server."
        case .httpError(let statusCode, _):
            return "Server returned an error with status code \(statusCode)."
        case .decodingError(let error):
            return "Failed to parse server data: \(error.localizedDescription)"
        case .noData:
            return "No data received from the server."
        case .invalidURL:
            return "The requested URL is invalid."
        }
    }
}

final class ResortPassURLCache: URLCache, @unchecked Sendable {
    private let defaultExpirationDuration: TimeInterval = 300
    
    override func storeCachedResponse(_ cachedResponse: CachedURLResponse, for request: URLRequest) {
        guard let httpResponse = cachedResponse.response as? HTTPURLResponse else {
            super.storeCachedResponse(cachedResponse, for: request)
            return
        }
        
        var headers = [String: String]()
        for (key, value) in httpResponse.allHeaderFields {
            if let keyString = key as? String, let valueString = value as? String {
                headers[keyString] = valueString
            }
        }
        
        let hasCacheControl = headers.keys.contains { $0.lowercased() == "cache-control" }
        let hasETag = headers.keys.contains { $0.lowercased() == "etag" }
        let hasLastModified = headers.keys.contains { $0.lowercased() == "last-modified" }

        // Only inject the fallback max-age if the server provided absolutely NO cache validation indicators
        if !hasCacheControl && !hasETag && !hasLastModified {
            headers["Cache-Control"] = "max-age=\(Int(defaultExpirationDuration))"
            if let url = httpResponse.url,
                let modifiedResponse = HTTPURLResponse(url: url, statusCode: httpResponse.statusCode, httpVersion: nil, headerFields: headers) {
                let modifiedCachedResponse = CachedURLResponse(response: modifiedResponse, data: cachedResponse.data, userInfo: cachedResponse.userInfo, storagePolicy: cachedResponse.storagePolicy)

                super.storeCachedResponse(modifiedCachedResponse, for: request)
                return
            }
        }
        
        super.storeCachedResponse(cachedResponse, for: request)
    }
}

final class NetworkClient: NetworkClientProtocol {
    private let session: URLSession
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
    
    init(session: URLSession) {
        self.session = session
    }
    
    convenience init() {
        let memoryCapacity = 10 * 1024 * 1024 // 10MB
        let diskCapacity = 50 * 1024 * 1024  // 50MB
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ResortPassAPICache", isDirectory: true)
        
        let config = URLSessionConfiguration.default
        config.urlCache = ResortPassURLCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            directory: cacheDirectory
        )
        config.requestCachePolicy = .useProtocolCachePolicy
        
        let session = URLSession(configuration: config)
        self.init(session: session)
    }
    
    func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
        
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }
}

