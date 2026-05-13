//
//  StudyViewModel.swift
//  SmartTutor
//
//  Sprint 5 — MVVM ViewModel for StudyView.
//
//  Responsibilities:
//    • Calls POST /ask via APIClient and publishes the answer to StudyView.
//    • Enforces the freemium 10-question/day limit locally (mirrored on server).
//    • Queues the answered question into OfflineSyncManager after every ask.
//    • Exposes structured ViewState so the View has a single source of truth.
//    • All network calls are async/await; errors are mapped to user-friendly strings.
//    • Dependency-injected for testability (APIClient + OfflineSyncManaging).
//
//  MVVM contract:
//    View  → calls vm.ask(question:)  and  vm.reset()
//    View  ← observes vm.messages, vm.viewState, vm.questionsUsedToday
//

import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.smarttutor.app", category: "StudyViewModel")

// MARK: - View State

enum StudyViewState: Equatable {
    case idle
    case loading
    case error(String)  // user-visible message
}

// MARK: - Chat Message (ViewModel layer model)

struct StudyMessage: Identifiable, Equatable {
    enum Role: Equatable { case user, assistant }
    let id: UUID
    let role: Role
    let text: String
    /// Full parsed response — nil for user messages and raw-output fallbacks
    let response: AskResponse?

    init(role: Role, text: String, response: AskResponse? = nil) {
        self.id       = UUID()
        self.role     = role
        self.text     = text
        self.response = response
    }
}

// MARK: - ViewModel

@MainActor
final class StudyViewModel: ObservableObject {

    // MARK: Published outputs (View binds to these)

    @Published private(set) var messages: [StudyMessage] = []
    @Published private(set) var viewState: StudyViewState = .idle
    @Published private(set) var questionsUsedToday: Int = 0

    // MARK: Constants

    static let freeDailyLimit = 10

    // MARK: Dependencies (injected for testability)

    private let apiClient: APIClient
    private let syncManager: OfflineSyncManaging
    private let profile: () -> StudentProfile?  // closure so tests can swap easily

    // MARK: Init

    init(
        apiClient: APIClient = .shared,
        syncManager: OfflineSyncManaging? = nil,
        profile: @escaping () -> StudentProfile? = { StudentProfile.load() }
    ) {
        self.apiClient   = apiClient
        self.syncManager = syncManager ?? OfflineSyncManager()
        self.profile     = profile

        appendWelcomeMessage()
        logger.info("StudyViewModel: initialised")
    }

    // MARK: - Public API

    /// Submit a student question. Returns immediately; answer appended asynchronously.
    func ask(question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logger.warning("StudyViewModel.ask: empty question — ignored")
            return
        }
        guard viewState != .loading else {
            logger.warning("StudyViewModel.ask: already loading — ignored")
            return
        }

        // Local freemium gate — real gate also enforced server-side (HTTP 429)
        let isPremium = profile()?.isPremium ?? false
        if !isPremium && questionsUsedToday >= Self.freeDailyLimit {
            logger.info("StudyViewModel.ask: daily limit reached  used=\(self.questionsUsedToday)")
            // Caller (View) should show Paywall on this state; we also record it as error
            viewState = .error("daily_limit_reached")
            return
        }

        let language = profile()?.preferredLanguage.rawValue  // nil → server default

        logger.info("StudyViewModel.ask  lang=\(language ?? "default")  q=\(trimmed.prefix(80))")

        messages.append(StudyMessage(role: .user, text: trimmed))
        viewState = .loading

        Task { [weak self] in
            await self?.performAsk(trimmed: trimmed, language: language)
        }
    }

    /// Clear error state so the user can retry.
    func dismissError() {
        if case .error = viewState { viewState = .idle }
    }

    /// Reset conversation (e.g. user taps "New Chat").
    func reset() {
        messages.removeAll()
        viewState = .idle
        appendWelcomeMessage()
        logger.info("StudyViewModel.reset")
    }

    // MARK: - Private

    private func performAsk(trimmed: String, language: String?) async {
        do {
            let response: AskResponse = try await apiClient.request(
                .ask(question: trimmed, language: language)
            )

            let answerText = buildAnswerText(from: response)
            messages.append(StudyMessage(role: .assistant, text: answerText, response: response))
            viewState = .idle
            questionsUsedToday += 1

            // Persist to offline queue for /sync-answers upload
            syncManager.enqueue(question: trimmed, topic: nil, subject: nil)

            logger.info("StudyViewModel.performAsk: success  questions_today=\(self.questionsUsedToday)")

        } catch let apiError as APIError {
            logger.error("StudyViewModel.performAsk: APIError=\(apiError.localizedDescription ?? "")")
            handleAPIError(apiError, question: trimmed)
        } catch {
            logger.error("StudyViewModel.performAsk: unexpected=\(error.localizedDescription)")
            messages.append(StudyMessage(
                role: .assistant,
                text: "Something went wrong. Please try again."
            ))
            viewState = .idle
        }
    }

    private func handleAPIError(_ error: APIError, question: String) {
        switch error {
        case .noNetwork:
            // Queue offline and show a friendly fallback message
            syncManager.enqueue(question: question, topic: nil, subject: nil)
            messages.append(StudyMessage(
                role: .assistant,
                text: "You're offline. Your question has been saved and will be answered when you reconnect."
            ))
            viewState = .idle

        case .unauthorized:
            // Session expired — signal the View to navigate to login
            viewState = .error("unauthorized")

        case .serverError(let code, _) where code == 429:
            viewState = .error("daily_limit_reached")

        case .serverError:
            messages.append(StudyMessage(
                role: .assistant,
                text: error.userMessage
            ))
            viewState = .idle

        default:
            messages.append(StudyMessage(role: .assistant, text: error.userMessage))
            viewState = .idle
        }
    }

    /// Format the structured AskResponse into a readable chat string.
    private func buildAnswerText(from response: AskResponse) -> String {
        var parts: [String] = [response.explanation]

        if !response.workedExample.isEmpty {
            parts.append("\n\n📘 Example:\n\(response.workedExample)")
        }

        if !response.practiceProblems.isEmpty {
            let problems = response.practiceProblems.enumerated().map { i, p in
                "Q\(i + 1): \(p.question)\nA: \(p.answer)"
            }.joined(separator: "\n\n")
            parts.append("\n\n✏️ Practice:\n\(problems)")
        }

        return parts.joined()
    }

    private func appendWelcomeMessage() {
        let lang = profile()?.preferredLanguage ?? .english
        let greeting: String
        switch lang {
        case .bengali:
            greeting = "নমস্কার! আমি আপনার AI শিক্ষক। আপনার যেকোনো প্রশ্ন জিজ্ঞাসা করুন।"
        case .hindi:
            greeting = "नमस्ते! मैं आपका AI शिक्षक हूं। कोई भी प्रश्न पूछें।"
        default:
            greeting = "Hello! I'm your AI tutor. Ask me any question about JEE, NEET, or your board exams."
        }
        messages.append(StudyMessage(role: .assistant, text: greeting))
    }
}
