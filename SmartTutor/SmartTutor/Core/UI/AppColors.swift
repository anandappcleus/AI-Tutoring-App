//
//  AppColors.swift
//  SmartTutor
//
//  Ported from NowAssist/AppColors.swift.
//  Provides a single source-of-truth for the app's gradient and accent colours,
//  with automatic light / dark mode switching.
//

import SwiftUI

struct AppColors {

    // MARK: - Gradient

    /// Full-screen gradient top colour.
    /// Light: dark blue-gray  |  Dark: near-black
    static let gradientTop = Color(
        light: Color(red: 0.25, green: 0.27, blue: 0.35),
        dark:  Color(red: 0.15, green: 0.15, blue: 0.15)
    )

    /// Full-screen gradient bottom colour.
    /// Light: pinkish-rose  |  Dark: dark gray
    static let gradientBottom = Color(
        light: Color(red: 0.85, green: 0.45, blue: 0.55),
        dark:  Color(red: 0.25, green: 0.25, blue: 0.25)
    )

    // MARK: - Accent

    /// Primary interactive accent.
    /// Light: red  |  Dark: light gray
    static let accent = Color(
        light: Color(red: 0.8, green: 0.2, blue: 0.2),
        dark:  Color(red: 0.7, green: 0.7, blue: 0.7)
    )

    /// UIColor variant of `accent` for UIKit APIs (tab bar, etc.).
    static var accentUIColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1)
                : UIColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1)
        }
    }

    // MARK: - Convenience gradient

    /// Returns the `[gradientTop, gradientBottom]` array used in every LinearGradient.
    static var gradientColors: [Color] { [gradientTop, gradientBottom] }

    // MARK: - Card backgrounds (NowAssist: dark translucent over gradient)

    /// Primary card background — dark translucent for both modes.
    static let cardBackground = Color.black.opacity(0.28)

    /// Secondary / nested card background.
    static let cardBackgroundSecondary = Color.white.opacity(0.10)

    /// Divider colour over gradient background.
    static let cardDivider = Color.white.opacity(0.15)

    // MARK: - Text on gradient / dark cards

    /// Primary text on gradient or dark card backgrounds.
    static let textPrimary   = Color.white
    /// Secondary text on gradient or dark card backgrounds.
    static let textSecondary = Color.white.opacity(0.65)
}

// MARK: - Light / Dark initialiser for Color

extension Color {
    /// Creates a colour that switches between `light` and `dark` based on the
    /// current UIKit user interface style — identical to NowAssist's implementation.
    init(light: Color, dark: Color) {
        self.init(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
    }
}
