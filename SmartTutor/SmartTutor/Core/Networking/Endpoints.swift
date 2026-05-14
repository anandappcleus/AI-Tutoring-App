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
    case ask(question: String, language: String?)

    // Study Plan — returns today's Curriculum Planner output
    case plan(studentId: String)

    // Progress
    case progress(studentId: String)
    case syncAnswers([SyncAnswerPayload])

    // Profile update (called from Onboarding and Settings)
    case updateProfile(language: String?, examTarget: String?, name: String?)

    // Sprint 8: Offline packs (placeholder — not wired yet)
    // case packs
    // case downloadPack(id: String)

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
        }
    }

    // MARK: HTTP Method

    var httpMethod: String {
        switch self {
        case .login, .register, .refresh, .ask, .syncAnswers: return "POST"
        case .me, .plan, .progress:                            return "GET"
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

        case .ask(let question, let language):
            var body: [String: String] = ["question": question]
            if let lang = language { body["language"] = lang }
            return try? JSONSerialization.data(withJSONObject: body)

        case .syncAnswers(let answers):
            return try? encoder.encode(["answers": answers])

        case .updateProfile(let language, let examTarget, let name):
            var body: [String: String] = [:]
            if let lang = language      { body["preferred_language"] = lang }
            if let exam = examTarget    { body["exam_target"] = exam }
            if let n = name             { body["name"] = n }
            return try? JSONSerialization.data(withJSONObject: body)

        default:
            return nil
        }
    }
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
    let explanation: String
    let workedExample: String
    let practiceProblems: [PracticeProblem]
    let language: String
    let rawOutput: String?

    struct PracticeProblem: Decodable, Equatable {
        let question: String
        let answer: String
    }

    enum CodingKeys: String, CodingKey {
        case explanation, language
        case workedExample    = "worked_example"
        case practiceProblems = "practice_problems"
        case rawOutput        = "raw_output"
    }
}

struct StudyPlanResponse: Decodable {
    let studentId: String
    let planDate: String
    let topics: [TopicSlot]
    let createdAt: String

    struct TopicSlot: Decodable {
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

struct ProgressResponse: Decodable {
    let studentId: String
    let weekStart: String
    let weekEnd: String
    let totalQuestions: Int
    let correctQuestions: Int
    let overallAccuracyPct: Double
    let topics: [TopicProgress]
    let weakTopics: [String]

    struct TopicProgress: Decodable {
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
    let inserted: Int
    let skipped: Int
}
