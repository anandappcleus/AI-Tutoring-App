//
//  Endpoints.swift
//  SmartTutor
//
//  Sprint 5 — full implementation.
//
//  Each Endpoint case carries its payload inline so the builder is
//  self-contained: no scattered encoding logic in callers.
//

import Foundation

// MARK: - Endpoint Definitions

enum Endpoint {
    // Auth
    case login(email: String, password: String)   // POST /auth/token (form-encoded)
    case register(name: String, email: String, password: String,
                  language: String, examTarget: String)
    case refresh(refreshToken: String)
    case me                                        // GET /auth/me

    // Study — triggers Question Generator agent
    case ask(question: String, language: String?, examType: String?, imageBase64: String?)

    // Study Plan — returns today's Curriculum Planner output
    case plan(studentId: String)

    // Progress
    case progress(studentId: String)
    case syncAnswers([SyncAnswerPayload])

    // Profile update (called from Onboarding and Settings)
    case updateProfile(language: String?, examTarget: String?, name: String?)

    // Sprint 6: APNs device token upload
    case registerDeviceToken(token: String)

    // Sprint 8: Offline packs
    case packs                          // GET /packs
    case downloadPack(id: String)       // GET /packs/:id/download

    // Sprint 7+: Mock tests (static fallback in MockTestsViewModel if 404)
    case mockTests                      // GET /mock-tests

    // MARK: Path

    var path: String {
        switch self {
        case .login:                return "/auth/token"
        case .register:             return "/auth/register"
        case .refresh:              return "/auth/refresh"
        case .me:                   return "/auth/me"
        case .ask:                  return "/ask"
        case .plan(let id):         return "/plan/\(id)"
        case .progress(let id):     return "/progress/\(id)"
        case .syncAnswers:          return "/sync-answers"
        case .updateProfile:        return "/auth/me"
        case .registerDeviceToken:  return "/auth/device-token"
        case .packs:                return "/packs"
        case .downloadPack(let id): return "/packs/\(id)/download"
        case .mockTests:            return "/mock-tests"
        }
    }

    // MARK: HTTP Method

    var httpMethod: String {
        switch self {
        case .login, .register, .refresh, .ask, .syncAnswers,
             .registerDeviceToken:                             return "POST"
        case .me, .plan, .progress, .packs, .downloadPack, .mockTests:  return "GET"
        case .updateProfile:                                   return "PATCH"
        }
    }

    // MARK: URL

    var url: URL {
        AppConfig.apiBaseURL.appendingPathComponent(path)
    }

    // MARK: Request body (JSON-encoded; nil for GET or form-encoded endpoints)

    var requestBody: Data? {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601

        switch self {
        case .register(let name, let email, let password, let lang, let exam):
            let body: [String: String] = [
                "name": name, "email": email, "password": password,
                "preferred_language": lang, "exam_target": exam,
            ]
            return try? JSONSerialization.data(withJSONObject: body)

        case .refresh(let token):
            return try? JSONSerialization.data(withJSONObject: ["refresh_token": token])

        case .ask(let question, let language, let examType, let imageBase64):
            var body: [String: String] = ["question": question]
            if let lang = language      { body["language"] = lang }
            if let exam = examType      { body["exam_type"] = exam }
            if let b64 = imageBase64    { body["image_b64"] = b64 }
            return try? JSONSerialization.data(withJSONObject: body)

        case .syncAnswers(let answers):
            return try? encoder.encode(["answers": answers])

        case .updateProfile(let language, let examTarget, let name):
            var body: [String: String] = [:]
            if let lang = language      { body["preferred_language"] = lang }
            if let exam = examTarget    { body["exam_target"] = exam }
            if let n = name             { body["name"] = n }
            return try? JSONSerialization.data(withJSONObject: body)

        case .registerDeviceToken(let token):
            return try? JSONSerialization.data(withJSONObject: ["token": token])

        default:
            return nil
        }
    }
}

// MARK: - APNs Device Token Response

struct DeviceTokenResponse: Decodable {
    let registered: Bool
}

// MARK: - Request / Response Payload Types

struct SyncAnswerPayload: Codable {
    let question: String
    let topic: String?
    let subject: String?
    let isCorrect: Bool
    let answeredAt: Date

