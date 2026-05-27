//
//  MockTestsView.swift
//  SmartTutor
//
//  Displays available mock test papers for the student's exam target.
//  The ViewModel tries GET /mock-tests from the backend; on failure (incl.
//  404 / network offline) it falls back to the built-in static catalog so
//  the feature is never empty.
//

import Foundation
import os.log
import SwiftUI

// MARK: - Domain Model

struct MockTest: Identifiable, Hashable {
    let id: String
    let title: String
    let examType: String        // JEE | NEET | WBCHSE
    let subjects: String        // e.g. "Physics · Chemistry · Maths"
    let year: Int
    let questionCount: Int
    let durationMinutes: Int
    let difficulty: String      // Easy | Medium | Hard
    let questionsAvailable: Bool // true when DB has questions for this paper
}

// MARK: - ViewModel

@MainActor
@Observable final class MockTestsViewModel {

    enum LoadState {
        case loading
        case loaded([MockTest])
        case empty
        case error(String)
    }

    private(set) var loadState: LoadState = .loading
    private(set) var selectedFilter: String = "All"  // All | JEE | NEET | WBCHSE

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    var filteredTests: [MockTest] {
        guard case .loaded(let tests) = loadState else { return [] }
        if selectedFilter == "All" { return tests }
        return tests.filter { $0.examType == selectedFilter }
    }

    // MARK: Load

    func load(examTarget: String?) async {
        AppLogger.apiStart(AppLogger.mockTests, endpoint: "GET /mock-tests")
        loadState = .loading

        // Pre-select the student's exam filter so the relevant papers show first
        if let exam = examTarget, !exam.isEmpty {
            selectedFilter = exam
        }

        do {
            let tests: [MockTestResponse] = try await apiClient.request(.mockTests)
            let mapped = tests.map { r in
                MockTest(id: r.id, title: r.title, examType: r.examType,
                         subjects: r.subjects, year: r.year,
                         questionCount: r.questionCount,
                         durationMinutes: r.durationMinutes,
                         difficulty: r.difficulty,
                         questionsAvailable: r.questionsAvailable)
            }
            AppLogger.apiSuccess(AppLogger.mockTests, endpoint: "GET /mock-tests",
                                 detail: "count=\(mapped.count)")
            loadState = mapped.isEmpty ? .empty : .loaded(mapped)
        } catch {
            AppLogger.apiFailure(AppLogger.mockTests, endpoint: "GET /mock-tests", error: error)
            // Offline / server unavailable — fall back to built-in catalog so
            // the feature is never blank.
            AppLogger.userAction(AppLogger.mockTests, action: "static-catalog-fallback")
            loadState = .loaded(MockTestsViewModel.staticCatalog)
        }
    }

    // MARK: Built-in catalog (mirrors backend; used when API is unreachable)

