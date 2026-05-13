//
//  APIClient.swift
//  SmartTutor
//
//  Sprint 5 — full implementation.
//
//  Design:
//    • Generic request<T: Decodable>(_ endpoint: Endpoint) async throws -> T
//    • Access token stored in Keychain via TokenStore; injected as Bearer header
//    • On HTTP 401: attempts a silent token refresh via POST /auth/refresh once,
//      then retries the original request; if refresh fails, throws .unauthorized
//    • Network unavailable: throws .noNetwork
//    • All errors logged with structured context for easy debugging
//

import Foundation
import os.log

// MARK: - Logging

private let logger = Logger(subsystem: "com.smarttutor.app", category: "APIClient")

// MARK: - API Errors

enum APIError: LocalizedError, Equatable {
    case invalidURL
    case unauthorized                                 // session expired, needs login
    case serverError(statusCode: Int, body: String)  // 4xx/5xx with body
    case decodingError(String)                        // JSON decode failure
    case noNetwork                                    // URLError.notConnectedToInternet

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL."
        case .unauthorized:
            return "Session expired. Please log in again."
        case .serverError(let code, let body):
            return "Server error \(code): \(body)"
        case .decodingError(let detail):
            return "Response parsing failed: \(detail)"
        case .noNetwork:
            return "No internet connection."
        }
    }

    // User-friendly short message for UI display
    var userMessage: String {
        switch self {
        case .noNetwork:       return "Check your internet connection and try again."
        case .unauthorized:    return "Please log in again to continue."
        case .serverError:     return "Something went wrong on our end. Please try again."
        case .decodingError:   return "Unexpected response from server."
        case .invalidURL:      return "Invalid request. Please contact support."
        }
    }

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL):       return true
        case (.unauthorized, .unauthorized):   return true
        case (.noNetwork, .noNetwork):         return true
        case (.serverError(let a, _), .serverError(let b, _)): return a == b
        default:                               return false
        }
    }
}

// MARK: - Token Store (Keychain-backed)

/// Thread-safe Keychain wrapper for access + refresh tokens.
/// Uses the Security framework directly — no third-party deps.
enum TokenStore {
    private static let service = "com.smarttutor.app"
    private static let accessKey  = "access_token"
    private static let refreshKey = "refresh_token"

    static func saveAccessToken(_ token: String)  { save(token, for: accessKey) }
    static func saveRefreshToken(_ token: String) { save(token, for: refreshKey) }
    static func accessToken()  -> String? { load(for: accessKey) }
    static func refreshToken() -> String? { load(for: refreshKey) }

    static func clearAll() {
        delete(for: accessKey)
        delete(for: refreshKey)
        logger.info("TokenStore: cleared all tokens")
    }

    // MARK: Private helpers

    private static func save(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else {
            logger.error("TokenStore.save: UTF-8 encoding failed for key=\(key)")
            return
        }
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]

        var status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        if status != errSecSuccess {
            logger.error("TokenStore.save: failed key=\(key) status=\(status)")
        }
    }

    private static func load(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      key,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                logger.warning("TokenStore.load: unexpected status key=\(key) status=\(status)")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(for key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Auth Response

struct AuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
        case tokenType    = "token_type"
        case expiresIn    = "expires_in"
    }
}

// MARK: - API Client

@MainActor
class APIClient {
    static let shared = APIClient()

    let session: URLSession
    let decoder: JSONDecoder
    let encoder: JSONEncoder

