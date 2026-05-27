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
    @Environment(AppState.self) private var appState
    @ObservedObject private var appearanceManager = AppearanceManager.shared
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
        ZStack {
            // Full-screen gradient — NowAssist design system
            LinearGradient(
                gradient: Gradient(colors: AppColors.gradientColors),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

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

                VStack(spacing: 16) {
                    // Profile card
                    VStack(spacing: 0) {
                        Button {
                            AppLogger.userAction(AppLogger.auth, action: "edit-profile-opened",
                                                 context: "profile-card")
                            showEditProfile = true
                        } label: {
                            HStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: AppColors.gradientColors),
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
                                        .foregroundStyle(AppColors.textPrimary)
                                    Text(appState.currentProfile?.email ?? "—")
                                        .font(.system(size: 14))
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .padding(10)
                                    .background(AppColors.cardBackgroundSecondary)
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
                    .background(AppColors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    // Preferences section
                    SettingsGroupBox(title: "Preferences") {
                        SettingsNavRow(
                            icon: "globe", iconBg: .blue,
                            title: "Language", subtitle: appState.currentProfile?.preferredLanguage.displayName ?? "—",
                            action: {
                                AppLogger.userAction(AppLogger.auth, action: "settings-language-opened")
                                showLanguagePicker = true
                            }
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

                    // Appearance section — ported from NowAssist
                    SettingsGroupBox(title: "Appearance") {
                        ForEach(Array(AppearanceMode.allCases.enumerated()), id: \.element) { idx, mode in
                            Button {
                                appearanceManager.appearanceMode = mode
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: mode.icon)
                                        .font(.system(size: 18))
                                        .foregroundStyle(AppColors.accent)
                                        .frame(width: 36, height: 36)
                                    Text(mode.rawValue)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if appearanceManager.appearanceMode == mode {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(AppColors.accent)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
                            if idx < AppearanceMode.allCases.count - 1 {
                                Divider().padding(.leading, 68)
                            }
                        }
                    }

                    // Account & support
                    SettingsGroupBox(title: "Account & Support") {
                        SettingsNavRow(
                            icon: "person.fill", iconBg: .indigo,
                            title: "Edit Profile", subtitle: "Update your information",
                            action: {
                                AppLogger.userAction(AppLogger.auth, action: "edit-profile-opened",
                                                     context: "account-row")
                                showEditProfile = true
                            }
                        )
                        Divider().padding(.leading, 68)
                        SettingsNavRow(
                            icon: "shield.fill", iconBg: .orange,
                            title: "Privacy & Security", subtitle: "Manage your data",
                            action: {
                                AppLogger.userAction(AppLogger.auth, action: "privacy-opened")
                                showPrivacy = true
                            }
                        )
                        Divider().padding(.leading, 68)
                        SettingsNavRow(
                            icon: "questionmark.circle.fill", iconBg: .teal,
                            title: "Help & Support", subtitle: "FAQs and contact us",
                            action: {
                                AppLogger.userAction(AppLogger.auth, action: "help-opened")
                                showHelp = true
                            }
                        )
                    }

                    // About
                    VStack(spacing: 4) {
                        Text("SmartTutor")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.textSecondary)
                        Text("Version \(AppConfig.appVersion)")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.textSecondary.opacity(0.8))
                        Text("© 2026 SmartTutor. All rights reserved.")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.textSecondary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .background(AppColors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    // Logout
                    Button {
                        AppLogger.userAction(AppLogger.auth, action: "logout-tapped")
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
        .scrollContentBackground(.hidden)
        } // ZStack
        .ignoresSafeArea(edges: .top)
        .task {
            AppLogger.navigated(to: "SettingsView")
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationStatus = settings.authorizationStatus
        }
        .sheet(isPresented: $showLanguagePicker) { LanguagePickerSheet().environment(appState) }
        .sheet(isPresented: $showEditProfile)    { EditProfileSheet().environment(appState)    }
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
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
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
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
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
                    Circle().fill(iconBg.opacity(0.25)).frame(width: 40, height: 40)
                    Image(systemName: icon).foregroundStyle(iconBg).font(.system(size: 17))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppColors.textPrimary)
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
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
                Circle().fill(iconBg.opacity(0.25)).frame(width: 40, height: 40)
                Image(systemName: icon).foregroundStyle(iconBg).font(.system(size: 17))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppColors.textPrimary)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().tint(AppColors.accent)
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
                Circle().fill(iconBg.opacity(0.25)).frame(width: 40, height: 40)
                Image(systemName: icon).foregroundStyle(iconBg).font(.system(size: 17))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppColors.textPrimary)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(AppColors.textSecondary)
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
    @Environment(AppState.self) var appState
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
    @Environment(AppState.self) var appState
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
