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
                         difficulty: r.difficulty)
            }
            AppLogger.apiSuccess(AppLogger.mockTests, endpoint: "GET /mock-tests",
                                 detail: "count=\(mapped.count)")
            loadState = mapped.isEmpty ? .empty : .loaded(mapped)
        } catch {
            AppLogger.apiFailure(AppLogger.mockTests, endpoint: "GET /mock-tests", error: error)
            loadState = .error(error.localizedDescription)
        }
    }

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

    enum CodingKeys: String, CodingKey {
        case id, title, difficulty, subjects, year
        case examType        = "exam_type"
        case questionCount   = "question_count"
        case durationMinutes = "duration_minutes"
    }
}

// MARK: - Root View

struct MockTestsView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = MockTestsViewModel()
    @State private var selectedTest: MockTest?

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
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(
            LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing),
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
            MockTestDetailView(test: test)
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
                    .background(vm.selectedFilter == f ? Color.indigo : Color(UIColor.systemGray5))
                    .foregroundStyle(vm.selectedFilter == f ? .white : .primary)
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
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(test.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Text(test.subjects)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

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
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail Sheet

struct MockTestDetailView: View {
    let test: MockTest
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
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.indigo)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    Text("Full paper mode coming soon")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
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
