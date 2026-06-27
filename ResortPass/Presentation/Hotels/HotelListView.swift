//
//  HotelListView.swift
//  ResortPass
//

import SwiftUI

struct HotelListView: View {
    @StateObject private var viewModel: HotelListViewModel
    
    init(
        latitude: Double,
        longitude: Double,
        locationName: String,
        networkClient: any NetworkClientProtocol = NetworkClient()
    ) {
        _viewModel = StateObject(wrappedValue: HotelListViewModel(
            latitude: latitude,
            longitude: longitude,
            locationName: locationName,
            networkClient: networkClient
        ))
    }
    
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            
            List {
                if !viewModel.isLoadingInitial && !viewModel.hotels.isEmpty && viewModel.errorMessage == nil {
                    ForEach(viewModel.hotels) { hotel in
                        hotelCard(for: hotel)
                            .onAppear {
                                viewModel.loadMoreIfNeeded(for: hotel)
                            }
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    
                    if viewModel.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Theme.rpRed))
                                .scaleEffect(1.2)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .padding(.vertical, 16)
                    }
                } else if viewModel.isLoadingInitial {
                    ForEach(0..<3, id: \.self) { _ in
                        shimmerCard
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable {
                await viewModel.fetchHotels(reset: true)
            }
            
            if let errorMessage = viewModel.errorMessage {
                errorStateView(message: errorMessage)
                    .transition(.opacity)
            } else if !viewModel.isLoadingInitial && viewModel.hotels.isEmpty {
                emptyStateView
                    .transition(.opacity)
            }
        }
        .navigationTitle(viewModel.locationName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.fetchHotels(reset: true)
        }
    }
    
    private func hotelCard(for hotel: Hotel) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                // Image Header
                CachedAsyncImage(url: hotel.resolvedImageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 190)
                        .clipped()
                } placeholder: {
                    Rectangle()
                        .fill(Color(uiColor: .systemGray5))
                        .shimmer()
                        .frame(height: 190)
                }
                
                // Details section
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(hotel.name)
                            .font(.rpTitle(size: 18))
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(2)
                        
                        HStack(spacing: 4) {
                            if hotel.displayRating > 0 {
                                StarRatingView(rating: hotel.displayRating)
                                
                                Text(String(format: "%.1f", hotel.displayRating))
                                    .font(.rpMedium(size: 13))
                                    .foregroundColor(Theme.textPrimary)
                                
                                Text("(\(hotel.reviews ?? 0))")
                                    .foregroundColor(Theme.textSecondary)
                                
                                Text("|")
                                    .foregroundColor(Theme.textSecondary)
                            }
                            
                            let city = hotel.cityName ?? ""
                            let state = hotel.stateCode ?? ""
                            let locationText = !city.isEmpty && !state.isEmpty ? "\(city), \(state)" : (city.isEmpty ? state : city)
                            if !locationText.isEmpty {
                                Text(locationText)
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
                        .font(.rpCaption(size: 13))
                    }
                    
                    // Amenities scroll view
                    if let amenities = hotel.amenities, !amenities.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(amenities, id: \.name) { amenity in
                                    amenityChip(for: amenity)
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                     // Pricing and Product details
                    HStack(alignment: .firstTextBaseline) {
                        if let product = hotel.displayProduct {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                let typeName = (product.productTypeName ?? "Pass").trimmingCharacters(in: .whitespacesAndNewlines)
                                let name = product.name.trimmingCharacters(in: .whitespacesAndNewlines)
                                let displayLabel = !typeName.isEmpty && typeName.caseInsensitiveCompare(name) != .orderedSame ? "\(typeName) - \(name)" : name
                                
                                if let price = product.price {
                                    Text(String(format: "$%.0f", price))
                                        .font(.system(size: 24, weight: .bold, design: .default))
                                        .foregroundColor(Theme.rpRed)
                                }
                                
                                Text(displayLabel)
                                    .font(.rpMedium(size: 14))
                                    .foregroundColor(Theme.textPrimary)
                            }
                        } else {
                            Text("No booking available")
                                .font(.rpMedium(size: 14))
                                .foregroundColor(Theme.textSecondary)
                        }
                        
                        Spacer()
                        
                        if let distance = hotel.distanceMiles {
                            Text(String(format: "%.1f mi away", distance))
                                .font(.rpMedium(size: 14))
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(16)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityString(for: hotel))
    }
    
    private func amenityChip(for amenity: Amenity) -> some View {
        HStack(spacing: 4) {
            // Pick a matching system icon for common amenities
            Image(systemName: systemIcon(for: amenity.name))
                .font(.system(size: 11))
            
            Text(amenity.description ?? amenity.name.capitalized)
                .font(.rpCaption(size: 11))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(uiColor: .systemGray5))
        .cornerRadius(20)
        .foregroundColor(Theme.textPrimary)
    }
    
    private func systemIcon(for amenityName: String) -> String {
        switch amenityName.lowercased() {
        case "pool": return "drop.fill"
        case "food", "restaurant": return "fork.knife"
        case "spa", "massage": return "face.smiling"
        case "wifi": return "wifi"
        case "gym", "fitness": return "dumbbell.fill"
        case "parking": return "car.fill"
        default: return "checkmark.circle"
        }
    }
    
    private func accessibilityString(for hotel: Hotel) -> String {
        var str = "\(hotel.name) in \(hotel.cityName ?? "")."
        if let distance = hotel.distanceMiles {
            str += " \(String(format: "%.1f miles away", distance))."
        }
        if hotel.displayRating > 0 {
            str += " Rating \(String(format: "%.1f", hotel.displayRating))."
        }
        if let product = hotel.displayProduct {
            str += " Offering \(product.name)"
            if let price = product.price {
                str += " starting from \(String(format: "%.0f dollars", price))."
            }
        }
        return str
    }
    
    // MARK: - Skeleton/Shimmer view
    
    private var shimmerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color(uiColor: .systemGray5))
                .frame(height: 190)
                .shimmer()
            
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(uiColor: .systemGray5))
                    .frame(width: 180, height: 20)
                    .shimmer()
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(uiColor: .systemGray5))
                    .frame(width: 100, height: 14)
                    .shimmer()
                
                Divider()
                
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(uiColor: .systemGray5))
                        .frame(width: 120, height: 16)
                        .shimmer()
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(uiColor: .systemGray5))
                        .frame(width: 60, height: 24)
                        .shimmer()
                }
            }
            .padding(16)
        }
        .background(Theme.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.border.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Error and Empty States
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "house.circle")
                .font(.system(size: 64))
                .foregroundColor(Theme.textSecondary)
            
            Text("No Resorts Found")
                .font(.rpTitle(size: 18))
                .foregroundColor(Theme.textPrimary)
            
            Text("We couldn't find any resorts or hotels available for '\(viewModel.locationName)'. Try checking a different location.")
                .font(.rpBody(size: 14))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding()
    }
    
    private func errorStateView(message: String) -> some View {
        VStack(spacing: 16) {
             Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundColor(Theme.rpAccent)
            
            Text("Connection Error")
                .font(.rpTitle(size: 18))
                .foregroundColor(Theme.textPrimary)
            
            Text(message)
                .font(.rpBody(size: 14))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button(action: {
                viewModel.retryFetch()
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
        .padding()
    }
}


