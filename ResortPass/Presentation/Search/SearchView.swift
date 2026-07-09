//
//  SearchView.swift
//  ResortPass
//

import SwiftUI
import CoreLocation

extension SearchView {
    @MainActor
    init(viewModel: ViewModel) {
        self.init(viewModel: viewModel, locationManager: LocationManager.shared)
    }
}

extension SearchView where ViewModel == SearchViewModel {
    @MainActor
    init() {
        self.init(viewModel: SearchViewModel())
    }
}

struct SearchView<ViewModel: SearchViewModelProtocol>: View {
    @StateObject private var viewModel: ViewModel
    @ObservedObject private var locationManager: LocationManager
    
    @MainActor
    init(viewModel: ViewModel, locationManager: LocationManager) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.locationManager = locationManager
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with Search Bar
                searchHeaderView
                
                // Content Body
                Group {
                    if let errorMessage = viewModel.errorMessage {
                        errorStateView(message: errorMessage)
                    } else if viewModel.isLoading && viewModel.places.isEmpty {
                        // Initial loading state
                        loadingStateView
                    } else if viewModel.places.isEmpty && !viewModel.searchQuery.isEmpty {
                        emptyStateView
                    } else {
                        resultsListView
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .background(Theme.background)
            .navigationTitle("ResortPass")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        locationManager.requestLocation()
                    }) {
                        Image(systemName: locationManager.userLocation == nil ? "location.circle" : "location.circle.fill")
                            .foregroundColor(Theme.rpRed)
                    }
                    .accessibilityLabel("Use My Location")
                    .accessibilityHint("Asks for location access to search nearby hotels.")
                }
            }
            .onChange(of: locationManager.userLocation) { newLocation in
                if let newLocation {
                    Task {
                        await viewModel.loadNearbyLocations(latitude: newLocation.latitude, longitude: newLocation.longitude)
                    }
                }
            }
            .onAppear {
                locationManager.requestLocation()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var searchHeaderView: some View {
        VStack(spacing: 12) {
            HStack {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.rpRed))
                            .scaleEffect(0.8)
                            .frame(width: 20, height: 20)
                            .padding(.leading, 16)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(Theme.textSecondary)
                            .padding(.leading, 16)
                    }
                    
                    TextField("Where do you want to go?", text: $viewModel.searchQuery)
                        .font(.rpBody(size: 16))
                        .foregroundColor(Theme.textPrimary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Search for resorts or destinations")
                    
                    if !viewModel.searchQuery.isEmpty {
                        Button(action: {
                            viewModel.searchQuery = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Theme.textSecondary)
                        }
                        .padding(.trailing, 16)
                        .accessibilityLabel("Clear search text")
                    }
                }
                .padding(.vertical, 10)
                .background(Color(uiColor: .systemGray5))
                .clipShape(Capsule())
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            Divider()
        }
        .background(Theme.cardBackground)
    }
    
    private var resultsListView: some View {
        List {
            if viewModel.searchQuery.isEmpty {
                if !viewModel.nearbyPlaces.isEmpty {
                    Section(header: Text("NEARBY DESTINATIONS")
                                .font(.rpCaption(size: 12))
                                .foregroundColor(Theme.textSecondary)
                                .padding(.top, 8)) {
                        ForEach(viewModel.nearbyPlaces) { place in
                            placeRow(for: place)
                        }
                    }
                    .listRowBackground(Theme.cardBackground)
                }
                
                Section(header: Text("POPULAR DESTINATIONS")
                            .font(.rpCaption(size: 12))
                            .foregroundColor(Theme.textSecondary)
                            .padding(.top, 8)) {
                    ForEach(viewModel.popularPlaces) { place in
                        placeRow(for: place)
                    }
                }
                .listRowBackground(Theme.cardBackground)
            } else {
                ForEach(viewModel.searchResults) { place in
                    placeRow(for: place)
                        .onAppear {
                            viewModel.loadMoreIfNeeded(for: place)
                        }
                }
                .listRowBackground(Theme.cardBackground)
            }
        }
        .listStyle(InsetGroupedListStyle())
        .scrollContentBackground(.hidden)
    }
    
    private func placeRow(for place: Place) -> some View {
        NavigationLink(destination: HotelListView(
            latitude: place.latitude ?? 0.0,
            longitude: place.longitude ?? 0.0,
            locationName: place.name
        )) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Theme.rpRed.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(Theme.rpRed)
                        .font(.system(size: 18))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name)
                        .font(.rpMedium(size: 16))
                        .foregroundColor(Theme.textPrimary)
                    
                    Text((place.type ?? "city").capitalized)
                        .font(.rpCaption(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(place.name), \(place.type ?? "city")")
        .accessibilityHint("Double tap to view resorts and hotels in this location.")
    }
    
    private var loadingStateView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: Theme.rpRed))
            Text("Searching Resorts...")
                .font(.rpMedium(size: 16))
                .foregroundColor(Theme.textSecondary)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 64))
                .foregroundColor(Theme.textSecondary)
            
            Text("No Results Found")
                .font(.rpTitle(size: 18))
                .foregroundColor(Theme.textPrimary)
            
            Text("We couldn't find any resorts matching '\(viewModel.searchQuery)'. Try searching for a city or state.")
                .font(.rpBody(size: 14))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
    
    private func errorStateView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundColor(Theme.rpAccent)
            
            Text("Search Error")
                .font(.rpTitle(size: 18))
                .foregroundColor(Theme.textPrimary)
            
            Text(message)
                .font(.rpBody(size: 14))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button(action: {
                viewModel.retrySearch()
            }) {
                Text("Retry")
                    .font(.rpMedium(size: 16))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Theme.rpRed)
                    .cornerRadius(8)
            }
        }
    }
}

#Preview {
    SearchView()
}
