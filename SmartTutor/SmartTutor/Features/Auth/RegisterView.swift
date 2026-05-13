//
//  RegisterView.swift
//  SmartTutor
//
//  Sprint 5 — Registration screen.
//  Design mirrors LoginView (same brand gradient).
//

import SwiftUI

struct RegisterView: View {

    @StateObject private var vm = RegisterViewModel()
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private let gradientColors: [Color] = [
        Color(red: 0.36, green: 0.33, blue: 0.93),
        Color(red: 0.58, green: 0.28, blue: 0.91),
        Color(red: 0.93, green: 0.33, blue: 0.58),
    ]

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // MARK: Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 72, height: 72)
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 32, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(.top, 32)

                        Text("Create Account")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)

                        Text("Join thousands of students preparing for JEE & NEET")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 32)

                    // MARK: Form card
                    VStack(spacing: 18) {

                        // Error banner
                        if let error = vm.errorMessage {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                Text(error)
                                    .font(.system(size: 14))
                                Spacer()
                                Button {
                                    vm.clearError()
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .bold))
                                }
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // Full name
                        AuthFieldView(
                            title: "Full Name",
                            placeholder: "Your name",
                            text: $vm.name,
                            textContentType: .name
                        )

                        // Email
                        AuthFieldView(
                            title: "Email Address",
                            placeholder: "you@example.com",
                            text: $vm.email,
                            keyboardType: .emailAddress,
                            textContentType: .emailAddress,
                            autocapitalization: .never
                        )

                        // Password
                        VStack(spacing: 0) {
                            AuthFieldView(
                                title: "Password",
                                placeholder: "At least 6 characters",
                                text: $vm.password,
                                isSecure: true,
                                textContentType: .newPassword
                            )
                            if !vm.password.isEmpty && vm.password.count < 6 {
                                Text("Password must be at least 6 characters")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 4)
                            }
                        }

                        // Confirm password
                        VStack(spacing: 0) {
                            AuthFieldView(
                                title: "Confirm Password",
                                placeholder: "Re-enter your password",
                                text: $vm.confirmPassword,
                                isSecure: true,
                                textContentType: .newPassword
                            )
                            if vm.passwordMismatch {
                                Text("Passwords do not match")
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 4)
                            }
                        }

                        // Language picker
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Learning Language")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color(red: 0.36, green: 0.33, blue: 0.93))

                            Picker("Language", selection: $vm.selectedLanguage) {
                                ForEach(vm.languages, id: \.code) { lang in
                                    Text(lang.label).tag(lang.code)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .tint(Color(red: 0.36, green: 0.33, blue: 0.93))
                        }

                        // Create Account button
                        Button {
                            Task { await vm.submit(appState: appState) }
                        } label: {
                            ZStack {
                                if vm.isLoading || appState.isLoggingIn {
                                    ProgressView()
                                        .tint(Color(red: 0.58, green: 0.28, blue: 0.91))
                                } else {
                                    Text("Create Account")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.36, green: 0.33, blue: 0.93),
                                                    Color(red: 0.58, green: 0.28, blue: 0.91),
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .shadow(
                                color: Color(red: 0.58, green: 0.28, blue: 0.91).opacity(0.35),
                                radius: 12, y: 4
                            )
                        }
                        .disabled(!vm.canSubmit || appState.isLoggingIn)
                        .opacity(!vm.canSubmit || appState.isLoggingIn ? 0.6 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: vm.canSubmit)
                    }
                    .padding(24)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .shadow(color: Color.black.opacity(0.12), radius: 24, y: 8)
                    .padding(.horizontal, 20)

                    // MARK: Back to login
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Already have an account?")
                                .foregroundColor(.white.opacity(0.85))
                            Text("Sign In")
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .underline()
                        }
                        .font(.system(size: 15))
                    }
                    .padding(.top, 28)
                    .padding(.bottom, 52)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Sign In")
                            .font(.system(size: 16))
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: vm.errorMessage)
    }
}

#Preview {
    NavigationStack {
        RegisterView()
            .environmentObject(AppState())
    }
}