    static let staticCatalog: [MockTest] = [
        // JEE Mains 2019 — Jan (questions available)
        MockTest(id: "jee-2019-0109-am", title: "JEE Mains Jan 2019 — 9 Jan Morning",
                 examType: "JEE", subjects: "Physics · Chemistry · Maths",
                 year: 2019, questionCount: 90, durationMinutes: 180, difficulty: "Medium",
                 questionsAvailable: true),
        MockTest(id: "jee-2019-0109-pm", title: "JEE Mains Jan 2019 — 9 Jan Evening",
                 examType: "JEE", subjects: "Physics · Chemistry · Maths",
                 year: 2019, questionCount: 90, durationMinutes: 180, difficulty: "Medium",
                 questionsAvailable: true),
        MockTest(id: "jee-2019-0110-am", title: "JEE Mains Jan 2019 — 10 Jan Morning",
                 examType: "JEE", subjects: "Physics · Chemistry · Maths",
                 year: 2019, questionCount: 90, durationMinutes: 180, difficulty: "Medium",
                 questionsAvailable: true),
        MockTest(id: "jee-2019-0110-pm", title: "JEE Mains Jan 2019 — 10 Jan Evening",
                 examType: "JEE", subjects: "Physics · Chemistry · Maths",
                 year: 2019, questionCount: 90, durationMinutes: 180, difficulty: "Medium",
                 questionsAvailable: true),
        MockTest(id: "jee-2019-0111-am", title: "JEE Mains Jan 2019 — 11 Jan Morning",
                 examType: "JEE", subjects: "Physics · Chemistry · Maths",
                 year: 2019, questionCount: 90, durationMinutes: 180, difficulty: "Medium",
                 questionsAvailable: true),
        MockTest(id: "jee-2019-0111-pm", title: "JEE Mains Jan 2019 — 11 Jan Evening",
                 examType: "JEE", subjects: "Physics · Chemistry · Maths",
                 year: 2019, questionCount: 90, durationMinutes: 180, difficulty: "Medium",
                 questionsAvailable: true),
        MockTest(id: "jee-2019-0112-am", title: "JEE Mains Jan 2019 — 12 Jan Morning",
                 examType: "JEE", subjects: "Physics · Chemistry · Maths",
                 year: 2019, questionCount: 90, durationMinutes: 180, difficulty: "Medium",
                 questionsAvailable: true),
        MockTest(id: "jee-2019-0112-pm", title: "JEE Mains Jan 2019 — 12 Jan Evening",
                 examType: "JEE", subjects: "Physics · Chemistry · Maths",
                 year: 2019, questionCount: 90, durationMinutes: 180, difficulty: "Medium",
                 questionsAvailable: true),
        // JEE Mains 2019 — April (questions available)
        MockTest(id: "jee-2019-0408-am", title: "JEE Mains Apr 2019 — 8 Apr Morning",
                 examType: "JEE", subjects: "Physics · Chemistry · Maths",
                 year: 2019, questionCount: 90, durationMinutes: 180, difficulty: "Medium",
                 questionsAvailable: true),
        MockTest(id: "jee-2019-0408-pm", title: "JEE Mains Apr 2019 — 8 Apr Evening",
                 examType: "JEE", subjects: "Physics · Chemistry · Maths",
                 year: 2019, questionCount: 90, durationMinutes: 180, difficulty: "Medium",
                 questionsAvailable: true),
        MockTest(id: "jee-2019-0409-am", title: "JEE Mains Apr 2019 — 9 Apr Morning",
                 examType: "JEE", subjects: "Physics · Chemistry · Maths",
                 year: 2019, questionCount: 90, durationMinutes: 180, difficulty: "Medium",
                 questionsAvailable: true),
        MockTest(id: "jee-2019-0409-pm", title: "JEE Mains Apr 2019 — 9 Apr Evening",
                 examType: "JEE", subjects: "Physics · Chemistry · Maths",
                 year: 2019, questionCount: 90, durationMinutes: 180, difficulty: "Medium",
                 questionsAvailable: true),
        MockTest(id: "jee-2019-0410-am", title: "JEE Mains Apr 2019 — 10 Apr Morning",
                 examType: "JEE", subjects: "Physics · Chemistry · Maths",
                 year: 2019, questionCount: 90, durationMinutes: 180, difficulty: "Medium",
                 questionsAvailable: true),
        MockTest(id: "jee-2019-0410-pm", title: "JEE Mains Apr 2019 — 10 Apr Evening",
                 examType: "JEE", subjects: "Physics · Chemistry · Maths",
                 year: 2019, questionCount: 90, durationMinutes: 180, difficulty: "Medium",
                 questionsAvailable: true),
        MockTest(id: "jee-2019-0412-am", title: "JEE Mains Apr 2019 — 12 Apr Morning",
                 examType: "JEE", subjects: "Physics · Chemistry · Maths",
                 year: 2019, questionCount: 90, durationMinutes: 180, difficulty: "Medium",
                 questionsAvailable: true),
        MockTest(id: "jee-2019-0412-pm", title: "JEE Mains Apr 2019 — 12 Apr Evening",
                 examType: "JEE", subjects: "Physics · Chemistry · Maths",
                 year: 2019, questionCount: 90, durationMinutes: 180, difficulty: "Medium",
                 questionsAvailable: true),
        // JEE Mains 2024/2023 (no questions yet)
        MockTest(id: "jee-2024-j1-s1", title: "JEE Mains Jan 2024 — Shift 1",
                 examType: "JEE", subjects: "Physics · Chemistry · Maths",
                 year: 2024, questionCount: 90, durationMinutes: 180, difficulty: "Hard",
                 questionsAvailable: false),
        MockTest(id: "jee-2024-j1-s2", title: "JEE Mains Jan 2024 — Shift 2",
                 examType: "JEE", subjects: "Physics · Chemistry · Maths",
                 year: 2024, questionCount: 90, durationMinutes: 180, difficulty: "Hard",
                 questionsAvailable: false),
        MockTest(id: "jee-2023-j1-s1", title: "JEE Mains Jan 2023 — Shift 1",
                 examType: "JEE", subjects: "Physics · Chemistry · Maths",
                 year: 2023, questionCount: 90, durationMinutes: 180, difficulty: "Medium",
                 questionsAvailable: false),
        MockTest(id: "jee-2023-j1-s2", title: "JEE Mains Jan 2023 — Shift 2",
                 examType: "JEE", subjects: "Physics · Chemistry · Maths",
                 year: 2023, questionCount: 90, durationMinutes: 180, difficulty: "Medium",
                 questionsAvailable: false),
        // NEET (questions available)
        MockTest(id: "neet-2025", title: "NEET UG 2025",
                 examType: "NEET", subjects: "Physics · Chemistry · Biology",
                 year: 2025, questionCount: 180, durationMinutes: 200, difficulty: "Hard",
                 questionsAvailable: true),
        MockTest(id: "neet-2023", title: "NEET UG 2023",
                 examType: "NEET", subjects: "Physics · Chemistry · Biology",
                 year: 2023, questionCount: 180, durationMinutes: 200, difficulty: "Medium",
                 questionsAvailable: true),
        MockTest(id: "neet-2022", title: "NEET UG 2022",
                 examType: "NEET", subjects: "Physics · Chemistry · Biology",
                 year: 2022, questionCount: 180, durationMinutes: 200, difficulty: "Medium",
                 questionsAvailable: true),
        MockTest(id: "neet-2021", title: "NEET UG 2021",
                 examType: "NEET", subjects: "Physics · Chemistry · Biology",
                 year: 2021, questionCount: 180, durationMinutes: 200, difficulty: "Easy",
                 questionsAvailable: true),
        MockTest(id: "neet-2020", title: "NEET UG 2020",
                 examType: "NEET", subjects: "Physics · Chemistry · Biology",
                 year: 2020, questionCount: 180, durationMinutes: 200, difficulty: "Easy",
                 questionsAvailable: true),
        MockTest(id: "neet-2019", title: "NEET UG 2019",
                 examType: "NEET", subjects: "Physics · Chemistry · Biology",
                 year: 2019, questionCount: 180, durationMinutes: 200, difficulty: "Medium",
                 questionsAvailable: true),
        MockTest(id: "neet-2018", title: "NEET UG 2018",
                 examType: "NEET", subjects: "Physics · Chemistry · Biology",
                 year: 2018, questionCount: 180, durationMinutes: 200, difficulty: "Medium",
                 questionsAvailable: true),
        MockTest(id: "neet-2016", title: "NEET UG 2016",
                 examType: "NEET", subjects: "Physics · Chemistry · Biology",
                 year: 2016, questionCount: 180, durationMinutes: 200, difficulty: "Easy",
                 questionsAvailable: true),
        // WBCHSE
        MockTest(id: "wbchse-phy-2024", title: "WBCHSE Physics 2024",
                 examType: "WBCHSE", subjects: "Physics",
                 year: 2024, questionCount: 50, durationMinutes: 90, difficulty: "Medium",
                 questionsAvailable: false),
        MockTest(id: "wbchse-chem-2024", title: "WBCHSE Chemistry 2024",
                 examType: "WBCHSE", subjects: "Chemistry",
                 year: 2024, questionCount: 50, durationMinutes: 90, difficulty: "Medium",
                 questionsAvailable: false),
        MockTest(id: "wbchse-math-2024", title: "WBCHSE Mathematics 2024",
                 examType: "WBCHSE", subjects: "Mathematics",
                 year: 2024, questionCount: 50, durationMinutes: 90, difficulty: "Medium",
                 questionsAvailable: false),
    ]

