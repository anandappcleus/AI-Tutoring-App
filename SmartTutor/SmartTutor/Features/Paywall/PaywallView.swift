//
//  PaywallView.swift
//  SmartTutor
//
//  Converted from PaywallScreen.tsx
//  Premium upgrade with annual / monthly plan selection.
//

import SwiftUI

struct PaywallView: View {
    let onSubscribe: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: PremiumPlan = .annual
    @State private var isProcessing = false

    enum PremiumPlan { case monthly, annual }

    private let features: [(icon: String, text: String, highlight: Bool)] = [
        ("bolt.fill",               "Unlimited Questions",          true),
        ("arrow.down.circle.fill",  "Offline Question Packs",       true),
        ("sparkles",                "Advanced AI Explanations",     false),
        ("person.2.fill",           "Parent Monitoring Dashboard",  false),
        ("crown.fill",              "Priority Support",             false),
        ("checkmark.circle.fill",   "All Languages Supported",      false),
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.57, green: 0.25, blue: 0.95),
                    Color(red: 0.35, green: 0.32, blue: 0.95),
                    Color(red: 0.22, green: 0.49, blue: 0.95),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Close button
                    HStack {
                        Spacer()
                        Button {
                            AppLogger.userAction(AppLogger.auth, action: "paywall-dismissed")
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    VStack(spacing: 24) {
                        // Crown + headline
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.yellow, .orange],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 80, height: 80)
                                    .shadow(color: .orange.opacity(0.4), radius: 16, y: 6)
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 34))
                                    .foregroundStyle(.white)
                            }
                            Text("Upgrade to Premium")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.white)
                            Text("Unlock unlimited learning potential")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.8))
                        }

                        // Features list
                        VStack(spacing: 16) {
                            ForEach(features, id: \.text) { feature in
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                feature.highlight
                                                ? AnyShapeStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                                                : AnyShapeStyle(Color.white.opacity(0.2))
                                            )
                                            .frame(width: 40, height: 40)
                                        Image(systemName: feature.icon)
                                            .font(.system(size: 16))
                                            .foregroundStyle(.white)
                                    }
                                    Text(feature.text)
                                        .font(.system(size: 15, weight: feature.highlight ? .semibold : .regular))
                                        .foregroundStyle(.white)
                                    Spacer()
                                }
                            }
                        }
                        .padding(24)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )

                        // Plan picker
                        VStack(spacing: 12) {
                            PlanButton(
                                title: "Annual Plan",
                                subtitle: "₹208/month",
                                price: "₹2,499",
                                period: "per year",
                                badge: "30% off",
                                isSelected: selectedPlan == .annual
                            ) {
                                AppLogger.userAction(AppLogger.auth, action: "plan-selected", context: "annual")
                                withAnimation(.spring(response: 0.3)) { selectedPlan = .annual }
                            }

                            PlanButton(
                                title: "Monthly Plan",
                                subtitle: "Flexible billing",
                                price: "₹299",
                                period: "per month",
                                badge: nil,
                                isSelected: selectedPlan == .monthly
                            ) {
                                AppLogger.userAction(AppLogger.auth, action: "plan-selected", context: "monthly")
                                withAnimation(.spring(response: 0.3)) { selectedPlan = .monthly }
                            }
                        }

                        // Subscribe CTA
                        Button {
                            AppLogger.userAction(AppLogger.auth, action: "subscribe-tapped",
                                                 context: selectedPlan == .monthly ? "monthly" : "annual")
                            isProcessing = true
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                isProcessing = false
                                onSubscribe()
                            }
                        } label: {
                            Group {
                                if isProcessing {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.9)
                                        Text("Processing...")
                                    }
                                } else {
                                    Text(selectedPlan == .monthly ? "Subscribe — ₹299/mo" : "Subscribe — ₹2,499/yr")
                                }
                            }
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .shadow(color: .orange.opacity(0.4), radius: 12, y: 4)
                        }
                        .disabled(isProcessing)
                        .opacity(isProcessing ? 0.8 : 1)

                        // Trust badges
                        VStack(spacing: 8) {
                            HStack(spacing: 24) {
                                PaywallTrustBadge(icon: "checkmark.circle.fill", text: "Cancel anytime")
                                PaywallTrustBadge(icon: "lock.shield.fill",     text: "Secure payment")
                            }
                            Text("7-day money-back guarantee")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        // Testimonial
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 40, height: 40)
                                Text("R")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("★★★★★").foregroundStyle(.yellow).font(.system(size: 14))
                                Text("""
                                     "Premium helped me improve my JEE rank by 5000 positions! \
                                     The unlimited questions and offline packs are amazing."
                                     """)
                                .font(.system(size: 13))
                                .foregroundStyle(.white)
                                Text("– Rahul, JEE 2025 Aspirant")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 48)
                }
            }
        }
        .onAppear {
            AppLogger.navigated(to: "PaywallView",
                                from: "plan=\(selectedPlan == .monthly ? "monthly" : "annual")")
        }
    }
}

// MARK: - Plan Button

private struct PlanButton: View {
    let title: String
    let subtitle: String
    let price: String
    let period: String
    let badge: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(isSelected ? .black : .white)
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(isSelected ? .gray : .white.opacity(0.7))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(price)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(isSelected ? .black : .white)
                        Text(period)
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? .gray : .white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(isSelected ? Color.white : Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isSelected ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: isSelected ? .black.opacity(0.12) : .clear, radius: 12, y: 4)
                .scaleEffect(isSelected ? 1.02 : 1.0)

                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(Capsule())
                        .shadow(color: .orange.opacity(0.4), radius: 4, y: 2)
                        .offset(x: -8, y: -10)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct PaywallTrustBadge: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
