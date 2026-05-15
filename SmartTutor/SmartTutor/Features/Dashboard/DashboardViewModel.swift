//
//  DashboardViewModel.swift
//  SmartTutor
//
//  Sprint 6 — Loads today's study plan from GET /plan/:studentId.
//  Sprint 9 — Offline cache + auto-refresh on reconnect.
//

import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.smarttutor.app", category: "DashboardViewModel")

@MainActor
final class DashboardViewModel: ObservableObject {

    @Published private(set) var studyPlan: StudyPlanResponse? = nil
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isShowingCachedPlan: Bool = false

    private let apiClient: APIClient
    private let syncManager: OfflineSyncManager
    private var cancellables = Set<AnyCancellable>()
    private var currentStudentId: String = ""

    init(apiClient: APIClient = .shared, syncManager: OfflineSyncManager = .shared) {
        self.apiClient   = apiClient
        self.syncManager = syncManager
        observeReachability()
    }

    // MARK: - Load

    func loadPlan(studentId: String) async {
        guard !isLoading else { return }
        currentStudentId = studentId
        isLoading = true
        defer { isLoading = false }

        do {
            let plan: StudyPlanResponse = try await apiClient.request(.plan(studentId: studentId))
            studyPlan = plan
            isShowingCachedPlan = false
            cachePlan(plan, for: studentId)
            logger.info("DashboardViewModel.loadPlan: ok  topics=\(plan.topics.count)")
        } catch let error as APIError {
            switch error {
            case .serverError(let code, _) where code == 404:
                studyPlan = nil
                isShowingCachedPlan = false
                logger.info("DashboardViewModel.loadPlan: no plan yet for today")
            case .noNetwork:
                loadCachedPlan(for: studentId)
            default:
                loadCachedPlan(for: studentId)
                logger.error("DashboardViewModel.loadPlan: failed  \(error.localizedDescription ?? "")")
            }
        } catch {
            loadCachedPlan(for: studentId)
            logger.error("DashboardViewModel.loadPlan: unexpected  \(error.localizedDescription)")
        }
    }

    // MARK: - Reconnect auto-refresh

    private func observeReachability() {
        syncManager.$isNetworkReachable
            .dropFirst()                              // skip initial value
            .filter { $0 }                            // only rising edges (offline → online)
            .sink { [weak self] _ in
                guard let self, !self.currentStudentId.isEmpty else { return }
                logger.info("DashboardViewModel: network restored — refreshing plan")
                Task {
                    // Wait for the network stack to fully establish before hitting the API.
                    try? await Task.sleep(for: .seconds(2))
                    await self.loadPlan(studentId: self.currentStudentId)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - UserDefaults cache

    private func cacheKey(for studentId: String) -> String {
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        return "cached_plan_\(studentId)_\(today)"
    }

    private func cachePlan(_ plan: StudyPlanResponse, for studentId: String) {
        guard let data = try? JSONEncoder().encode(plan) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey(for: studentId))
    }

    private func loadCachedPlan(for studentId: String) {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(for: studentId)),
              let plan = try? JSONDecoder().decode(StudyPlanResponse.self, from: data) else {
            logger.info("DashboardViewModel: no cached plan for today")
            return
        }
        studyPlan = plan
        isShowingCachedPlan = true
        logger.info("DashboardViewModel: showing cached plan  topics=\(plan.topics.count)")
    }
}
