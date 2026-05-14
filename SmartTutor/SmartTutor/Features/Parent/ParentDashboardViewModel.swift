//
//  ParentDashboardViewModel.swift
//  SmartTutor
//
//  Sprint 6 — Loads weekly progress for the Parent Dashboard via GET /progress/:studentId.
//
//  Maps ProgressResponse fields to parent-friendly display values.
//  Fields not tracked by the API (streak, daily breakdown, predicted score)
//  are flagged as unavailable so the View can show placeholder UI.
//

import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.smarttutor.app", category: "ParentDashboardViewModel")

@MainActor
final class ParentDashboardViewModel: ObservableObject {

    // MARK: - Published outputs

    @Published private(set) var progressData: ProgressResponse? = nil
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String? = nil

    // MARK: - Convenience computed properties for the View

    /// Total questions attempted this week.
    var questionsAttempted: Int { progressData?.totalQuestions ?? 0 }

    /// Overall accuracy percentage (0–100).
    var avgAccuracy: Int { progressData.map { Int($0.overallAccuracyPct) } ?? 0 }

    /// Topics the student is struggling with (accuracy < 70%).
    var weakTopics: [String] { progressData?.weakTopics ?? [] }

    /// All topics attempted this week with per-topic accuracy.
    var topicBreakdown: [ProgressResponse.TopicProgress] { progressData?.topics ?? [] }

    /// Week range string, e.g. "12 May – 18 May 2026".
    var weekRange: String? {
        guard let d = progressData else { return nil }
        return "\(d.weekStart) – \(d.weekEnd)"
    }

    // MARK: - Dependencies

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    // MARK: - Load

    func load(studentId: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let data: ProgressResponse = try await apiClient.request(.progress(studentId: studentId))
            progressData = data
            logger.info("ParentDashboardViewModel.load: ok  topics=\(data.topics.count)  weak=\(data.weakTopics.count)")
        } catch let error as APIError {
            errorMessage = error.userMessage
            logger.error("ParentDashboardViewModel.load: failed  \(error.localizedDescription)")
        } catch {
            errorMessage = "Failed to load progress."
            logger.error("ParentDashboardViewModel.load: unexpected  \(error.localizedDescription)")
        }
    }
}
