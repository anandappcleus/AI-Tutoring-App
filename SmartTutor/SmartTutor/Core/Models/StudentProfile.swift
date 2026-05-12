//
//  StudentProfile.swift
//  SmartTutor
//
//  Sprint 1 scaffold — Keychain persistence added in Sprint 5.
//
//  Copilot prompt (Sprint 5, Task 3):
//  // Codable StudentProfile: id, name, email, preferredLanguage, examTarget, isPremium
//  // static func load() -> StudentProfile? — reads from Keychain
//  // func save() — writes JSON to Keychain using Security framework
//

import Foundation

struct StudentProfile: Codable, Equatable {
    let id: String
    var name: String
    var email: String
    var preferredLanguage: Language
    var examTarget: ExamTarget
    var isPremium: Bool

    // MARK: - Language

    enum Language: String, Codable, CaseIterable, Identifiable {
        case bengali = "bn"
        case hindi   = "hi"
        case tamil   = "ta"
        case telugu  = "te"
        case marathi = "mr"
        case english = "en"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .bengali: return "বাংলা (Bengali)"
            case .hindi:   return "हिन्दी (Hindi)"
            case .tamil:   return "தமிழ் (Tamil)"
            case .telugu:  return "తెలుగు (Telugu)"
            case .marathi: return "मराठी (Marathi)"
            case .english: return "English"
            }
        }
    }

    // MARK: - Exam Target

    enum ExamTarget: String, Codable, CaseIterable, Identifiable {
        case jee    = "JEE"
        case neet   = "NEET"
        case wbchse = "WBCHSE"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .jee:    return "JEE Mains & Advanced"
            case .neet:   return "NEET UG"
            case .wbchse: return "WB Board (WBCHSE)"
            }
        }
    }

    // MARK: - Keychain (TODO Sprint 5)

    // static func load() -> StudentProfile? { ... }
    // func save() { ... }
    // static func clear() { ... }
}
