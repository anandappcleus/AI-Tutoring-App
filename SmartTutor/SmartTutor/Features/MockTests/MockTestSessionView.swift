//
//  MockTestSessionView.swift
//  SmartTutor
//
//  Full Paper Mode — timed exam session for JEE / NEET mock papers.
//
//  Flow:
//    MockTestSessionView  →  startSession()  →  loads questions + starts attempt
//    Student answers, navigates questions, timer counts down
//    On submit (or timeout) → MockTestResultView (pushed inside same NavigationStack)
//

import Foundation
import Observation
import os.log
import SwiftUI

private let logger = Logger(subsystem: "com.smarttutor.app", category: "MockTestSession")

// MARK: - Domain Models

struct MockQuestion: Identifiable, Decodable {
    let id: String
    let questionNumber: Int
    let subject: String
    let topic: String?
    let questionText: String
    let options: [String]?      // nil for integer-type
    let questionType: String    // MCQ | integer | multi_correct
    let hasImage: Bool

    enum CodingKeys: String, CodingKey {
        case id, subject, topic, options
        case questionNumber = "question_number"
        case questionText   = "question_text"
        case questionType   = "question_type"
        case hasImage       = "has_image"
    }
}

struct AttemptStartResponse: Decodable {
    let attemptId: String
    let paperId: String
    let startedAt: String
    let durationMinutes: Int

    enum CodingKeys: String, CodingKey {
        case attemptId       = "attempt_id"
        case paperId         = "paper_id"
        case startedAt       = "started_at"
        case durationMinutes = "duration_minutes"
    }
}

struct AttemptResult: Decodable {
    struct SubjectScore: Decodable {
        let score: Int
        let max: Int
        let accuracy: Double
    }
    let attemptId: String
    let score: Int
    let maxScore: Int
    let accuracyPct: Double
    let timeTakenSeconds: Int?
    let subjectBreakdown: [String: SubjectScore]
    let answers: [String: String]
    let correctAnswers: [String: String]

    enum CodingKeys: String, CodingKey {
        case score, answers
        case attemptId        = "attempt_id"
        case maxScore         = "max_score"
        case accuracyPct      = "accuracy_pct"
        case timeTakenSeconds = "time_taken_seconds"
        case subjectBreakdown = "subject_breakdown"
        case correctAnswers   = "correct_answers"
    }
}

// MARK: - ViewModel

@MainActor
@Observable final class MockTestSessionViewModel {

    enum SessionState: Equatable {
        case loading
        case active
        case submitting
        case submitted
        case error(String)
        static func == (lhs: SessionState, rhs: SessionState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.active, .active),
                 (.submitting, .submitting), (.submitted, .submitted): return true
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    // MARK: Published

    private(set) var sessionState: SessionState = .loading
    private(set) var questions: [MockQuestion] = []
    private(set) var currentIndex: Int = 0
    private(set) var answers: [String: String] = [:]   // questionId → answer string
    private(set) var markedForReview: Set<String> = []
    private(set) var timeRemaining: Int = 0             // seconds
    private(set) var result: AttemptResult? = nil

    // MARK: Private

    private var attemptId: String = ""
    private var timerTask: Task<Void, Never>? = nil
    private var lastSavedAnswers: [String: String] = [:]

    let test: MockTest
    private let apiClient: APIClient

    init(test: MockTest, apiClient: APIClient = .shared) {
        self.test = test
        self.apiClient = apiClient
    }

    // MARK: - Session start

    func startSession() async {
        sessionState = .loading
        do {
            // 1. Load questions
            let qs: [MockQuestion] = try await apiClient.request(.mockTestQuestions(paperId: test.id))
            guard !qs.isEmpty else {
                sessionState = .error("No questions found for this paper. Please check back later.")
                return
            }
            questions = qs

            // 2. Start attempt
            let attempt: AttemptStartResponse = try await apiClient.request(.startAttempt(paperId: test.id))
            attemptId = attempt.attemptId
            timeRemaining = attempt.durationMinutes * 60

            logger.info("MockTestSession: started  paper=\(self.test.id)  attempt=\(attempt.attemptId)  questions=\(qs.count)")
            sessionState = .active
            startTimer()
        } catch {
            logger.error("MockTestSession: startSession failed  \(error.localizedDescription)")
            sessionState = .error(error.localizedDescription)
        }
    }

