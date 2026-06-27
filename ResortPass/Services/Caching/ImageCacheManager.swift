//
//  ImageCacheManager.swift
//  ResortPass
//

import UIKit

/// Protocol describing the capabilities of an Image Cache Manager, allowing test doubles and mock configurations.
protocol ImageCacheManagerProtocol: Actor {
    func image(from urlString: String) async -> UIImage?
    func getFromMemory(for urlString: String) async -> UIImage?
    func getFromDisk(for urlString: String) async -> Data?
    func set(_ data: Data, _ image: UIImage, for urlString: String) async
    func clearAll() async
}

/// Manages image caching in memory (standard dictionary) and on disk (via URLCache) under actor isolation.
actor ImageCacheManager: ImageCacheManagerProtocol {
    static let shared = ImageCacheManager()
    
    // NSCache memory cache configured to evict after 100 items
    private let memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()
    
    // URLSession configured with URLCache for disk persistence
    private lazy var session: URLSession = {
        let memoryCapacity = 50 * 1024 * 1024 // 50MB
        let diskCapacity = 150 * 1024 * 1024  // 150MB
        
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, directory: nil)
        config.requestCachePolicy = .returnCacheDataElseLoad // Use cached data first, load from network only when missing
        return URLSession(configuration: config)
    }()
    
    private init() {
        setupMemoryObserver()
    }
    
    nonisolated private func setupMemoryObserver() {
        // Flush memory cache if the system runs low
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.clearMemoryCache()
            }
        }
    }
    
    // Clears memory cache
    func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }
    
    // Memory cache lookup
    func getFromMemory(for urlString: String) -> UIImage? {
        memoryCache.object(forKey: urlString as NSString)
    }
    
    // Save image to memory
    func saveToMemory(_ image: UIImage, for urlString: String) {
        memoryCache.setObject(image, forKey: urlString as NSString)
    }
    
    /// Main entry point to load/fetch an image. Checks memory cache, reads from URLCache, 
    /// decompresses on a background cooperative thread, and backfills memory cache.
    func image(from urlString: String) async -> UIImage? {
        // 1. Check Memory Cache
        if let cached = getFromMemory(for: urlString) {
            return cached
        }
        
        // 2. Check Disk Cache (URLCache)
        if let cachedData = getFromDisk(for: urlString),
           let image = UIImage(data: cachedData) {
            let decompressedImage = image.decompressed
            saveToMemory(decompressedImage, for: urlString)
            return decompressedImage
        }
        
        // 3. Network Fetch
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            let request = URLRequest(url: url)
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            
            guard let image = UIImage(data: data) else { return nil }
            let decompressedImage = image.decompressed
            
            // Explicitly store to both disk cache (URLCache) and memory cache
            let cachedResponse = CachedURLResponse(response: httpResponse, data: data)
            session.configuration.urlCache?.storeCachedResponse(cachedResponse, for: request)
            
            saveToMemory(decompressedImage, for: urlString)
            return decompressedImage
        } catch {
            return nil
        }
    }
    
    // MARK: - Test & Legacy Compatibility Helpers
    
    // Fetch raw data directly from URLCache (primarily for tests)
    func getFromDisk(for urlString: String) -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        let request = URLRequest(url: url)
        return session.configuration.urlCache?.cachedResponse(for: request)?.data
    }
    
    // Force cache raw data and UIImage (primarily for tests)
    func set(_ data: Data, _ image: UIImage, for urlString: String) {
        guard let url = URL(string: urlString) else { return }
        let request = URLRequest(url: url)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let cachedResponse = CachedURLResponse(response: response, data: data)
        session.configuration.urlCache?.storeCachedResponse(cachedResponse, for: request)
        saveToMemory(image, for: urlString)
    }
    
    // Wipe everything
    func clearAll() {
        clearMemoryCache()
        session.configuration.urlCache?.removeAllCachedResponses()
    }
}

// MARK: - Image Decompression

extension UIImage {
    /// Forces decompression of the image on the caller's thread by rendering it into a Core Graphics bitmap context.
    /// This prevents stuttering when the image is first rendered on the main thread.
    nonisolated var decompressed: UIImage {
        guard let cgImage = self.cgImage else { return self }
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return self
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let decompressedCGImage = context.makeImage() else { return self }
        
        return UIImage(
            cgImage: decompressedCGImage,
            scale: self.scale,
            orientation: self.imageOrientation
        )
    }
}
