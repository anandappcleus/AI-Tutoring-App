//
//  Endpoints.swift
//  SmartTutor
//
//  Sprint 1 scaffold — full implementation in Sprint 5.
//
//  Copilot prompt (Sprint 5, Task 2):
//  // Enum Endpoint with cases: ask, plan(studentId:), syncAnswers, progress(studentId:), login
//  // var path: String — relative URL path for each case
//  // var httpMethod: String — "GET" or "POST"
//

import Foundation

// MARK: - Endpoint Definitions

enum Endpoint {
    // Auth
    case login(email: String, password: String)

    // Study — triggers Question Generator agent
    case ask(studentId: String, question: String, language: String)

    // Study Plan — returns today's Curriculum Planner output
    case plan(studentId: String)

    // Progress
    case progress(studentId: String)
    case syncAnswers([SyncAnswerPayload])

    // Sprint 8: Offline packs
    // case packs
    // case downloadPack(id: String)

    var path: String {
        switch self {
        case .login:               return "/auth/token"
        case .ask:                 return "/ask"
        case .plan(let id):        return "/plan/\(id)"
        case .progress(let id):    return "/progress/\(id)"
        case .syncAnswers:         return "/sync-answers"
        }
    }

    var httpMethod: String {
        switch self {
        case .login, .ask, .syncAnswers: return "POST"
        case .plan, .progress:           return "GET"
        }
    }

    var url: URL {
        AppConfig.apiBaseURL.appendingPathComponent(path)
    }
}

// MARK: - Request / Response Payload Types (stubs — Sprint 5 fills these in)

struct SyncAnswerPayload: Codable {
    let id: String
    let question: String
    let topic: String?
    let isCorrect: Bool
    let answeredAt: Date

    enum CodingKeys: String, CodingKey {
        case id, question, topic
        case isCorrect   = "is_correct"
        case answeredAt  = "answered_at"
    }
}
