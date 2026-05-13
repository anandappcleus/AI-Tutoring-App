//
//  ContentView.swift
//  SmartTutor
//
//  Root shell: shows OnboardingView on first launch, then the main TabView.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("isOnboardingComplete") private var isOnboardingComplete = false

    var body: some View {
        if isOnboardingComplete {
            MainTabView()
        } else {
            OnboardingView(isOnboardingComplete: $isOnboardingComplete)
        }
    }
}

// MARK: - Main Tab View

private struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Home",     systemImage: "house.fill") }

            StudyView()
                .tabItem { Label("Study",    systemImage: "brain.head.profile") }

            LearnerProgressView()
                .tabItem { Label("Progress", systemImage: "chart.bar.xaxis") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.indigo)
    }
}

#Preview {
    ContentView()
}
