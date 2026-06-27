//
//  LaunchView.swift
//  ResortPass
//

import SwiftUI

struct LaunchView: View {
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0.0
    
    init() {}
    
    var body: some View {
        ZStack {
            Theme.rpRed.ignoresSafeArea()
            VStack(spacing: 8) {
                Text("RESORTPASS")
                    .font(.system(size: 38, weight: .bold, design: .serif))
                    .kerning(6) // Premium character spacing
                    .foregroundColor(.white)
                    .scaleEffect(scale)
                    .opacity(opacity)
                
                Text("DAY GUEST PASSES & SPAS")
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .kerning(4)
                    .foregroundColor(.white)
                    .offset(y: 4)
                    .opacity(opacity)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) {
                self.scale = 1.0
                self.opacity = 1.0
            }
        }
    }
}

#Preview {
    LaunchView()
}