    func setFilter(_ filter: String) {
        AppLogger.userAction(AppLogger.mockTests, action: "filter-changed", context: filter)
        selectedFilter = filter
    }
}

// MARK: - Network Response (matches GET /mock-tests)

private struct MockTestResponse: Decodable {
    let id: String
    let title: String
    let examType: String
    let subjects: String
    let year: Int
    let questionCount: Int
    let durationMinutes: Int
    let difficulty: String
    let questionsAvailable: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, difficulty, subjects, year
        case examType           = "exam_type"
        case questionCount      = "question_count"
        case durationMinutes    = "duration_minutes"
        case questionsAvailable = "questions_available"
    }
}

// MARK: - Root View

struct MockTestsView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = MockTestsViewModel()
    @State private var selectedTest: MockTest?
    @State private var fullPaperTest: MockTest?  // drives the full-screen session cover

    private var examTarget: String? { appState.currentProfile?.examTarget.rawValue }

    var body: some View {
        Group {
            switch vm.loadState {
            case .loading:
                loadingView
            case .loaded:
                loadedView
            case .empty:
                emptyView
            case .error(let msg):
                errorView(message: msg)
            }
        }
        .navigationTitle("Mock Tests")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(
            LinearGradient(gradient: Gradient(colors: AppColors.gradientColors), startPoint: .top, endPoint: .bottom),
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                filterMenu
            }
        }
        .sheet(item: $selectedTest) { test in
            MockTestDetailView(test: test) { testToStart in
                selectedTest = nil
                // Small delay so the sheet dismiss animation completes before the cover appears
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    fullPaperTest = testToStart
                }
            }
        }
        .fullScreenCover(item: $fullPaperTest) { test in
            MockTestSessionView(test: test)
        }
        .task {
            AppLogger.navigated(to: "MockTestsView", from: "Dashboard")
            await vm.load(examTarget: examTarget)
        }
    }

    // MARK: Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Loading mock tests…")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Loaded

    private var loadedView: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                // Segmented filter chip row
                filterChips
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                if vm.filteredTests.isEmpty {
                    Text("No tests for \(vm.selectedFilter). Try 'All'.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                } else {
                    ForEach(vm.filteredTests) { test in
                        MockTestCard(test: test) {
                            AppLogger.userAction(AppLogger.mockTests,
                                                 action: "test-tapped",
                                                 context: test.id)
                            selectedTest = test
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: Empty

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("No Mock Tests Yet")
                .font(.system(size: 18, weight: .semibold))
            Text("Mock tests for JEE, NEET, and WBCHSE will appear here once available.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Refresh") {
                Task { await vm.load(examTarget: examTarget) }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Could not load tests")
                .font(.system(size: 18, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                Task { await vm.load(examTarget: examTarget) }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Filter Chips

    private let filters = ["All", "JEE", "NEET", "WBCHSE"]

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(filters, id: \.self) { f in
                Button(f) { vm.setFilter(f) }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(vm.selectedFilter == f ? AppColors.accent : AppColors.cardBackground)
                    .foregroundStyle(AppColors.textPrimary)
                    .clipShape(Capsule())
            }
            Spacer()
        }
    }

    // MARK: Filter Menu (toolbar)

    private var filterMenu: some View {
        Menu {
            ForEach(filters, id: \.self) { f in
                Button(f) { vm.setFilter(f) }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
    }
}

// MARK: - Test Card

private struct MockTestCard: View {
    let test: MockTest
    let onTap: () -> Void

    private var difficultyColor: Color {
        switch test.difficulty {
        case "Easy":   return .green
        case "Medium": return .orange
        default:       return .red
        }
    }

    private var examColor: Color {
        switch test.examType {
        case "JEE":    return .indigo
        case "NEET":   return .teal
        default:       return .purple
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                // Exam badge
                VStack {
                    Text(test.examType)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(examColor)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text(String(test.year))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(test.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.leading)

                    Text(test.subjects)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)

                    HStack(spacing: 10) {
                        Label("\(test.questionCount) Qs", systemImage: "list.bullet")
                        Label("\(test.durationMinutes) min", systemImage: "clock")
                        Text(test.difficulty)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(difficultyColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(difficultyColor.opacity(0.12))
                            .clipShape(Capsule())
                        if test.questionsAvailable {
                            Label("Full Paper", systemImage: "doc.text.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppColors.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColors.cardBackgroundSecondary)
                                .clipShape(Capsule())
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(16)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail Sheet

struct MockTestDetailView: View {
    let test: MockTest
    /// Called when the user taps "Start Full Paper Mode". The sheet should dismiss
    /// and then the caller presents MockTestSessionView as a fullScreenCover.
    var onStartFullPaper: ((MockTest) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedMainTab") private var selectedMainTab = 0
    @AppStorage("pendingStudyTopic") private var pendingStudyTopic = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 10) {
                    Text(test.title)
                        .font(.system(size: 20, weight: .bold))
                        .multilineTextAlignment(.center)

                    HStack(spacing: 12) {
                        infoPill(label: "\(test.questionCount) Qs",    icon: "list.bullet",  color: .blue)
                        infoPill(label: "\(test.durationMinutes) min", icon: "clock",        color: .green)
                        infoPill(label: test.difficulty,               icon: "flame",        color: .orange)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)

                Divider()

                // Subjects
                VStack(alignment: .leading, spacing: 8) {
                    Label("Subjects covered", systemImage: "books.vertical")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(test.subjects)
                        .font(.system(size: 15))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)

                Divider()

                // Marking scheme info
                VStack(alignment: .leading, spacing: 8) {
                    Label("Exam Context", systemImage: "info.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(examContextText)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)

                Spacer()

                // CTA
                VStack(spacing: 12) {
                    // Full Paper Mode — always shown; disabled with badge when not yet available
                    if test.questionsAvailable {
                        Button {
                            AppLogger.userAction(AppLogger.mockTests,
                                                 action: "start-full-paper",
                                                 context: test.id)
                            dismiss()
                            onStartFullPaper?(test)
                        } label: {
                            Label("Start Full Paper Mode", systemImage: "doc.text.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    LinearGradient(colors: [.indigo, .purple],
                                                   startPoint: .leading, endPoint: .trailing)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    } else {
                        VStack(spacing: 6) {
                            Label("Full Paper Mode", systemImage: "doc.text.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white.opacity(0.5))
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color(UIColor.systemGray3))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            Text("Questions for this paper are being processed. Check back soon.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }

                    Button {
                        AppLogger.userAction(AppLogger.mockTests,
                                             action: "start-practice",
                                             context: test.id)
                        pendingStudyTopic = "Practice \(test.examType) mock test questions from \(test.title)"
                        dismiss()
                        Task {
                            try? await Task.sleep(for: .milliseconds(350))
                            selectedMainTab = 1
                        }
                    } label: {
                        Label("Practise with AI Tutor", systemImage: "brain.head.profile")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(test.questionsAvailable ? .indigo : .white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(test.questionsAvailable
                                        ? Color(UIColor.secondarySystemBackground)
                                        : Color.indigo)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(test.questionsAvailable ? Color.indigo.opacity(0.4) : Color.clear, lineWidth: 1.5)
                            )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var examContextText: String {
        switch test.examType {
        case "JEE":
            return "MCQ +4/-1 · Integer type +4/0. 3 hours. 90 questions across Physics, Chemistry, and Mathematics."
        case "NEET":
            return "MCQ +4/-1. 200 minutes. 180 questions across Physics, Chemistry, and Biology."
        default:
            return "Short answer and long answer questions. Follow WBCHSE board exam pattern."
        }
    }

    private func infoPill(label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11))
            Text(label).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}
