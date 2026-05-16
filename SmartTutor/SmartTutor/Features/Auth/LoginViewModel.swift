//
//  LoginViewModel.swift
//  SmartTutor
//
//  Sprint 5 — Login form state. Delegates auth to AppState.
//

import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.smarttutor.app", category: "LoginViewModel")

@MainActor
@Observable final class LoginViewModel {

    // MARK: - Form inputs

    var email: String = ""
    var password: String = ""

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