    // Guard flag: prevents infinite refresh loops if the refresh endpoint also 401s
    var isRefreshing = false

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy   = .convertToSnakeCase
    }

    // MARK: - Public API

    /// Perform a typed API request. Automatically attaches Bearer token,
    /// handles silent token refresh on 401, and maps network/decode errors.
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        logger.debug("APIClient.request  \(endpoint.httpMethod) \(endpoint.path)")
        let urlRequest = try buildURLRequest(endpoint)
        return try await execute(urlRequest, endpoint: endpoint, isRetry: false)
    }

    // MARK: - Login (no auth header)

    /// Authenticate with email + password, persist tokens.
    func login(email: String, password: String) async throws -> AuthTokenResponse {
        logger.info("APIClient.login  email=\(email)")

        var req = URLRequest(url: Endpoint.login(email: email, password: password).url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // OAuth2PasswordRequestForm expects form-encoded body
        let body = "username=\(email.urlEncoded)&password=\(password.urlEncoded)&grant_type=password"
        req.httpBody = body.data(using: .utf8)

        let (data, response) = try await performDataTask(req)
        try validateHTTPResponse(response, data: data, context: "login")

        do {
            let tokens = try decoder.decode(AuthTokenResponse.self, from: data)
            TokenStore.saveAccessToken(tokens.accessToken)
            TokenStore.saveRefreshToken(tokens.refreshToken)
            logger.info("APIClient.login  success  expires_in=\(tokens.expiresIn)s")
            return tokens
        } catch {
            logger.error("APIClient.login  decode_error=\(error)")
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - Private helpers

    private func buildURLRequest(_ endpoint: Endpoint) throws -> URLRequest {
        var req = URLRequest(url: endpoint.url)
        req.httpMethod = endpoint.httpMethod
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = endpoint.requestBody {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if let token = TokenStore.accessToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            logger.warning("APIClient.buildURLRequest  no_token  path=\(endpoint.path)")
        }
        return req
    }

    private func execute<T: Decodable>(
        _ request: URLRequest,
        endpoint: Endpoint,
        isRetry: Bool
    ) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await performDataTask(request)
        } catch let urlError as URLError where [.notConnectedToInternet,
                                                .networkConnectionLost,
                                                .cannotConnectToHost,   // -1004 connection refused
                                                .cannotFindHost,        // -1003 DNS failure
                                                .timedOut               // -1001
                                               ].contains(urlError.code) {
            logger.warning("APIClient.execute  no_network  code=\(urlError.code.rawValue)  path=\(endpoint.path)")
            throw APIError.noNetwork
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverError(statusCode: 0, body: "No HTTP response")
        }

        // Silent refresh on 401 — attempt once
        if http.statusCode == 401 && !isRetry && !isRefreshing {
            logger.info("APIClient.execute  401_refresh  path=\(endpoint.path)")
            do {
                try await refreshTokens()
            } catch {
                logger.error("APIClient.execute  refresh_failed  \(error)")
                throw APIError.unauthorized
            }
            // Rebuild request with new token and retry
            let retryRequest = try buildURLRequest(endpoint)
            return try await execute(retryRequest, endpoint: endpoint, isRetry: true)
        }

        try validateHTTPResponse(response, data: data, context: endpoint.path)

        do {
            let result = try decoder.decode(T.self, from: data)
            logger.debug("APIClient.execute  ok  status=\(http.statusCode)  path=\(endpoint.path)")
            return result
        } catch {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
            logger.error("APIClient.execute  decode_error  path=\(endpoint.path)  error=\(error)  preview=\(preview)")
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    private func refreshTokens() async throws {
        guard !isRefreshing else { return }
        guard let refreshToken = TokenStore.refreshToken() else {
            logger.warning("APIClient.refreshTokens  no_refresh_token")
            throw APIError.unauthorized
        }
        isRefreshing = true
        defer { isRefreshing = false }

        logger.info("APIClient.refreshTokens  attempting_refresh")

        var req = URLRequest(url: AppConfig.apiBaseURL.appendingPathComponent("/auth/refresh"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

        let (data, response) = try await performDataTask(req)
        try validateHTTPResponse(response, data: data, context: "token_refresh")

        let tokens = try decoder.decode(AuthTokenResponse.self, from: data)
        TokenStore.saveAccessToken(tokens.accessToken)
        TokenStore.saveRefreshToken(tokens.refreshToken)
        logger.info("APIClient.refreshTokens  success")
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data, context: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(500), encoding: .utf8) ?? "<unreadable>"
            logger.error("APIClient.validateHTTPResponse  status=\(http.statusCode)  context=\(context)  body=\(body)")
            if http.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.serverError(statusCode: http.statusCode, body: body)
        }
    }

    private func performDataTask(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

// MARK: - String URL encoding helper

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
