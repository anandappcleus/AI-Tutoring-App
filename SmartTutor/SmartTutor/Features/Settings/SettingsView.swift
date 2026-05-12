//
//  SettingsView.swift
//  SmartTutor
//
//  Converted from SettingsScreen.tsx
//  Profile card, preference toggles, account/support rows, logout.
//

import SwiftUI

struct SettingsView: View {
    @State private var notificationsEnabled = true
    @State private var soundEffectsEnabled  = true

    private let profile = (
        name:     "Riya Sharma",
        email:    "riya.sharma@email.com",
        exam:     "JEE Mains 2026",
        language: "Bengali",
        joined:   "March 2026"
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Gradient header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.system(size: 24, weight: .bold))
                    Text("Manage your account & preferences")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 36)
                .background(
                    LinearGradient(
                        colors: [.indigo, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

                VStack(spacing: 16) {
                    // Profile card
                    VStack(spacing: 0) {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.indigo, .purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 64, height: 64)
                                Text(String(profile.name.prefix(1)))
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.name)
                                    .font(.system(size: 17, weight: .bold))
                                Text(profile.email)
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(10)
                                .background(Color(UIColor.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        Divider().padding(.vertical, 16)

                        HStack(spacing: 0) {
                            ProfileMetaCell(label: "Preparing for", value: profile.exam)
                            Divider().frame(height: 40)
                            ProfileMetaCell(label: "Member since", value: profile.joined)
                        }
                    }
                    .padding(20)
                    .background(Color(UIColor.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)

                    // Preferences section
                    SettingsGroupBox(title: "Preferences") {
                        SettingsNavRow(
                            icon: "globe", iconBg: .blue,
                            title: "Language", subtitle: profile.language
                        )
                        Divider().padding(.leading, 68)
                        SettingsToggleRow(
                            icon: "bell.fill", iconBg: .yellow,
                            title: "Push Notifications", subtitle: "Daily study reminders",
                            isOn: $notificationsEnabled
                        )
                        Divider().padding(.leading, 68)
                        SettingsDisabledRow(
                            icon: "moon.fill", iconBg: .purple,
                            title: "Dark Mode", subtitle: "Coming soon"
                        )
                        Divider().padding(.leading, 68)
                        SettingsToggleRow(
                            icon: "speaker.wave.2.fill", iconBg: .green,
                            title: "Sound Effects", subtitle: "Feedback sounds",
                            isOn: $soundEffectsEnabled
                        )
                    }

                    // Account & support
                    SettingsGroupBox(title: "Account & Support") {
                        SettingsNavRow(
                            icon: "person.fill", iconBg: .indigo,
                            title: "Edit Profile", subtitle: "Update your information"
                        )
                        Divider().padding(.leading, 68)
                        SettingsNavRow(
                            icon: "shield.fill", iconBg: .orange,
                            title: "Privacy & Security", subtitle: "Manage your data"
                        )
                        Divider().padding(.leading, 68)
                        SettingsNavRow(
                            icon: "questionmark.circle.fill", iconBg: .teal,
                            title: "Help & Support", subtitle: "FAQs and contact us"
                        )
                    }

                    // About
                    VStack(spacing: 4) {
                        Text("SmartTutor")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Text("Version \(AppConfig.appVersion)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.7))
                        Text("© 2026 SmartTutor. All rights reserved.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .background(Color(UIColor.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)

                    // Logout
                    Button {
                        // Logout action
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Log Out")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, -16)
                .padding(.bottom, 40)
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Supporting Components

private struct ProfileMetaCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SettingsGroupBox<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
    }
}

private struct SettingsNavRow: View {
    let icon: String
    let iconBg: Color
    let title: String
    let subtitle: String

    var body: some View {
        Button {
            // navigation action
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(iconBg.opacity(0.15)).frame(width: 40, height: 40)
                    Image(systemName: icon).foregroundColor(iconBg).font(.system(size: 17))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(.primary)
                    Text(subtitle).font(.system(size: 13)).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsToggleRow: View {
    let icon: String
    let iconBg: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(iconBg.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: icon).foregroundColor(iconBg).font(.system(size: 17))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(subtitle).font(.system(size: 13)).foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().tint(.indigo)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

private struct SettingsDisabledRow: View {
    let icon: String
    let iconBg: Color
    let title: String
    let subtitle: String
    @State private var value = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(iconBg.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: icon).foregroundColor(iconBg).font(.system(size: 17))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(subtitle).font(.system(size: 13)).foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $value)
                .labelsHidden()
                .disabled(true)
                .opacity(0.4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