    // MARK: - Navigation

    func goTo(index: Int) {
        guard index >= 0, index < questions.count else { return }
        currentIndex = index
    }

    func goNext() { goTo(index: currentIndex + 1) }
    func goPrevious() { goTo(index: currentIndex - 1) }

    // MARK: - Answers

    func setAnswer(_ answer: String, for questionId: String) {
        answers[questionId] = answer
        // Debounce auto-save: save immediately when answer changes
        Task { await autoSave() }
    }

    func clearAnswer(for questionId: String) {
        answers.removeValue(forKey: questionId)
    }

    func toggleReview(for questionId: String) {
        if markedForReview.contains(questionId) {
            markedForReview.remove(questionId)
        } else {
            markedForReview.insert(questionId)
        }
    }

    // MARK: - Submit

    func submit() async {
        guard sessionState == .active else { return }
        sessionState = .submitting
        timerTask?.cancel()

        // Final save before submit
        await autoSave()

        do {
            let res: AttemptResult = try await apiClient.request(
                .submitAttempt(paperId: test.id, attemptId: attemptId)
            )
            result = res
            sessionState = .submitted
            logger.info("MockTestSession: submitted  score=\(res.score)/\(res.maxScore)")
        } catch {
            logger.error("MockTestSession: submit failed  \(error.localizedDescription)")
            sessionState = .error("Submission failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if Task.isCancelled { return }
                if self.timeRemaining > 0 {
                    self.timeRemaining -= 1
                } else {
                    // Time's up — auto submit
                    await self.submit()
                    return
                }
            }
        }
    }

    func stopTimer() {
        timerTask?.cancel()
    }

    // MARK: - Auto-save (PATCH answers)

