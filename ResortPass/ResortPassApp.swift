//
//  ResortPassApp.swift
//  ResortPass
//
//  Created by Amad on 6/25/26.
//

import SwiftUI

@main
struct ResortPassApp: App {
    @State private var showSplash = true
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    LaunchView()
                        .transition(.opacity)
                } else {
                    SearchView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.6), value: showSplash)
            .task {
                // Display splash screen for 1.8 seconds
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                withAnimation {
                    showSplash = false
                }
            }
        }
    }
}
