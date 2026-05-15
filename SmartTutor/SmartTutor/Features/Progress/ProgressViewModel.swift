//
//  ProgressViewModel.swift
//  SmartTutor
//
//  Sprint 6 — Loads weekly progress from GET /progress/:studentId.
//  Sprint 9 — Offline cache + auto-refresh on reconnect.
//

import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.smarttutor.app", category: "ProgressViewModel")

@MainActor
final class ProgressViewModel: ObservableObject {

    @Published private(set) var progressData: ProgressResponse? = nil
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String? = nil
    @Published private(set) var isShowingCachedData: Bool = false

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

    func load(studentId: String) async {
        guard !isLoading else { return }
        currentStudentId = studentId
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let data: ProgressResponse = try await apiClient.request(.progress(studentId: studentId))
            progressData = data
            isShowingCachedData = false
            cacheProgress(data, for: studentId)
            logger.info("ProgressViewModel.load: ok  topics=\(data.topics.count)  weak=\(data.weakTopics.count)")
        } catch {
            // Fall back to cache; surface an error only if cache is also empty.
            if loadCachedProgress(for: studentId) {
                logger.info("ProgressViewModel.load: offline — showing cached progress")
            } else {
                errorMessage = (error as? APIError)?.userMessage ?? "Failed to load progress."
                logger.error("ProgressViewModel.load: failed  \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Reconnect auto-refresh

    private func observeReachability() {
        syncManager.$isNetworkReachable
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in
                guard let self, !self.currentStudentId.isEmpty else { return }
                logger.info("ProgressViewModel: network restored — refreshing progress")
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    await self.load(studentId: self.currentStudentId)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - UserDefaults cache

    private func cacheKey(for studentId: String) -> String { "cached_progress_\(studentId)" }

    private func cacheProgress(_ data: ProgressResponse, for studentId: String) {
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        UserDefaults.standard.set(encoded, forKey: cacheKey(for: studentId))
    }

    /// Returns true if cached data was loaded successfully.
    @discardableResult
    private func loadCachedProgress(for studentId: String) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(for: studentId)),
              let cached = try? JSONDecoder().decode(ProgressResponse.self, from: data) else {
            return false
        }
        progressData = cached
        isShowingCachedData = true
        return true
    }
}