    private func autoSave() async {
        guard !attemptId.isEmpty, sessionState == .active else { return }
        guard answers != lastSavedAnswers else { return }
        do {
            let _: SaveAnswersResponse = try await apiClient.request(
                .saveAnswers(paperId: test.id, attemptId: attemptId, answers: answers)
            )
            lastSavedAnswers = answers
        } catch {
            // Non-fatal — answers saved in memory; will retry on next answer change
            logger.debug("MockTestSession: autoSave failed (non-fatal)  \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    var currentQuestion: MockQuestion? { questions[safe: currentIndex] }

    var answeredCount: Int { answers.count }

    func status(for question: MockQuestion) -> QuestionStatus {
        if markedForReview.contains(question.id) { return .markedForReview }
        if answers[question.id] != nil           { return .answered }
        return .unanswered
    }

    // Formatted timer string MM:SS
    var timerString: String {
        let m = timeRemaining / 60
        let s = timeRemaining % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// Minimal Decodable to consume PATCH response
private struct SaveAnswersResponse: Decodable {
    let saved: Bool
}

enum QuestionStatus {
    case unanswered, answered, markedForReview

    var color: Color {
        switch self {
        case .unanswered:      return Color(UIColor.systemGray5)
        case .answered:        return .green
        case .markedForReview: return .orange
        }
    }
}

// Safe subscript
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Session View

struct MockTestSessionView: View {
    let test: MockTest
    @Environment(\.dismiss) private var dismiss
    @State private var vm: MockTestSessionViewModel
    @State private var showPalette = false
    @State private var showSubmitConfirm = false
    @State private var integerInput: String = ""

    init(test: MockTest) {
        self.test = test
        _vm = State(initialValue: MockTestSessionViewModel(test: test))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch vm.sessionState {
                case .loading:
                    loadingView
                case .active, .submitting:
                    activeView
                case .submitted:
                    if let result = vm.result {
                        MockTestResultView(test: test, result: result, questions: vm.questions, onDismiss: { dismiss() })
                    }
                case .error(let msg):
                    errorView(message: msg)
                }
            }
            .navigationBarBackButtonHidden(true)
            .toolbar {
                if vm.sessionState == .active || vm.sessionState == .submitting {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Exit") { dismiss() }
                            .foregroundStyle(.red)
                    }
                    ToolbarItem(placement: .principal) {
                        timerLabel
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showPalette = true
                        } label: {
                            Label("Questions", systemImage: "square.grid.3x3")
                        }
                    }
                }
            }
        }
        .task { await vm.startSession() }
        .sheet(isPresented: $showPalette) {
            QuestionPaletteView(vm: vm)
        }
        .confirmationDialog(
            "Submit Paper?",
            isPresented: $showSubmitConfirm,
            titleVisibility: .visible
        ) {
            Button("Submit", role: .destructive) {
                Task { await vm.submit() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let unanswered = vm.questions.count - vm.answeredCount
            Text(unanswered > 0
                 ? "You have \(unanswered) unanswered question(s). Are you sure you want to submit?"
                 : "Submit all \(vm.answeredCount) answers?")
        }
    }

    // MARK: Loading

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView().scaleEffect(1.5)
            Text("Loading paper…")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Could not load paper")
                .font(.system(size: 18, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Active Test

    private var activeView: some View {
        VStack(spacing: 0) {
            if let question = vm.currentQuestion {
                questionHeader(question)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        questionBody(question)
                        answerSection(question)
                    }
                    .padding(20)
                }
                Divider()
                navigationBar(question)
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    // Question # + subject header
    private func questionHeader(_ q: MockQuestion) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Q\(q.questionNumber) of \(vm.questions.count)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                Text(q.subject.capitalized + (q.topic.map { " · \($0)" } ?? ""))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                vm.toggleReview(for: q.id)
            } label: {
                let marked = vm.markedForReview.contains(q.id)
                Label(marked ? "Marked" : "Mark", systemImage: marked ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(marked ? .orange : .secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(UIColor.systemBackground))
    }

    // Question text — run a lightweight cleanup pass to remove PDF artefacts
    private func questionBody(_ q: MockQuestion) -> some View {
        Text(cleanQuestionText(q.questionText))
            .font(.system(size: 15))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Remove common PDF extraction artefacts from question text.
    /// Not full LaTeX rendering — just cleans the most common noise.
    private func cleanQuestionText(_ raw: String) -> String {
        var s = raw
        // Vedantu / site watermarks embedded in PDFs
        s = s.replacingOccurrences(of: #"www\.\S+\.com\s*\d*"#, with: "", options: .regularExpression)
        // "Q. 1" / "Q.1" numbering artefacts at start of extracted text
        s = s.replacingOccurrences(of: #"^Q\.\s*\d+\s*"#, with: "", options: [.regularExpression, .anchored])
        // Collapse runs of 3+ whitespace/newline into a single space
        s = s.replacingOccurrences(of: #"\s{3,}"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Options (MCQ) or integer input
    @ViewBuilder
    private func answerSection(_ q: MockQuestion) -> some View {
        if q.questionType == "integer" {
            integerAnswerView(q)
        } else if let options = q.options, !options.isEmpty {
            mcqOptionsView(q, options: options)
        } else {
            noOptionsPlaceholder(q)
        }

        // Marking scheme hint
        markingSchemeHint(q)
    }

    private func noOptionsPlaceholder(_ q: MockQuestion) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Options not available for this question.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Mark for review and continue.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Skip") {
                vm.toggleReview(for: q.id)
                vm.goNext()
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.orange)
        }
        .padding(14)
        .background(Color.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }

    private func mcqOptionsView(_ q: MockQuestion, options: [String]) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(options.enumerated()), id: \.offset) { idx, option in
                let letter = ["A", "B", "C", "D"][safe: idx] ?? "\(idx+1)"
                let value = "\(idx + 1)"   // 1-indexed — matches backend correct_answer ("1"/"2"/"3"/"4")
                let isSelected = vm.answers[q.id] == value
                Button {
                    if isSelected {
                        vm.clearAnswer(for: q.id)
                    } else {
                        vm.setAnswer(value, for: q.id)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(letter)
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 28, height: 28)
                            .background(isSelected ? Color.indigo : Color(UIColor.systemGray5))
                            .foregroundStyle(isSelected ? .white : .primary)
                            .clipShape(Circle())
                        Text(option)
                            .font(.system(size: 14))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(isSelected ? Color.indigo.opacity(0.08) : Color(UIColor.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.indigo : Color(UIColor.systemGray4), lineWidth: isSelected ? 1.5 : 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func integerAnswerView(_ q: MockQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter integer answer (0–9999):")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                TextField("Integer answer", text: Binding(
                    get: { vm.answers[q.id] ?? "" },
                    set: { val in
                        let filtered = val.filter { $0.isNumber }
                        if filtered.isEmpty {
                            vm.clearAnswer(for: q.id)
                        } else {
                            vm.setAnswer(filtered, for: q.id)
                        }
                    }
                ))
                .keyboardType(.numberPad)
                .font(.system(size: 18, weight: .semibold))
                .multilineTextAlignment(.center)
                .frame(width: 120, height: 48)
                .background(Color(UIColor.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.indigo, lineWidth: 1.5))

                if vm.answers[q.id] != nil {
                    Button("Clear") { vm.clearAnswer(for: q.id) }
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func markingSchemeHint(_ q: MockQuestion) -> some View {
        let scheme: String
        switch (test.examType, q.questionType) {
        case ("JEE", "MCQ"):     scheme = "+4 correct · −1 wrong"
        case ("JEE", "integer"): scheme = "+4 correct · no negative"
        case ("NEET", _):        scheme = "+4 correct · −1 wrong"
        default:                 scheme = "+4 correct"
        }
        return Text(scheme)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }

    // Prev / Next / Submit bar
    private func navigationBar(_ q: MockQuestion) -> some View {
        HStack(spacing: 12) {
            Button {
                vm.goPrevious()
            } label: {
                Label("Prev", systemImage: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
            }
            .disabled(vm.currentIndex == 0)
            .buttonStyle(.bordered)

            Spacer()

            // Progress dots
            Text("\(vm.answeredCount) / \(vm.questions.count) answered")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()

            if vm.currentIndex == vm.questions.count - 1 {
                Button {
                    showSubmitConfirm = true
                } label: {
                    Label("Submit", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .clipShape(Capsule())
                }
                .disabled(vm.sessionState == .submitting)
            } else {
                Button {
                    vm.goNext()
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(UIColor.systemBackground))
    }

    // Timer pill in navigation bar
    private var timerLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 12))
            Text(vm.timerString)
                .font(.system(size: 15, weight: .bold).monospacedDigit())
        }
        .foregroundStyle(vm.timeRemaining < 300 ? .red : .primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            (vm.timeRemaining < 300 ? Color.red : Color.clear).opacity(0.1)
        )
        .clipShape(Capsule())
    }
}

// MARK: - Question Palette

private struct QuestionPaletteView: View {
    let vm: MockTestSessionViewModel
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // Legend
                HStack(spacing: 16) {
                    legendItem(color: Color(UIColor.systemGray5), label: "Not Attempted")
                    legendItem(color: .green, label: "Answered")
                    legendItem(color: .orange, label: "Review")
                }
                .padding(.horizontal, 20)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(vm.questions.enumerated()), id: \.offset) { idx, q in
                        let status = vm.status(for: q)
                        let isCurrent = vm.currentIndex == idx
                        Button {
                            vm.goTo(index: idx)
                            dismiss()
                        } label: {
                            Text("\(q.questionNumber)")
                                .font(.system(size: 13, weight: isCurrent ? .black : .medium))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(status.color)
                                .foregroundStyle(status == .answered ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isCurrent ? Color.indigo : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle("Question Palette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 16, height: 16)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Result View

struct MockTestResultView: View {
    let test: MockTest
    let result: AttemptResult
    let questions: [MockQuestion]
    let onDismiss: () -> Void

    // Map question id → question for O(1) lookup
    private var questionMap: [String: MockQuestion] {
        Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })
    }

    // Convert stored "1"/"2"/"3"/"4" back to display letter
    private func answerLabel(_ value: String?, options: [String]?) -> String {
        guard let v = value, !v.isEmpty, v != "0" else { return "—" }
        let letters = ["A", "B", "C", "D"]
        if let n = Int(v), n >= 1, n <= (options?.count ?? 4) {
            return letters[safe: n - 1] ?? v
        }
        return v  // integer-type: show raw number
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Score hero
                scoreHero

                // Subject breakdown
                if !result.subjectBreakdown.isEmpty {
                    subjectBreakdownSection
                }

                // Stats row
                statsRow

                // Per-question review
                if !questions.isEmpty {
                    answerReviewSection
                }

                Spacer(minLength: 20)

                Button("Done", action: onDismiss)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.indigo)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
            .padding(.top, 32)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Score hero card

    private var scoreHero: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(scoreColor.opacity(0.2), lineWidth: 12)
                    .frame(width: 130, height: 130)
                Circle()
                    .trim(from: 0, to: CGFloat(result.score) / CGFloat(max(result.maxScore, 1)))
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 130, height: 130)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(result.score)")
                        .font(.system(size: 36, weight: .black))
                    Text("/ \(result.maxScore)")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }

            Text(performanceLabel)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(scoreColor)

            Text(String(format: "%.1f%% accuracy", result.accuracyPct))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 20)
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    // MARK: Subject breakdown

    private var subjectBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subject Breakdown")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 20)

            VStack(spacing: 8) {
                ForEach(result.subjectBreakdown.sorted(by: { $0.key < $1.key }), id: \.key) { subject, scores in
                    subjectRow(subject: subject.capitalized, scores: scores)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func subjectRow(subject: String, scores: AttemptResult.SubjectScore) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(subject)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Text("\(scores.score) / \(scores.max)")
                    .font(.system(size: 14, weight: .semibold))
                Text(String(format: "(%.0f%%)", scores.accuracy))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color(UIColor.systemGray5)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(accuracyColor(scores.accuracy))
                        .frame(width: geo.size.width * CGFloat(max(scores.score, 0)) / CGFloat(max(scores.max, 1)),
                               height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Stats row

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard(value: "\(result.score)", label: "Score", color: scoreColor)
            statCard(value: "\(result.maxScore - result.score)", label: "Lost", color: .secondary)
            if let secs = result.timeTakenSeconds {
                statCard(value: formatTime(secs), label: "Time", color: .blue)
            }
        }
        .padding(.horizontal, 20)
    }

    private func statCard(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    // MARK: Answer Review

    private var answerReviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Answer Review")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 20)

            VStack(spacing: 6) {
                ForEach(questions) { q in
                    let given    = result.answers[q.id] ?? ""
                    let correct  = result.correctAnswers[q.id] ?? ""
                    let hasCorrect = !correct.isEmpty && correct != "0"
                    let attempted  = !given.isEmpty && given != "0"

                    let isCorrect  = attempted && hasCorrect && given == correct
                    let isWrong    = attempted && hasCorrect && given != correct
                    // unattempted or no correct key stored → gray

                    HStack(spacing: 10) {
                        // Status dot
                        Circle()
                            .fill(isCorrect ? Color.green : isWrong ? Color.red : Color(UIColor.systemGray4))
                            .frame(width: 8, height: 8)

                        Text("Q\(q.questionNumber)")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 34, alignment: .leading)

                        Text(q.subject.prefix(4).capitalized)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .leading)

                        Spacer()

                        if isWrong {
                            Text("You: \(answerLabel(given, options: q.options))")
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                            Text("✓ \(answerLabel(correct, options: q.options))")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.green)
                        } else if isCorrect {
                            Text(answerLabel(given, options: q.options))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.green)
                        } else if attempted && !hasCorrect {
                            Text(answerLabel(given, options: q.options))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text("(no key)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Not attempted")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(UIColor.systemGray3))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: Helpers

    private var scoreColor: Color {
        let pct = result.accuracyPct
        if pct >= 60 { return .green }
        if pct >= 35 { return .orange }
        return .red
    }

    private var performanceLabel: String {
        let pct = result.accuracyPct
        if pct >= 80 { return "Excellent 🎯" }
        if pct >= 60 { return "Good Work 👍" }
        if pct >= 35 { return "Keep Practising 📚" }
        return "Needs Improvement 💪"
    }

    private func accuracyColor(_ pct: Double) -> Color {
        if pct >= 60 { return .green }
        if pct >= 35 { return .orange }
        return .red
    }

    private func formatTime(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
