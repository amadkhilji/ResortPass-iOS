//
//  CachedAsyncImage.swift
//  ResortPass
//

import SwiftUI

/// Asynchronously loads and displays an image from a URL.
/// Memory cache is checked synchronously on the main thread first to prevent scrolling flicker.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let cacheManager: any ImageCacheManagerProtocol
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    
    @State private var state: ImageLoadingState = .loading
    @State private var loadTask: Task<Void, Never>?
    @State private var loadedURLString: String?
    
    init(
        url: URL?,
        cacheManager: any ImageCacheManagerProtocol = ImageCacheManager.shared,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.cacheManager = cacheManager
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            switch state {
            case .empty, .loading:
                placeholder()
            case .success(let image):
                content(image)
            case .failure:
                // Error fallback card representation
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(uiColor: .systemGray5))
                    Image(systemName: "photo")
                        .font(.system(size: 24))
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
        .onAppear {
            loadImage()
        }
        .onDisappear {
            cancelLoading()
        }
        .onChange(of: url) { _ in
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let url = url else {
            state = .failure
            loadedURLString = nil
            return
        }
        
        let urlString = url.absoluteString
        
        // Skip redundant fetches if we're already displaying this image
        if case .success = state, loadedURLString == urlString {
            return
        }
        
        cancelLoading()
        state = .loading
        loadedURLString = nil
        
        loadTask = Task { @MainActor in
            let result = await cacheManager.image(from: urlString)
            
            guard !Task.isCancelled else { return }
            
            if let uiImage = result {
                self.loadedURLString = urlString
                withAnimation(.easeOut(duration: 0.3)) {
                    self.state = .success(Image(uiImage: uiImage))
                }
            } else {
                self.loadedURLString = nil
                self.state = .failure
            }
        }
    }
    
    private func cancelLoading() {
        loadTask?.cancel()
        loadTask = nil
    }
}

// MARK: - Helper Enums

private enum ImageLoadingState {
    case empty
    case loading
    case success(Image)
    case failure
}