    enum CodingKeys: String, CodingKey {
        case question, topic, subject
        case isCorrect  = "is_correct"
        case answeredAt = "answered_at"
    }
}

// MARK: - Response Types

struct AskResponse: Decodable, Equatable {
    let answer: String             // MCQ option letter / numerical value / one-line answer
    let explanation: String
    let workedExample: String
    let practiceProblems: [PracticeProblem]
    let language: String
    let questionType: String?      // MCQ | Integer | Short Answer | Long Answer
    let marks: Int?
    let markingScheme: String?     // e.g. "+4/-1", "no negative marking"
    let rawOutput: String?

    struct PracticeProblem: Decodable, Equatable {
        let question: String
        let answer: String
        let questionType: String?
        let marks: Int?
        let markingScheme: String?

        enum CodingKeys: String, CodingKey {
            case question, answer
            case questionType    = "question_type"
            case marks
            case markingScheme   = "marking_scheme"
        }
    }

    enum CodingKeys: String, CodingKey {
        case answer, explanation, language, marks
        case workedExample    = "worked_example"
        case practiceProblems = "practice_problems"
        case questionType     = "question_type"
        case markingScheme    = "marking_scheme"
        case rawOutput        = "raw_output"
    }
}

struct StudyPlanResponse: Codable {
    let studentId: String
    let planDate: String
    let topics: [TopicSlot]
    let createdAt: String

    struct TopicSlot: Codable {
        let topic: String
        let durationMin: Int
        let priority: Int

        enum CodingKeys: String, CodingKey {
            case topic, priority
            case durationMin = "duration_min"
        }
    }

    enum CodingKeys: String, CodingKey {
        case topics
        case studentId = "student_id"
        case planDate  = "plan_date"
        case createdAt = "created_at"
    }
}

struct ProgressResponse: Codable {
    let studentId: String
    let weekStart: String
    let weekEnd: String
    let totalQuestions: Int
    let correctQuestions: Int
    let overallAccuracyPct: Double
    let topics: [TopicProgress]
    let weakTopics: [String]

    struct TopicProgress: Codable {
        let topic: String
        let subject: String?
        let correct: Int
        let total: Int
        let accuracyPct: Double

        enum CodingKeys: String, CodingKey {
            case topic, subject, correct, total
            case accuracyPct = "accuracy_pct"
        }
    }

    enum CodingKeys: String, CodingKey {
        case topics
        case studentId        = "student_id"
        case weekStart        = "week_start"
        case weekEnd          = "week_end"
        case totalQuestions   = "total_questions"
        case correctQuestions = "correct_questions"
        case overallAccuracyPct = "overall_accuracy_pct"
        case weakTopics       = "weak_topics"
    }
}

struct StudentResponse: Decodable {
    let id: String
    let name: String
    let email: String
    let preferredLanguage: String
    let examTarget: String
    let isPremium: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, email
        case preferredLanguage = "preferred_language"
        case examTarget        = "exam_target"
        case isPremium         = "is_premium"
        case createdAt         = "created_at"
    }
}

struct SyncResponse: Decodable {
    let synced: Int
    let skipped: Int
}

// MARK: - Sprint 8: Offline Pack Response Types

struct PackResponse: Decodable, Identifiable {
    let id: String
    let subject: String
    let topic: String
    let examTarget: String
    let language: String
    let questionCount: Int
    let sizeKB: Int
    let iconName: String

    enum CodingKeys: String, CodingKey {
        case id, subject, topic, language
        case examTarget   = "exam_target"
        case questionCount = "question_count"
        case sizeKB       = "size_kb"
        case iconName     = "icon_name"
    }
}

struct PackDownloadResponse: Decodable {
    let packId: String
    let questions: [QuestionItem]

    struct QuestionItem: Decodable {
        let id: String
        let topic: String
        let subject: String
        let questionText: String
        let answerText: String
        let language: String

        enum CodingKeys: String, CodingKey {
            case id, topic, subject, language
            case questionText = "question_text"
            case answerText   = "answer_text"
        }
    }

    enum CodingKeys: String, CodingKey {
        case packId   = "pack_id"
        case questions
    }
}
