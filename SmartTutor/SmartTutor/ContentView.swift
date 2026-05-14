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
        Group {
            if !appState.isAuthenticated {
                LoginView()
            } else if !isOnboardingComplete {
                OnboardingView(isOnboardingComplete: $isOnboardingComplete)
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: appState.isAuthenticated)
    }
}

// MARK: - Main Tab View

private struct MainTabView: View {
    @AppStorage("selectedMainTab") private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("Home",     systemImage: "house.fill") }
                .tag(0)

            StudyView()
                .tabItem { Label("Study",    systemImage: "brain.head.profile") }
                .tag(1)

            LearnerProgressView()
                .tabItem { Label("Progress", systemImage: "chart.bar.xaxis") }
                .tag(2)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .tint(.indigo)
    }
}

#Preview {
    ContentView()
}
