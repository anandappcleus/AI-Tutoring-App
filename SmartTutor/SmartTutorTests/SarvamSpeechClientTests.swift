//
//  SarvamSpeechClientTests.swift
//  SmartTutorTests
//
//  Sprint 6 — Unit tests for SarvamSpeechClient.
//
//  Uses MockURLProtocol to intercept URLSession calls.
//  Uses the testAPIKey init parameter to bypass Info.plist lookup.
//
//  Coverage:
//    ✓ transcribe() throws missingAPIKey when no key is configured
//    ✓ transcribe() throws httpError on 4xx response
//    ✓ transcribe() throws emptyTranscript when server returns blank text
//    ✓ transcribe() returns transcript string on success
//    ✓ synthesise() throws missingAPIKey when no key is configured
//    ✓ synthesise() throws httpError on 4xx response
//    ✓ synthesise() returns audio Data on success
//

import XCTest
@testable import SmartTutor

final class SarvamSpeechClientTests: XCTestCase {

    private let fakeKey = "test_api_key_12345"

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeSUT(useKey: Bool = true) -> SarvamSpeechClient {
        let session = makeMockURLSession { _ in
            // Default: 200 OK with empty body — override per test
            let resp = HTTPURLResponse(url: URL(string: "https://api.sarvam.ai")!,
                                       statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        return SarvamSpeechClient(session: session, testAPIKey: useKey ? fakeKey : nil)
    }

    private func httpResponse(status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.sarvam.ai")!,
                        statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    // MARK: - transcribe() — missing API key

    func test_transcribe_throwsMissingAPIKey_whenNoKeyConfigured() async throws {
        let sut = SarvamSpeechClient(session: URLSession.shared, testAPIKey: nil)
        let audioURL = try makeTempAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        do {
            _ = try await sut.transcribe(audioURL: audioURL)
            XCTFail("Expected missingAPIKey error")
        } catch SarvamError.missingAPIKey {
            // expected
        }
    }

    // MARK: - transcribe() — HTTP errors

    func test_transcribe_throwsHTTPError_on4xxResponse() async throws {
        let audioURL = try makeTempAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let session = makeMockURLSession { [self] _ in
            (httpResponse(status: 401), Data("{\"error\":\"unauthorized\"}".utf8))
        }
        let sut = SarvamSpeechClient(session: session, testAPIKey: fakeKey)

        do {
            _ = try await sut.transcribe(audioURL: audioURL)
            XCTFail("Expected httpError")
        } catch SarvamError.httpError(let code, _) {
            XCTAssertEqual(code, 401)
        }
    }

    func test_transcribe_throwsHTTPError_on5xxResponse() async throws {
        let audioURL = try makeTempAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let session = makeMockURLSession { [self] _ in
            (httpResponse(status: 503), Data())
        }
        let sut = SarvamSpeechClient(session: session, testAPIKey: fakeKey)

        do {
            _ = try await sut.transcribe(audioURL: audioURL)
            XCTFail("Expected httpError")
        } catch SarvamError.httpError(let code, _) {
            XCTAssertEqual(code, 503)
        }
    }

    // MARK: - transcribe() — empty transcript

    func test_transcribe_throwsEmptyTranscript_whenServerReturnsBlank() async throws {
        let audioURL = try makeTempAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let body = Data("{\"transcript\":\"\"}".utf8)
        let session = makeMockURLSession { [self] _ in (httpResponse(status: 200), body) }
        let sut = SarvamSpeechClient(session: session, testAPIKey: fakeKey)

        do {
            _ = try await sut.transcribe(audioURL: audioURL)
            XCTFail("Expected emptyTranscript error")
        } catch SarvamError.emptyTranscript {
            // expected
        }
    }

    // MARK: - transcribe() — success

    func test_transcribe_returnsTranscript_onSuccess() async throws {
        let audioURL = try makeTempAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let expected = "নিউটনের দ্বিতীয় সূত্র কি?"
        let body = try JSONEncoder().encode(["transcript": expected])
        let session = makeMockURLSession { [self] _ in (httpResponse(status: 200), body) }
        let sut = SarvamSpeechClient(session: session, testAPIKey: fakeKey)

        let result = try await sut.transcribe(audioURL: audioURL)
        XCTAssertEqual(result, expected)
    }

    func test_transcribe_trimesWhitespace_fromTranscript() async throws {
        let audioURL = try makeTempAudioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let body = try JSONEncoder().encode(["transcript": "  hello  "])
        let session = makeMockURLSession { [self] _ in (httpResponse(status: 200), body) }
        let sut = SarvamSpeechClient(session: session, testAPIKey: fakeKey)

        let result = try await sut.transcribe(audioURL: audioURL)
        XCTAssertEqual(result, "hello")
    }

    // MARK: - synthesise() — missing API key

    func test_synthesise_throwsMissingAPIKey_whenNoKeyConfigured() async {
        let sut = SarvamSpeechClient(session: URLSession.shared, testAPIKey: nil)
        do {
            _ = try await sut.synthesise(text: "Hello")
            XCTFail("Expected missingAPIKey error")
        } catch SarvamError.missingAPIKey {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - synthesise() — HTTP errors

    func test_synthesise_throwsHTTPError_on4xxResponse() async throws {
        let session = makeMockURLSession { [self] _ in
            (httpResponse(status: 429), Data("{\"error\":\"rate_limit\"}".utf8))
        }
        let sut = SarvamSpeechClient(session: session, testAPIKey: fakeKey)

        do {
            _ = try await sut.synthesise(text: "Hello")
            XCTFail("Expected httpError")
        } catch SarvamError.httpError(let code, _) {
            XCTAssertEqual(code, 429)
        }
    }

    // MARK: - synthesise() — success

    func test_synthesise_returnsAudioData_onSuccess() async throws {
        let fakeAudio = Data(repeating: 0xAB, count: 64)
        let b64 = fakeAudio.base64EncodedString()
        let body = try JSONSerialization.data(withJSONObject: ["audios": [b64]])

        let session = makeMockURLSession { [self] _ in (httpResponse(status: 200), body) }
        let sut = SarvamSpeechClient(session: session, testAPIKey: fakeKey)

        let result = try await sut.synthesise(text: "নমস্কার")
        XCTAssertEqual(result, fakeAudio)
    }
}
