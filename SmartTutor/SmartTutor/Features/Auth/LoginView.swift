//
//  LoginView.swift
//  SmartTutor
//
//  Sprint 5 — Beautiful login screen.
//  Design mirrors OnboardingView: indigo→purple→pink gradient, white card, bold type.
//

import SwiftUI

// MARK: - Reusable text field (also used in RegisterView)

struct AuthFieldView: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .sentences

    @State private var showSecure = false

    private let accent = Color(red: 0.36, green: 0.33, blue: 0.93)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(accent)

            HStack(spacing: 8) {
                Group {
                    if isSecure && !showSecure {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                            .keyboardType(keyboardType)
                            .textInputAutocapitalization(autocapitalization)
                            .autocorrectionDisabled()
                    }
                }
                .textContentType(textContentType)

                if isSecure {
                    Button {
                        showSecure.toggle()
                    } label: {
                        Image(systemName: showSecure ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                            .frame(width: 28, height: 28)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Login View

struct LoginView: View {

    @StateObject private var vm = LoginViewModel()
    @EnvironmentObject private var appState: AppState
    @State private var showRegister = false

    // Brand gradient — matches OnboardingView exactly
    private let gradientColors: [Color] = [
        Color(red: 0.36, green: 0.33, blue: 0.93),
        Color(red: 0.58, green: 0.28, blue: 0.91),
        Color(red: 0.93, green: 0.33, blue: 0.58),
    ]

    var body: some View {
        NavigationStack {
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

                        // MARK: Hero header
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(width: 96, height: 96)
                                    .shadow(color: .white.opacity(0.3), radius: 16)
                                Image(systemName: "brain.head.profile")
                                    .font(.system(size: 48, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            .padding(.top, 64)

                            Text("SmartTutor")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.white)

                            Text("AI Tutor for JEE, NEET & Board Exams")
                                .font(.system(size: 15))
                                .foregroundColor(.white.opacity(0.85))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.bottom, 40)

                        // MARK: Auth card
                        VStack(spacing: 20) {

                            // Error banner
                            if let error = appState.loginError {
                                HStack(spacing: 10) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text(error)
                                        .font(.system(size: 14))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    Color.red.opacity(0.85)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                )
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }

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
                            AuthFieldView(
                                title: "Password",
                                placeholder: "Enter your password",
                                text: $vm.password,
                                isSecure: true,
                                textContentType: .password
                            )

                            // Sign In button
                            Button {
                                Task { await vm.submit(appState: appState) }
                            } label: {
                                ZStack {
                                    if appState.isLoggingIn {
                                        ProgressView()
                                            .tint(Color(red: 0.58, green: 0.28, blue: 0.91))
                                    } else {
                                        Text("Sign In")
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
                        .shadow(
                            color: Color.black.opacity(0.12),
                            radius: 24, y: 8
                        )
                        .padding(.horizontal, 20)

                        // MARK: Register link
                        Button {
                            showRegister = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("Don't have an account?")
                                    .foregroundColor(.white.opacity(0.85))
                                Text("Sign Up")
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
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $showRegister) {
                RegisterView()
            }
            .animation(.easeInOut(duration: 0.3), value: appState.loginError)
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AppState())
}
