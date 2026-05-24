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

import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.smarttutor.app", category: "ParentDashboardViewModel")

@MainActor
@Observable final class ParentDashboardViewModel {

    // MARK: - Published outputs

    private(set) var progressData: ProgressResponse? = nil
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String? = nil

    // MARK: - Convenience computed properties for the View

    /// Total questions attempted this week.
    var questionsAttempted: Int { progressData?.totalQuestions ?? 0 }

    /// Overall accuracy percentage (0–100).
    var avgAccuracy: Int { progressData.map { Int($0.overallAccuracyPct) } ?? 0 }

    /// Day streak (consecutive days with ≥1 answer).
    var dayStreak: Int { progressData?.dayStreak ?? 0 }

    /// Study time this week, formatted as "2h 30m" or "45 min".
    var studyTimeFormatted: String {
        guard let data = progressData else { return "—" }
        let min = data.estimatedStudyMinWeek
        guard min > 0 else { return "—" }
        if min < 60 { return "\(min) min" }
        let h = min / 60; let m = min % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// Per-day activity for the Daily Activity Log.
    var dailyActivity: [ProgressResponse.DailyActivity] { progressData?.dailyActivity ?? [] }

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
