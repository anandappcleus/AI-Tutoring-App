//
//  LoginViewModel.swift
//  SmartTutor
//
//  Sprint 5 — Login form state. Delegates auth to AppState.
//

import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.smarttutor.app", category: "LoginViewModel")

@MainActor
final class LoginViewModel: ObservableObject {

    // MARK: - Form inputs

    @Published var email: String = ""
    @Published var password: String = ""

    // MARK: - Derived

    var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    // MARK: - Actions

    /// Calls AppState.login() — loading state and error are on AppState.
    func submit(appState: AppState) async {
        let cleanEmail = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("LoginViewModel.submit  email=\(cleanEmail)")
        await appState.login(email: cleanEmail, password: password)
    }
}
