//
//  SarvamSpeechClient.swift
//  SmartTutor
//
//  Sprint 6 — Sarvam AI speech services.
//    • STT: Saaras v2  POST https://api.sarvam.ai/speech-to-text   (multipart)
//    • TTS: Bulbul v2  POST https://api.sarvam.ai/text-to-speech   (JSON)
//
//  The API key is read from Info.plist key "SARVAM_API_KEY".
//  Set it via your .xcconfig or directly in Info.plist for development.
//
//  Language codes follow BCP-47: "bn-IN", "hi-IN", "en-IN", "ta-IN", etc.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.smarttutor.app", category: "SarvamSpeechClient")

// MARK: - Errors

enum SarvamError: LocalizedError {
    case missingAPIKey
    case httpError(Int, String)
    case decodingError(String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Sarvam API key is not configured. Add SARVAM_API_KEY to Info.plist."
        case .httpError(let code, let body):
            return "Sarvam API error \(code): \(body)"
        case .decodingError(let detail):
            return "Sarvam response parsing failed: \(detail)"
        case .emptyTranscript:
            return "No speech detected. Please try again."
        }
    }
}

// MARK: - Response models

private struct STTResponse: Decodable {
    let transcript: String
}

private struct TTSResponse: Decodable {
    let audios: [String]   // base64-encoded WAV chunks
}

// MARK: - Client

/// Thread-safe wrapper around the Sarvam AI speech REST API.
/// Use `SarvamSpeechClient.shared` in production; inject a custom instance in tests.
actor SarvamSpeechClient {

    static let shared = SarvamSpeechClient()

    private let sttURL = URL(string: "https://api.sarvam.ai/speech-to-text")!
    private let ttsURL = URL(string: "https://api.sarvam.ai/text-to-speech")!
    private let session: URLSession
    /// Non-nil only in unit tests — bypasses Info.plist lookup.
    private let testAPIKey: String?

    /// Reads the API key at call-time so xcconfig changes are picked up without restart.
    private var apiKey: String {
        get throws {
            if let key = testAPIKey { return key }
            guard let key = Bundle.main.infoDictionary?["SARVAM_API_KEY"] as? String,
                  !key.isEmpty else {
                throw SarvamError.missingAPIKey
            }
            return key
        }
    }

    init(session: URLSession = .shared, testAPIKey: String? = nil) {
        self.session = session
        self.testAPIKey = testAPIKey
    }

    // MARK: - STT — audio file → transcript

    /// Transcribes a recorded audio file using Sarvam Saaras v2.
    ///
    /// - Parameters:
    ///   - audioURL: Local file URL of the recorded audio (WAV, 16 kHz mono recommended).
    ///   - languageCode: BCP-47 code, e.g. "bn-IN", "hi-IN". Defaults to "bn-IN".
    /// - Returns: Transcribed text string.
    func transcribe(audioURL: URL, languageCode: String = "en-IN") async throws -> String {
        let key = try apiKey
        let audioData = try Data(contentsOf: audioURL)
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: sttURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "api-subscription-key")

        var body = Data()

        // file
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        body.append("\r\n")

        // language_code
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"language_code\"\r\n\r\n")
        body.append("\(languageCode)\r\n")

        // model
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.append("saaras:v2\r\n")

        // closing boundary
        body.append("--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        do {
            let decoded = try JSONDecoder().decode(STTResponse.self, from: data)
            let text = decoded.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw SarvamError.emptyTranscript }
            logger.info("STT ok  lang=\(languageCode)  chars=\(text.count)")
            return text
        } catch let err as SarvamError {
            throw err
        } catch {
            throw SarvamError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - TTS — text → audio Data

    /// Synthesises speech from text using Sarvam Bulbul v2.
    ///
    /// - Parameters:
    ///   - text: The text to speak (≤ 500 characters per call).
    ///   - languageCode: BCP-47 code, e.g. "bn-IN", "hi-IN".
    /// - Returns: Raw WAV audio `Data` ready for `AVAudioPlayer`.
    func synthesise(text: String, languageCode: String = "en-IN") async throws -> Data {
        let key = try apiKey

        let payload: [String: Any] = [
            "inputs": [text],
            "target_language_code": languageCode,
            "speaker": "meera",
            "model": "bulbul:v2",
            "enable_preprocessing": true,
        ]

        var request = URLRequest(url: ttsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "api-subscription-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        do {
            let decoded = try JSONDecoder().decode(TTSResponse.self, from: data)
            guard let b64 = decoded.audios.first,
                  let audioData = Data(base64Encoded: b64) else {
                throw SarvamError.decodingError("No audio in TTS response")
            }
            logger.info("TTS ok  lang=\(languageCode)  bytes=\(audioData.count)")
            return audioData
        } catch let err as SarvamError {
            throw err
        } catch {
            throw SarvamError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            logger.error("Sarvam HTTP \(http.statusCode): \(body)")
            throw SarvamError.httpError(http.statusCode, body)
        }
    }
}

// MARK: - Data convenience

private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}
