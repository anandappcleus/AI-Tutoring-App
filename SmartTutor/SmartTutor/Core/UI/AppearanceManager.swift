//
//  AppearanceManager.swift
//  SmartTutor
//
//  Ported from NowAssist/AppearanceManager.swift.
//  Manages Light / Dark / System appearance and persists the user's choice.
//

import SwiftUI
import Combine

// MARK: - Mode enum

enum AppearanceMode: String, CaseIterable {
    case light  = "Light"
    case dark   = "Dark"
    case system = "System"

    var colorScheme: ColorScheme? {
        switch self {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }

    var icon: String {
        switch self {
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }
}

// MARK: - Manager

final class AppearanceManager: ObservableObject {

    static let shared = AppearanceManager()

    @Published var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "STAppearanceMode")
            DispatchQueue.main.async { self.applyAppearance() }
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "STAppearanceMode") ?? AppearanceMode.system.rawValue
        self.appearanceMode = AppearanceMode(rawValue: saved) ?? .system
    }

    func applyAppearance() {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for window in ws.windows {
                switch appearanceMode {
                case .light:  window.overrideUserInterfaceStyle = .light
                case .dark:   window.overrideUserInterfaceStyle = .dark
                case .system: window.overrideUserInterfaceStyle = .unspecified
                }
            }
        }
        updateTabBarAppearance()
    }

    private func updateTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()

        // Resolve which style is currently active
        let isDark: Bool
        if appearanceMode == .system {
            isDark = UIScreen.main.traitCollection.userInterfaceStyle == .dark
        } else {
            isDark = appearanceMode == .dark
        }

        let accent = isDark
            ? UIColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1)
            : UIColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1)

        appearance.stackedLayoutAppearance.selected.iconColor  = accent
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: accent]
        UITabBar.appearance().standardAppearance   = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
