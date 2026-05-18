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

/// A single prior conversation turn sent to the backend for multi-turn context.
struct ConversationTurn: Encodable {
    let role: String      // "user" or "assistant"
    let content: String
}

enum Endpoint {
    // Auth
    case login(email: String, password: String)   // POST /auth/token (form-encoded)
    case register(name: String, email: String, password: String,
                  language: String, examTarget: String)
    case refresh(refreshToken: String)
    case me                                        // GET /auth/me

    // Study — triggers Question Generator agent
    case ask(question: String, language: String?, examType: String?, imageBase64: String?,
             history: [ConversationTurn])

    // Chat history — returns last session turns from Redis
    case chatHistory                               // GET /ask/history

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

    // Full Paper Mode
    case mockTestQuestions(paperId: String)                                           // GET  /mock-tests/{id}/questions
    case startAttempt(paperId: String)                                                // POST /mock-tests/{id}/attempts
    case saveAnswers(paperId: String, attemptId: String, answers: [String: String])   // PATCH /mock-tests/{id}/attempts/{aid}
    case submitAttempt(paperId: String, attemptId: String)                            // POST /mock-tests/{id}/attempts/{aid}/submit
    case attemptResult(attemptId: String)                                             // GET  /mock-tests/attempts/{aid}/result

    // MARK: Path

    var path: String {
        switch self {
        case .login:                return "/auth/token"
        case .register:             return "/auth/register"
        case .refresh:              return "/auth/refresh"
        case .me:                   return "/auth/me"
        case .ask:                  return "/ask"
        case .chatHistory:          return "/ask/history"
        case .plan(let id):         return "/plan/\(id)"
        case .progress(let id):     return "/progress/\(id)"
        case .syncAnswers:          return "/sync-answers"
        case .updateProfile:        return "/auth/me"
        case .registerDeviceToken:  return "/auth/device-token"
        case .packs:                return "/packs"
        case .downloadPack(let id): return "/packs/\(id)/download"
        case .mockTests:            return "/mock-tests"
        case .mockTestQuestions(let pid):            return "/mock-tests/\(pid)/questions"
        case .startAttempt(let pid):                 return "/mock-tests/\(pid)/attempts"
        case .saveAnswers(let pid, let aid, _):      return "/mock-tests/\(pid)/attempts/\(aid)"
        case .submitAttempt(let pid, let aid):       return "/mock-tests/\(pid)/attempts/\(aid)/submit"
        case .attemptResult(let aid):               return "/mock-tests/attempts/\(aid)/result"
        }
    }

    // MARK: HTTP Method

    var httpMethod: String {
        switch self {
        case .login, .register, .refresh, .ask, .syncAnswers,
             .registerDeviceToken:                             return "POST"
        case .me, .plan, .progress, .packs, .downloadPack, .mockTests,
             .chatHistory, .mockTestQuestions, .attemptResult: return "GET"
        case .startAttempt, .submitAttempt:                    return "POST"
        case .updateProfile, .saveAnswers:                     return "PATCH"
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

        case .ask(let question, let language, let examType, let imageBase64, let history):
            var body: [String: Any] = ["question": question]
            if let lang = language      { body["language"] = lang }
            if let exam = examType      { body["exam_type"] = exam }
            if let b64 = imageBase64    { body["image_b64"] = b64 }
            if !history.isEmpty {
                body["history"] = history.map { ["role": $0.role, "content": $0.content] }
            }
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

        case .saveAnswers(_, _, let answers):
            return try? JSONSerialization.data(withJSONObject: ["answers": answers])

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
    let dayStreak: Int
    let estimatedStudyMinWeek: Int
    let dailyActivity: [DailyActivity]
    let subjectAccuracy: [SubjectAccuracy]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        studentId           = try c.decode(String.self,          forKey: .studentId)
        weekStart           = try c.decode(String.self,          forKey: .weekStart)
        weekEnd             = try c.decode(String.self,          forKey: .weekEnd)
        totalQuestions      = try c.decode(Int.self,             forKey: .totalQuestions)
        correctQuestions    = try c.decode(Int.self,             forKey: .correctQuestions)
        overallAccuracyPct  = try c.decode(Double.self,          forKey: .overallAccuracyPct)
        topics              = try c.decode([TopicProgress].self, forKey: .topics)
        weakTopics          = try c.decode([String].self,        forKey: .weakTopics)
        // New fields — safe defaults for old cached responses
        dayStreak              = try c.decodeIfPresent(Int.self,              forKey: .dayStreak)              ?? 0
        estimatedStudyMinWeek  = try c.decodeIfPresent(Int.self,              forKey: .estimatedStudyMinWeek)  ?? 0
        dailyActivity          = try c.decodeIfPresent([DailyActivity].self,  forKey: .dailyActivity)          ?? []
        subjectAccuracy        = try c.decodeIfPresent([SubjectAccuracy].self, forKey: .subjectAccuracy)       ?? []
    }

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

    struct DailyActivity: Codable {
        let dayName: String
        let questions: Int
        let estimatedMin: Int

        enum CodingKeys: String, CodingKey {
            case dayName = "day_name"
            case questions
            case estimatedMin = "estimated_min"
        }
    }

    struct SubjectAccuracy: Codable {
        let subject: String
        let total: Int
        let correct: Int
        let accuracyPct: Double

        enum CodingKeys: String, CodingKey {
            case subject, total, correct
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
        case dayStreak        = "day_streak"
        case estimatedStudyMinWeek = "estimated_study_min_week"
        case dailyActivity    = "daily_activity"
        case subjectAccuracy  = "subject_accuracy"
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
