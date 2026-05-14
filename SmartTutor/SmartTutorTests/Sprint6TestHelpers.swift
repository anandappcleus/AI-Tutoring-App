//
//  Sprint6TestHelpers.swift
//  SmartTutorTests
//
//  Sprint 6 — Shared test utilities for Sprint 6 unit tests.
//
//  Provides:
//    • StubAPIClient   — generic APIClient mock driven by a closure
//    • MockURLProtocol — URLProtocol subclass for intercepting URLSession calls
//    • makeProgressResponse() / makeStudentResponse() — convenience fixture builders
//

import Foundation
import XCTest
@testable import SmartTutor

// MARK: - StubAPIClient
//
// A generic APIClient subclass whose response is controlled via a closure.
// Supports any Decodable return type, unlike the Sprint 5 MockAPIClient
// which is hard-coded to AskResponse.

final class StubAPIClient: APIClient {

    /// Set this before calling any method under test.
    var responseHandler: ((Endpoint) async throws -> Any) = { _ in throw APIError.noNetwork }
    var callCount = 0

    override func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        callCount += 1
        let raw = try await responseHandler(endpoint)
        guard let cast = raw as? T else {
            throw APIError.decodingError("StubAPIClient: expected \(T.self), got \(type(of: raw))")
        }
        return cast
    }
}

// MARK: - MockURLProtocol
//
// Register with a URLSession via:
//   let config = URLSessionConfiguration.ephemeral
//   config.protocolClasses = [MockURLProtocol.self]
//   let session = URLSession(configuration: config)
//
// Set MockURLProtocol.requestHandler before each test.

final class MockURLProtocol: URLProtocol {

    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - URLSession factory

func makeMockURLSession(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
    MockURLProtocol.requestHandler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

// MARK: - Fixture builders

func makeProgressResponse(
    studentId: String = "test-student",
    totalQuestions: Int = 12,
    correctQuestions: Int = 9,
    overallAccuracyPct: Double = 75.0,
    topics: [ProgressResponse.TopicProgress] = [],
    weakTopics: [String] = [],
    weekStart: String = "2026-05-08",
    weekEnd: String = "2026-05-14"
) -> ProgressResponse {
    ProgressResponse(
        studentId: studentId,
        weekStart: weekStart,
        weekEnd: weekEnd,
        totalQuestions: totalQuestions,
        correctQuestions: correctQuestions,
        overallAccuracyPct: overallAccuracyPct,
        topics: topics,
        weakTopics: weakTopics
    )
}

func makeStudentResponse(
    id: String = "test-student",
    name: String = "Test User",
    language: String = "en",
    exam: String = "JEE"
) -> StudentResponse {
    StudentResponse(
        id: id, name: name, email: "\(id)@test.com",
        preferredLanguage: language, examTarget: exam,
        isPremium: false, createdAt: "2026-05-14T00:00:00Z"
    )
}

/// Creates a minimal valid WAV file in the temp directory for STT tests.
func makeTempAudioFile() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("test_audio_\(UUID().uuidString).wav")
    // 44-byte minimal WAV header with zero audio data
    var wav = Data()
    wav.append(contentsOf: "RIFF".utf8)
    wav.append(contentsOf: [36, 0, 0, 0])   // chunk size
    wav.append(contentsOf: "WAVE".utf8)
    wav.append(contentsOf: "fmt ".utf8)
    wav.append(contentsOf: [16, 0, 0, 0, 1, 0, 1, 0,
                             0x80, 0x3e, 0, 0, 0x7d, 0, 0, 0,
                             2, 0, 16, 0])  // PCM, mono, 16kHz
    wav.append(contentsOf: "data".utf8)
    wav.append(contentsOf: [0, 0, 0, 0])    // 0 bytes of audio
    try wav.write(to: url)
    return url
}
