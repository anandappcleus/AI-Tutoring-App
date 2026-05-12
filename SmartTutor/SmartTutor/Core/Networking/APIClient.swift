//
//  APIClient.swift
//  SmartTutor
//
//  Sprint 1 scaffold — full implementation in Sprint 5.
//
//  Copilot prompt (Sprint 5, Task 1):
//  // URLSession-based API client
//  // Generic func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T
//  // JWT token storage in Keychain, automatic refresh on 401
//  // All requests include Authorization: Bearer {token} header
//  // Base URL from AppConfig.apiBaseURL
//

import Foundation

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(statusCode: Int, body: String)
    case decodingError(Error)
    case noNetwork

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL."
        case .unauthorized:
            return "Session expired. Please log in again."
        case .serverError(let code, let body):
            return "Server error \(code): \(body)"
        case .decodingError(let error):
            return "Response parsing failed: \(error.localizedDescription)"
        case .noNetwork:
            return "No internet connection."
        }
    }
}

// MARK: - API Client

// TODO Sprint 5: Implement full APIClient
//   - Generic request<T: Decodable>(_ endpoint: Endpoint) async throws -> T
//   - Read access token from Keychain, inject as "Authorization: Bearer {token}"
//   - On 401: call POST /auth/token with refresh token, retry original request once
//   - On URLError.notConnectedToInternet: throw APIError.noNetwork

@MainActor
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // Sprint 5: full implementation replaces this stub
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        // TODO Sprint 5
        throw APIError.invalidURL
    }
}
