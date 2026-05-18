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

import Foundation
import Observation
import os.log
import UIKit

private let logger = Logger(subsystem: "com.smarttutor.app", category: "StudyViewModel")

// MARK: - View State

enum StudyViewState: Equatable {
    case idle
    case loading
    case error(String)  // user-visible message
}

// MARK: - Pending Image Store

/// Carries a UIImage from the Dashboard camera sheet to StudyView across the tab boundary.
/// The ViewModel claims and clears it immediately in `ask()`.
final class PendingImageStore {
    static let shared = PendingImageStore()
    var image: UIImage?
    var imageBase64: String?
    private init() {}
}

// MARK: - Chat Message (ViewModel layer model)

struct StudyMessage: Identifiable, Equatable {
    enum Role: Equatable { case user, assistant }
    let id: UUID
    let role: Role
    let text: String
    /// Thumbnail image attached by the user (camera input). nil for text-only messages.
    let image: UIImage?
    /// Full parsed response — nil for user messages and raw-output fallbacks
    let response: AskResponse?

    init(role: Role, text: String, image: UIImage? = nil, response: AskResponse? = nil) {
        self.id       = UUID()
        self.role     = role
        self.text     = text
        self.image    = image
        self.response = response
    }

    // UIImage is not Equatable; identity comparison via id is sufficient.
    static func == (lhs: StudyMessage, rhs: StudyMessage) -> Bool { lhs.id == rhs.id }
}

// MARK: - ViewModel

@MainActor
@Observable final class StudyViewModel {

    // MARK: Published outputs (View binds to these)

    private(set) var messages: [StudyMessage] = []
    private(set) var viewState: StudyViewState = .idle
    private(set) var questionsUsedToday: Int = 0

    // MARK: Conversation history (sent to backend for multi-turn context)

    /// Prior Q&A turns kept in memory; sent with every /ask request so the
    /// LLM can handle follow-up questions like "explain step 2 again".
    /// Capped at 10 turns (5 Q&A pairs). Loaded from the server on init.
    private var conversationHistory: [ConversationTurn] = []

    // MARK: Constants

    static let freeDailyLimit = 10

    /// Guards against calling GET /ask/history more than once per app session.
    /// The ViewModel may be re-created (e.g. when the SwiftUI hierarchy is rebuilt
    /// after a silent token-refresh), but we only want one history fetch per launch.
    private static var hasLoadedSessionHistory = false

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
        self.syncManager = syncManager ?? OfflineSyncManager.shared
        self.profile     = profile

        appendWelcomeMessage()
        logger.info("StudyViewModel: initialised")

        // Restore last session from Redis (non-blocking, non-fatal)
        Task { [weak self] in await self?.loadPreviousSession() }
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

        let language = profile()?.preferredLanguage.rawValue ?? "en"  // default to English

        logger.info("StudyViewModel.ask  lang=\(language)  q=\(trimmed.prefix(80))")

        // Claim the image (if any) queued by the camera sheet before this ask.
        let pendingImage = PendingImageStore.shared.image
        PendingImageStore.shared.image = nil
        let pendingImageBase64 = PendingImageStore.shared.imageBase64
        PendingImageStore.shared.imageBase64 = nil

        messages.append(StudyMessage(role: .user, text: trimmed, image: pendingImage))
        viewState = .loading

