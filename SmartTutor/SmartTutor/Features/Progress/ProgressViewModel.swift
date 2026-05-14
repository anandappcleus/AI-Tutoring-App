//
//  ProgressViewModel.swift
//  SmartTutor
//
//  Sprint 6 — Loads weekly progress from GET /progress/:studentId.
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

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func load(studentId: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let data: ProgressResponse = try await apiClient.request(.progress(studentId: studentId))
            progressData = data
            logger.info("ProgressViewModel.load: ok  topics=\(data.topics.count)  weak=\(data.weakTopics.count)")
        } catch let error as APIError {
            errorMessage = error.userMessage
            logger.error("ProgressViewModel.load: failed  \(error.localizedDescription)")
        } catch {
            errorMessage = "Failed to load progress."
            logger.error("ProgressViewModel.load: unexpected  \(error.localizedDescription)")
        }
    }
}
