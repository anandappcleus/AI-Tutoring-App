//
//  RegisterViewModel.swift
//  SmartTutor
//
//  Sprint 5 — Registration form state.
//  Calls POST /auth/register then auto-logs in via AppState.
//

import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.smarttutor.app", category: "RegisterViewModel")

@MainActor
final class RegisterViewModel: ObservableObject {

    // MARK: - Form inputs

    @Published var name: String = ""
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var confirmPassword: String = ""
    @Published var selectedLanguage: String = "en"

    // MARK: - State

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String? = nil

    // MARK: - Language options

    let languages: [(code: String, label: String)] = [
        ("en", "🇬🇧  English"),
        ("bn", "🇮🇳  বাংলা (Bengali)"),
        ("hi", "🇮🇳  हिन्दी (Hindi)"),
        ("ta", "🇮🇳  தமிழ் (Tamil)"),
        ("te", "🇮🇳  తెలుగు (Telugu)"),
        ("mr", "🇮🇳  मराठी (Marathi)"),
    ]

    // MARK: - Validation

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && password.count >= 6
            && password == confirmPassword
            && !isLoading
    }

    var passwordMismatch: Bool {
        !confirmPassword.isEmpty && password != confirmPassword
    }

    // MARK: - Actions

    func submit(appState: AppState) async {
        guard canSubmit else { return }
        isLoading = true
        errorMessage = nil

        let cleanEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName  = name.trimmingCharacters(in: .whitespacesAndNewlines)

        let language = self.selectedLanguage
        logger.info("RegisterViewModel.submit  email=\(cleanEmail)  lang=\(language)")

        do {
            // Step 1: Create account (returns StudentResponse with HTTP 201)
            let _: StudentResponse = try await APIClient.shared.request(
                .register(
                    name: cleanName,
                    email: cleanEmail,
                    password: password,
                    language: language,
                    examTarget: "JEE"   // default; user selects exam in Onboarding
                )
            )
            logger.info("RegisterViewModel.submit: account created  email=\(cleanEmail)")

            // Step 2: Authenticate immediately
            await appState.login(email: cleanEmail, password: password)
            if let loginErr = appState.loginError {
                errorMessage = loginErr
                logger.error("RegisterViewModel.submit: auto-login failed  \(loginErr)")
            }

        } catch let apiError as APIError {
            logger.error("RegisterViewModel.submit: APIError=\(apiError.localizedDescription ?? "")")
            errorMessage = apiError.userMessage
        } catch {
            logger.error("RegisterViewModel.submit: unexpected=\(error.localizedDescription)")
            errorMessage = "Registration failed. Please try again."
        }

        isLoading = false
    }

    func clearError() {
        errorMessage = nil
    }
}
