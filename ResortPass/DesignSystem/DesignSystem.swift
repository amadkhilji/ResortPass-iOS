//
//  DesignSystem.swift
//  ResortPass
//

import SwiftUI

struct Theme {
    // Premium semantic color palettes matching Apple News theme
    static let rpRed = Color(red: 250/255, green: 47/255, blue: 85/255)      // #FA2F55 - primary pinkish-red
    static let rpAccent = Color(red: 199/255, green: 21/255, blue: 66/255)   // #C71542 - deep rose accent
    static let gold = Color(red: 237/255, green: 189/255, blue: 70/255)    // #EDBD46 - star gold
    
    static var background: Color {
        Color(uiColor: .systemGroupedBackground)
    }
    
    static var cardBackground: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }
    
    static var textPrimary: Color {
        Color(uiColor: .label)
    }
    
    static var textSecondary: Color {
        Color(uiColor: .secondaryLabel)
    }
    
    static var border: Color {
        Color(uiColor: .separator)
    }
}

// MARK: - Font Extensions

extension Font {
    static func rpHeader(size: CGFloat = 24) -> Font {
        return .system(size: size, weight: .bold, design: .serif)
    }
    
    static func rpTitle(size: CGFloat = 18) -> Font {
        return .system(size: size, weight: .semibold, design: .default)
    }
    
    static func rpBody(size: CGFloat = 14) -> Font {
        return .system(size: size, weight: .regular, design: .default)
    }
    
    static func rpMedium(size: CGFloat = 14) -> Font {
        return .system(size: size, weight: .medium, design: .default)
    }
    
    static func rpCaption(size: CGFloat = 12) -> Font {
        return .system(size: size, weight: .regular, design: .default)
    }
}

// MARK: - Reusable Views

struct ResortPassButton: View {
    let title: String
    let action: () -> Void
    
    init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.rpMedium(size: 16))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Theme.rpRed)
                .cornerRadius(12)
                .shadow(color: Theme.rpRed.opacity(0.3), radius: 6, x: 0, y: 3)
        }
    }
}

// Custom Glassmorphic Card Background
struct GlassCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.cardBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.border.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
    }
}

// Stars Rating View
struct StarRatingView: View {
    let rating: Double
    let maxRating: Int = 5
    
    init(rating: Double) {
        self.rating = rating
    }
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<maxRating, id: \.self) { index in
                let target = Double(index) + 0.5
                if rating >= Double(index + 1) {
                    Image(systemName: "star.fill")
                        .foregroundColor(Theme.gold)
                } else if rating >= target {
                    Image(systemName: "star.leadinghalf.filled")
                        .foregroundColor(Theme.gold)
                } else {
                    Image(systemName: "star")
                        .foregroundColor(Color(uiColor: .systemGray4))
                }
            }
        }
        .font(.system(size: 13))
    }
}

// Shimmer Modifier for Skeleton Loading
struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .redacted(reason: .placeholder)
            .overlay(
                GeometryReader { geo in
                    let width = geo.size.width
                    let height = geo.size.height
                    
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.black.opacity(0.15),
                            Color.black.opacity(0.05),
                            Color.black.opacity(0.15)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: width, height: height)
                    .mask(content)
                    .offset(
                        x: -width + (phase * width * 2),
                        y: 0
                    )
                    .onAppear {
                        withAnimation(Animation.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                            phase = 1
                        }
                    }
                }
            )
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
}
