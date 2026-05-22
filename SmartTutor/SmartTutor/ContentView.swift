//
//  ContentView.swift
//  SmartTutor
//
//  Root shell: shows OnboardingView on first launch, then the main TabView.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
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
    /// Owned here so it survives every tab switch and sheet dismiss.
    /// StudyView reads it via @Environment instead of allocating its own instance.
    @State private var studyViewModel = StudyViewModel()

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
        .environment(studyViewModel)
        .onChange(of: selectedTab) { _, tab in
            let names = ["Home", "Study", "Progress", "Settings"]
            let dest = tab < names.count ? names[tab] : "tab-\(tab)"
            AppLogger.navigated(to: dest)
        }
    }
}

#Preview {
    ContentView()
}
