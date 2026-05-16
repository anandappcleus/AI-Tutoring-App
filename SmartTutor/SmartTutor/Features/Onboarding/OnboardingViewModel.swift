//
//  OnboardingViewModel.swift
//  SmartTutor
//
//  Sprint 6 — ViewModel for the 3-step onboarding flow.
//
//  Responsibilities:
//    • Owns form state: step, selectedLanguage, selectedExam, name.
//    • Validates each step via canProceed.
//    • Calls AppState.updateProfile on final submission; publishes isComplete.
//    • Tracks isSubmitting so the View can show a loading state.
//
//  MVVM contract:
//    View  → calls vm.advance()  and  vm.submit(via: appState)
//    View  ← observes vm.step, vm.canProceed, vm.isSubmitting, vm.isComplete
//

import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.smarttutor.app", category: "OnboardingViewModel")

@MainActor
@Observable final class OnboardingViewModel {

    // MARK: - Form state (View binds to these)

    var step: Int = 1
    var selectedLanguage: String = ""
    var selectedExam: String = ""
    var name: String = ""

    // MARK: - Submission state

    private(set) var isSubmitting: Bool = false
    private(set) var isComplete: Bool = false

    // MARK: - Validation

    var canProceed: Bool {
        switch step {
        case 1: return !selectedLanguage.isEmpty
        case 2: return !selectedExam.isEmpty
        case 3: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        default: return false
        }
    }

    // MARK: - Actions

    /// Advances to the next step if canProceed is true.
    func advance() {
        guard canProceed, step < 3 else { return }
        step += 1
    }

    /// Called on the final step. Persists language + exam preference via AppState,
    /// then signals completion via isComplete.
    func submit(via appState: AppState) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        let lang        = selectedLanguage.isEmpty ? "en" : selectedLanguage
        let exam        = selectedExam.isEmpty ? "JEE" : selectedExam.uppercased()
        let displayName = name.trimmingCharacters(in: .whitespaces)

        logger.info("OnboardingViewModel.submit: lang=\(lang) exam=\(exam) name=\(displayName)")

        await appState.updateProfile(
            language: lang,
            examTarget: exam,
            name: displayName.isEmpty ? nil : displayName
        )

        isComplete = true
        logger.info("OnboardingViewModel.submit: complete")
    }
}