        Task { [weak self] in
            await self?.performAsk(trimmed: trimmed, language: language, imageBase64: pendingImageBase64)
        }
    }

    /// Clear error state so the user can retry.
    func dismissError() {
        if case .error = viewState { viewState = .idle }
    }

    /// Reset conversation (e.g. user taps "New Chat").
    func reset() {
        messages.removeAll()
        conversationHistory.removeAll()
        viewState = .idle
        appendWelcomeMessage()
        logger.info("StudyViewModel.reset")
    }

    // MARK: - Private

    private func performAsk(trimmed: String, language: String?, imageBase64: String?) async {
        let examType = profile()?.examTarget.rawValue  // "JEE" | "NEET" | "WBCHSE"
        // Snapshot current history (last 10 turns) to send with this request
        let historySnapshot = Array(conversationHistory.suffix(10))
        do {
            let response: AskResponse = try await apiClient.request(
                .ask(question: trimmed, language: language, examType: examType,
                     imageBase64: imageBase64, history: historySnapshot)
            )

            let answerText = buildAnswerText(from: response)
            messages.append(StudyMessage(role: .assistant, text: answerText, response: response))

            // Append this Q&A pair to history for next turn
            conversationHistory.append(ConversationTurn(role: "user", content: trimmed))
            conversationHistory.append(ConversationTurn(role: "assistant",
                                                         content: response.explanation))
            // Cap at 10 turns (5 Q&A pairs)
            if conversationHistory.count > 10 {
                conversationHistory = Array(conversationHistory.suffix(10))
            }

            viewState = .idle
            questionsUsedToday += 1
            // NOTE: do NOT enqueue here — /ask already persisted to quiz_answers on
            // the server. The offline queue is only for questions captured while offline.
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
        case .timedOut:
            // Server took too long — do NOT queue to offline sync (image data not stored)
            messages.append(StudyMessage(
                role: .assistant,
                text: error.userMessage
            ))
            viewState = .idle

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
        var parts: [String] = []

        // Exam badge — e.g. "JEE Mains • MCQ • 4 marks (+4/-1)"
        // Only shown for real exam question types; internal labels (ACADEMIC TOPIC,
        // META QUERY, PRACTICE REQUEST) are suppressed.
        if let qt = response.questionType,
           let displayQt = examQuestionTypeLabel(qt),
           let m = response.marks {
            var badge = ""
            if let examTarget = profile()?.examTarget {
                badge += examTarget.displayName + " • "
            }
            badge += displayQt + " • \(m) mark" + (m == 1 ? "" : "s")
            if let scheme = response.markingScheme, !scheme.isEmpty {
                badge += " (\(scheme))"
            }
            parts.append("🎯 \(badge)")
        }

        // Answer callout — shown before explanation so it's immediately visible.
        // Suppress internal classification labels that the LLM (especially the 8B
        // fallback) sometimes puts in the answer field instead of leaving it empty.
        let answerUpper = response.answer.uppercased()
        let isClassificationLabel = answerUpper.contains("ACADEMIC TOPIC") ||
                                    answerUpper.contains("META QUERY") ||
                                    answerUpper.contains("PRACTICE REQUEST") ||
                                    answerUpper.contains("MCQ PROBLEM")
        if !response.answer.isEmpty && !isClassificationLabel {
            parts.append("✅ Answer: \(response.answer)")
        }

        parts.append(response.explanation)

        if !response.workedExample.isEmpty {
            parts.append("\n\n📘 Example:\n\(response.workedExample)")
        }

        if !response.practiceProblems.isEmpty {
            let problems = response.practiceProblems.enumerated().map { i, p in
                var line = "Q\(i + 1): \(p.question)\nA: \(p.answer)"
                if let qt = p.questionType,
                   let displayQt = examQuestionTypeLabel(qt),
                   let m = p.marks {
                    line = "[\(displayQt), \(m) marks] " + line
                }
                return line
            }.joined(separator: "\n\n")
            parts.append("\n\n✏️ Practice:\n\(problems)")
        }

        return parts.joined(separator: "\n")
    }

    /// Maps backend question_type strings to user-facing labels.
    /// Returns nil for internal classification labels that should not be shown.
    private func examQuestionTypeLabel(_ raw: String) -> String? {
        switch raw.uppercased().trimmingCharacters(in: .whitespaces) {
        case "MCQ":                          return "MCQ"
        case "INTEGER":                      return "Integer"
        case "SUBJECTIVE", "SHORT ANSWER":   return "Subjective"
        case "ASSERTION-REASON":             return "Assertion-Reason"
        case "MATRIX MATCH":                 return "Matrix Match"
        default:
            // Suppress internal backend classification labels
            let upper = raw.uppercased()
            if upper.contains("TOPIC") || upper.contains("QUERY") ||
               upper.contains("REQUEST") || upper.contains("PRACTICE") {
                return nil
            }
            return raw   // pass through other values (future types)
        }
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
            greeting = "Hello! I'm your AI tutor. Ask me any question about JEE, NEET, or your board exams. 🎓"
        }
        messages.append(StudyMessage(role: .assistant, text: greeting))
    }

    // MARK: - Previous session restore

    /// Fetch the last session's conversation turns from Redis via GET /ask/history.
    /// If history exists, rebuilds conversationHistory (for context sending) and
    /// prepends the last 3 Q&A pairs as visible messages above the welcome message.
    ///
    /// The `hasLoadedSessionHistory` static flag ensures this only hits the network
    /// once per app session even if the ViewModel is re-created (e.g. after a silent
    /// token refresh rebuilds the SwiftUI hierarchy).
    private func loadPreviousSession() async {
        guard !Self.hasLoadedSessionHistory else {
            logger.debug("StudyViewModel.loadPreviousSession: already loaded this session — skipping")
            return
        }
        Self.hasLoadedSessionHistory = true

        struct HistoryResponse: Decodable {
            struct Turn: Decodable { let role: String; let content: String }
            let history: [Turn]
        }
        do {
            let resp: HistoryResponse = try await apiClient.request(.chatHistory)
            guard !resp.history.isEmpty else { return }

            // Rebuild in-memory history for future sends
            conversationHistory = resp.history.map {
                ConversationTurn(role: $0.role, content: $0.content)
            }

            // Show last 3 Q&A pairs (6 turns) as chat bubbles above the welcome message
            let displayTurns = resp.history.suffix(6)
            var restored: [StudyMessage] = []
            for turn in displayTurns {
                let role: StudyMessage.Role = turn.role == "user" ? .user : .assistant
                restored.append(StudyMessage(role: role, text: turn.content))
            }

            // Insert restored history before the welcome message
            messages = restored + messages
            logger.info("StudyViewModel.loadPreviousSession: restored \(restored.count) messages")
        } catch {
            // Non-fatal: silently skip if Redis unavailable or not configured
            logger.debug("StudyViewModel.loadPreviousSession: \(error.localizedDescription)")
        }
    }
}
