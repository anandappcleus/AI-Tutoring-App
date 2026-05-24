//
//  NetworkStatusBanner.swift
//  SmartTutor
//
//  Displays a thin connectivity banner — standard iOS pattern used by
//  WhatsApp, Telegram, Slack etc.
//
//  • Offline  → persistent grey/black banner slides down from top
//  • Reconnected → green banner slides down, auto-dismisses after 3 s
//
//  Usage: attach .networkStatusBanner() to the root ContentView.
//

import SwiftUI

// MARK: - Banner state

private enum ConnectivityBannerState {
    case hidden
    case offline
    case reconnected
}

// MARK: - View modifier

private struct NetworkStatusBannerModifier: ViewModifier {

    @State private var bannerState: ConnectivityBannerState = .hidden
    @State private var dismissTask: Task<Void, Never>? = nil
    private let syncManager = OfflineSyncManager.shared

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if bannerState != .hidden {
                    banner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: bannerState == .hidden)
            .task { await observeConnectivity() }
    }

    // MARK: Banner view

    private var banner: some View {
        HStack(spacing: 8) {
            Image(systemName: bannerState == .offline ? "wifi.slash" : "wifi")
                .font(.system(size: 13, weight: .semibold))
            Text(bannerState == .offline ? "No internet connection" : "Back online")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(bannerState == .offline
                    ? Color(red: 0.20, green: 0.20, blue: 0.20)   // dark grey
                    : Color(red: 0.18, green: 0.68, blue: 0.38))  // green
        .animation(.easeInOut(duration: 0.25), value: bannerState)
    }

    // MARK: Observation loop

    private func observeConnectivity() async {
        var previous = syncManager.isNetworkReachable
        // Show offline banner immediately if app launched without connectivity.
        if !previous {
            withAnimation { bannerState = .offline }
        }
        while !Task.isCancelled {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                withObservationTracking {
                    _ = syncManager.isNetworkReachable
                } onChange: {
                    cont.resume()
                }
            }
            let current = syncManager.isNetworkReachable
            guard current != previous else { continue }

            dismissTask?.cancel()

            if !current {
                // Went offline
                withAnimation { bannerState = .offline }
            } else {
                // Came back online — show green banner, then hide after 3 s
                withAnimation { bannerState = .reconnected }
                dismissTask = Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    withAnimation { bannerState = .hidden }
                }
            }
            previous = current
        }
    }
}

// MARK: - Convenience modifier

extension View {
    /// Attaches the app-wide network connectivity banner to this view.
    func networkStatusBanner() -> some View {
        modifier(NetworkStatusBannerModifier())
    }
}
