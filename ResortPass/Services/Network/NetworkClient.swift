//
//  NetworkClient.swift
//  ResortPass
//

import Foundation
import CryptoKit

extension URLRequest {
    nonisolated var cacheKey: String? {
        guard let urlString = url?.absoluteString else { return nil }
        guard let httpBody = httpBody else { return urlString }
        
        let hash = SHA256.hash(data: httpBody)
        let bodyHashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        return "\(urlString)|\(bodyHashString)"
    }
}

actor POSTCache {
    static let shared = POSTCache()
    private init() {}
    
    private var storage = [String: (data: Data, response: HTTPURLResponse, timestamp: Date)]()
    private let cacheDuration: TimeInterval = 300 // 5 minutes
    
    func cachedResponse(for request: URLRequest) -> (Data, HTTPURLResponse)? {
        guard let key = request.cacheKey, let cached = storage[key] else { return nil }
        if Date().timeIntervalSince(cached.timestamp) > cacheDuration {
            storage.removeValue(forKey: key)
            return nil
        }
        return (cached.data, cached.response)
    }
    
    func storeResponse(data: Data, response: HTTPURLResponse, for request: URLRequest) {
        guard let key = request.cacheKey else { return }
        storage[key] = (data, response, Date())
    }
    
    func clear() {
        storage.removeAll()
    }
}

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
        if request.httpMethod == "POST", let cached = await POSTCache.shared.cachedResponse(for: request) {
            do {
                return try decoder.decode(T.self, from: cached.0)
            } catch {
                // Fallback to network request if decoding cached data fails (e.g., if model changed)
            }
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
        
        if request.httpMethod == "POST" {
            await POSTCache.shared.storeResponse(data: data, response: httpResponse, for: request)
        }
        
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }
}

