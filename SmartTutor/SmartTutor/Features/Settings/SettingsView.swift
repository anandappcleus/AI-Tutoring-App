//
//  SettingsView.swift
//  SmartTutor
//
//  Converted from SettingsScreen.tsx
//  Profile card, preference toggles, account/support rows, logout.
//

import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @AppStorage("soundEffectsEnabled") private var soundEffectsEnabled = true
    @State private var showLanguagePicker = false
    @State private var showEditProfile    = false
    @State private var showPrivacy        = false
    @State private var showHelp           = false

    private var notificationsEnabled: Binding<Bool> {
        Binding {
            notificationStatus == .authorized
        } set: { newValue in
            Task { await handleNotificationsToggle(newValue) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Gradient header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.system(size: 24, weight: .bold))
                    Text("Manage your account & preferences")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.white)
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
                        Button { showEditProfile = true } label: {
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
                                    Text(String((appState.currentProfile?.name ?? "?").prefix(1)))
                                        .font(.system(size: 26, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(appState.currentProfile?.name ?? "—")
                                        .font(.system(size: 17, weight: .bold))
                                    Text(appState.currentProfile?.email ?? "—")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(10)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.vertical, 16)

                        HStack(spacing: 0) {
                            ProfileMetaCell(label: "Preparing for", value: appState.currentProfile?.examTarget.displayName ?? "—")
                            Divider().frame(height: 40)
                            ProfileMetaCell(label: "Language", value: appState.currentProfile?.preferredLanguage.displayName ?? "—")
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
                            title: "Language", subtitle: appState.currentProfile?.preferredLanguage.displayName ?? "—",
                            action: { showLanguagePicker = true }
                        )
                        Divider().padding(.leading, 68)
                        SettingsToggleRow(
                            icon: "bell.fill", iconBg: .yellow,
                            title: "Push Notifications", subtitle: "Daily study reminders",
                            isOn: notificationsEnabled
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
                            title: "Edit Profile", subtitle: "Update your information",
                            action: { showEditProfile = true }
                        )
                        Divider().padding(.leading, 68)
                        SettingsNavRow(
                            icon: "shield.fill", iconBg: .orange,
                            title: "Privacy & Security", subtitle: "Manage your data",
                            action: { showPrivacy = true }
                        )
                        Divider().padding(.leading, 68)
                        SettingsNavRow(
                            icon: "questionmark.circle.fill", iconBg: .teal,
                            title: "Help & Support", subtitle: "FAQs and contact us",
                            action: { showHelp = true }
                        )
                    }

                    // About
                    VStack(spacing: 4) {
                        Text("SmartTutor")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        Text("Version \(AppConfig.appVersion)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary.opacity(0.7))
                        Text("© 2026 SmartTutor. All rights reserved.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .background(Color(UIColor.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)

                    // Logout
                    Button {
                        appState.logout()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Log Out")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.red)
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
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationStatus = settings.authorizationStatus
        }
        .sheet(isPresented: $showLanguagePicker) { LanguagePickerSheet().environmentObject(appState) }
        .sheet(isPresented: $showEditProfile)    { EditProfileSheet().environmentObject(appState)    }
        .sheet(isPresented: $showPrivacy)        { PrivacySheetView()                                }
        .sheet(isPresented: $showHelp)           { HelpSheetView()                                   }
    }

    // MARK: - Notifications

    private func handleNotificationsToggle(_ enable: Bool) async {
        let center = UNUserNotificationCenter.current()
        if enable {
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
                notificationStatus = granted ? .authorized : .denied
            case .denied:
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    await UIApplication.shared.open(url)
                }
            case .authorized, .provisional, .ephemeral:
                notificationStatus = .authorized
            @unknown default:
                break
            }
        } else {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
        }
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
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
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
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(iconBg.opacity(0.15)).frame(width: 40, height: 40)
                    Image(systemName: icon).foregroundStyle(iconBg).font(.system(size: 17))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
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
                Image(systemName: icon).foregroundStyle(iconBg).font(.system(size: 17))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
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
                Image(systemName: icon).foregroundStyle(iconBg).font(.system(size: 17))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
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

// MARK: - Sheet Views

private struct LanguagePickerSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            List(StudentProfile.Language.allCases) { lang in
                Button {
                    Task {
                        isSaving = true
                        await appState.updateProfile(language: lang.rawValue)
                        isSaving = false
                        dismiss()
                    }
                } label: {
                    HStack {
                        Text(lang.displayName).foregroundStyle(.primary)
                        Spacer()
                        if lang == appState.currentProfile?.preferredLanguage {
                            Image(systemName: "checkmark").foregroundStyle(.indigo)
                        }
                    }
                }
            }
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .disabled(isSaving)
            .overlay { if isSaving { ProgressView() } }
        }
    }
}

private struct EditProfileSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Display Name") {
                    TextField("Your name", text: $name)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task {
                            isSaving = true
                            await appState.updateProfile(name: name.trimmingCharacters(in: .whitespaces))
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .disabled(isSaving)
        }
        .onAppear { name = appState.currentProfile?.name ?? "" }
    }
}

private struct PrivacySheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your Privacy").font(.title2.bold())
                    Text("SmartTutor collects only the data needed to personalise your learning experience — your name, email, exam target, and session history. We never sell your data to third parties.")
                    Text("You may request deletion of your account and all associated data by contacting support@smarttutor.app.")
                }
                .padding()
            }
            .navigationTitle("Privacy & Security")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct HelpSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Frequently Asked Questions").font(.headline)
                        Group {
                            Text("**How does the AI tutor work?**\nAsk any JEE/NEET question in your preferred language and the AI answers with step-by-step explanations.")
                            Text("**What are Offline Packs?**\nDownload topic packs to study without an internet connection.")
                            Text("**How is my study plan generated?**\nThe AI crew analyses your progress nightly and creates a personalised plan at 2 AM IST.")
                        }
                        .font(.system(size: 14))
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Contact Us").font(.headline)
                        Link("support@smarttutor.app",
                             destination: URL(string: "mailto:support@smarttutor.app")!)
                            .font(.system(size: 15))
                    }
                }
                .padding()
            }
            .navigationTitle("Help & Support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
