//
//  DashboardViewModel.swift
//  SmartTutor
//
//  Sprint 6 — Loads today's study plan from GET /plan/:studentId.
//  Sprint 9 — Offline cache + auto-refresh on reconnect.
//

import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.smarttutor.app", category: "DashboardViewModel")

@Observable @MainActor
final class DashboardViewModel {

    private(set) var studyPlan: StudyPlanResponse? = nil
    private(set) var isLoading: Bool = false
    private(set) var isShowingCachedPlan: Bool = false

    private let apiClient: APIClient
    private let syncManager: OfflineSyncManager
    private var currentStudentId: String = ""
    /// Timestamp of the last successful network fetch — prevents re-fetching when
    /// DashboardView re-appears (sheet dismiss, tab switch, app foreground) within
    /// a short window.
    private var lastLoadedAt: Date? = nil
    private static let refreshInterval: TimeInterval = 300  // 5 minutes

    init(apiClient: APIClient = .shared, syncManager: OfflineSyncManager = .shared) {
        self.apiClient   = apiClient
        self.syncManager = syncManager
        observeReachability()
    }

    // MARK: - Load

    /// Force a fresh network fetch, bypassing the 5-minute freshness guard.
    /// Called by pull-to-refresh.
    func forceRefresh(studentId: String) async {
        lastLoadedAt = nil
        await loadPlan(studentId: studentId)
    }

    func loadPlan(studentId: String) async {
        guard !isLoading else { return }
        // Skip network fetch if data is already loaded and fresh (within 5 min).
        // The view re-appears on every sheet dismiss / tab switch / foreground;
        // we don't want a new /plan request on each of those.
        if studyPlan != nil,
           let last = lastLoadedAt,
           Date().timeIntervalSince(last) < Self.refreshInterval {
            logger.debug("DashboardViewModel.loadPlan: data fresh — skipping fetch")
            return
        }
        currentStudentId = studentId
        isLoading = true
        defer { isLoading = false }

        do {
            let plan: StudyPlanResponse = try await apiClient.request(.plan(studentId: studentId))
            studyPlan = plan
            isShowingCachedPlan = false
            lastLoadedAt = Date()
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
        } catch is CancellationError {
            // Task was cancelled (e.g. view disappeared mid-fetch) — not an error.
            logger.debug("DashboardViewModel.loadPlan: cancelled")
        } catch {
            loadCachedPlan(for: studentId)
            logger.error("DashboardViewModel.loadPlan: unexpected  \(error.localizedDescription)")
        }
    }

    // MARK: - Reconnect auto-refresh

    private func observeReachability() {
        Task { [weak self] in
            guard let self else { return }
            var previous = syncManager.isNetworkReachable
            // Guard: only trigger a reconnect-refresh after the network was *actually*
            // seen as offline during this session. The initial false→true transition at
            // app startup is not a reconnect; DashboardView.task already handles the
            // first fetch, so we must not fire a duplicate request on launch.
            var hasEverBeenOffline = false
            while !Task.isCancelled {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    withObservationTracking {
                        _ = self.syncManager.isNetworkReachable
                    } onChange: {
                        cont.resume()
                    }
                }
                let current = syncManager.isNetworkReachable
                if !current { hasEverBeenOffline = true }
                if current && !previous && hasEverBeenOffline && !currentStudentId.isEmpty {
                    logger.info("DashboardViewModel: network restored — refreshing plan")
                    Task { [weak self] in
                        try? await Task.sleep(for: .seconds(2))
                        guard let self else { return }
                        await self.loadPlan(studentId: self.currentStudentId)
                    }
                }
                previous = current
            }
        }
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

#if DEBUG
    // MARK: - Dev: trigger nightly crew

    /// Whether a manual crew trigger request is in flight.
    private(set) var isGeneratingPlan: Bool = false

    /// POST /admin/run-nightly-crew with the dev admin secret.
    /// Only compiled into DEBUG builds; stripped from release.
    func triggerNightlyCrew(studentId: String) async {
        guard !isGeneratingPlan else { return }
        isGeneratingPlan = true
        defer { isGeneratingPlan = false }

        let adminURL = AppConfig.apiBaseURL.appendingPathComponent("/admin/run-nightly-crew")
        var req = URLRequest(url: adminURL)
        req.httpMethod = "POST"
        // Dev-only secret — only present in DEBUG builds, stripped from release.
        req.setValue("smarttutor-admin-2026", forHTTPHeaderField: "X-Admin-Secret")

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 202 {
                logger.info("DashboardViewModel.triggerNightlyCrew: accepted — crew running in background")
            } else {
                logger.warning("DashboardViewModel.triggerNightlyCrew: unexpected response")
            }
        } catch {
            logger.error("DashboardViewModel.triggerNightlyCrew: \(error.localizedDescription)")
        }
    }
#endif
}
