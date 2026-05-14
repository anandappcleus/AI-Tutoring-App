//
//  DashboardViewModel.swift
//  SmartTutor
//
//  Sprint 6 — Loads today's study plan from GET /plan/:studentId.
//

import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.smarttutor.app", category: "DashboardViewModel")

@MainActor
final class DashboardViewModel: ObservableObject {

    @Published private(set) var studyPlan: StudyPlanResponse? = nil
    @Published private(set) var isLoading: Bool = false

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func loadPlan(studentId: String) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let plan: StudyPlanResponse = try await apiClient.request(.plan(studentId: studentId))
            studyPlan = plan
            logger.info("DashboardViewModel.loadPlan: ok  topics=\(plan.topics.count)")
        } catch let error as APIError {
            switch error {
            case .serverError(let code, _) where code == 404:
                // No plan yet — normal before first nightly crew run
                studyPlan = nil
                logger.info("DashboardViewModel.loadPlan: no plan yet for today")
            default:
                logger.error("DashboardViewModel.loadPlan: failed  \(error.localizedDescription)")
            }
        } catch {
            logger.error("DashboardViewModel.loadPlan: unexpected  \(error.localizedDescription)")
        }
    }
}
