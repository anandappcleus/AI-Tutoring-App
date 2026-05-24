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

private let logger = AppLogger.parent

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

    // MARK: - Exam readiness (derived from progress data + profile)

    /// Student's exam target, set at load time. Drives the readiness card title + score range.
    private(set) var examTarget: String = "JEE"
    /// Student's first name, used in the readiness narrative.
    private(set) var studentName: String = "Student"

    /// Max possible score for the student's exam.
    private var maxScore: Int {
        switch examTarget {
        case "NEET":   return 720
        case "WBCHSE": return 500
        default:       return 300   // JEE Mains & Advanced
        }
    }

    var examReadinessTitle: String { "\(examTarget) Exam Readiness Prediction" }

    /// Progress bar fill (0.0–1.0) based on overall accuracy.
    var predictedScoreProgress: Double {
        guard let data = progressData, data.totalQuestions > 0 else { return 0 }
        return min(data.overallAccuracyPct / 100.0, 1.0)
    }

    /// "low–high / max" score range derived from accuracy.
    var predictedScoreText: String {
        guard let data = progressData, data.totalQuestions > 0 else { return "—" }
        let mid  = Int((data.overallAccuracyPct / 100.0) * Double(maxScore))
        let low  = max(0, mid - 10)
        let high = min(maxScore, mid + 10)
        return "\(low)–\(high) / \(maxScore)"
    }

    /// Dynamic narrative using the student's name, accuracy trend, and weak topic count.
    var readinessSummary: String {
        guard let data = progressData, data.totalQuestions > 0 else {
            return "Complete more practice questions to generate a readiness prediction."
        }
        let acc = data.overallAccuracyPct
        let trend: String
        if acc >= 75      { trend = "is on track for a good score" }
        else if acc >= 60 { trend = "is making steady progress" }
        else              { trend = "needs focused practice to improve the score" }
        let weakCount = data.weakTopics.count
        let weakNote  = weakCount > 0
            ? " Consistent practice on \(weakCount) weak topic\(weakCount == 1 ? "" : "s") can improve the score by 15–20 marks."
            : " Keep up the consistent practice!"
        return "Based on current performance, \(studentName) \(trend).\(weakNote)"
    }

    /// Subject accuracy tags, e.g. ["Physics: 78%", "Chemistry: 65%"]. Empty when unavailable.
    var subjectTags: [String] {
        progressData?.subjectAccuracy.map { "\($0.subject): \(Int($0.accuracyPct))%" } ?? []
    }

    // MARK: - Dependencies

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    // MARK: - Load

    func load(studentId: String, examTarget: String = "JEE", studentName: String = "Student") async {
        self.examTarget  = examTarget
        self.studentName = studentName
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
