//
//  StudentProfile.swift
//  SmartTutor
//
//  Sprint 5 — Keychain persistence implemented.
//
//  Stored as JSON in a single Keychain generic password item.
//  Call StudentProfile.load() on app start; call profile.save() after
//  login or any profile mutation; call StudentProfile.clear() on logout.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.smarttutor.app", category: "StudentProfile")

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

    // MARK: - Factory from server response

    init(from response: StudentResponse) {
        self.id    = response.id
        self.name  = response.name
        self.email = response.email
        self.isPremium = response.isPremium
        self.preferredLanguage = Language(rawValue: response.preferredLanguage) ?? .english
        self.examTarget        = ExamTarget(rawValue: response.examTarget) ?? .jee
    }

    // Swift synthesised memberwise init is also available for tests / previews
    init(id: String, name: String, email: String,
         preferredLanguage: Language, examTarget: ExamTarget, isPremium: Bool) {
        self.id = id; self.name = name; self.email = email
        self.preferredLanguage = preferredLanguage
        self.examTarget = examTarget; self.isPremium = isPremium
    }

    // MARK: - Keychain persistence

    private static let keychainService = "com.smarttutor.app"
    private static let keychainKey     = "student_profile"

    /// Load the stored profile from Keychain.
    /// Returns nil on first install or after logout.
    static func load() -> StudentProfile? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                logger.warning("StudentProfile.load: unexpected status=\(status)")
            }
            return nil
        }

        do {
            let profile = try JSONDecoder().decode(StudentProfile.self, from: data)
            logger.debug("StudentProfile.load: ok  id=\(profile.id)")
            return profile
        } catch {
            logger.error("StudentProfile.load: decode_error=\(error.localizedDescription)")
            return nil
        }
    }

    /// Persist this profile to Keychain (insert or replace).
    func save() {
        guard let data = try? JSONEncoder().encode(self) else {
            logger.error("StudentProfile.save: encode_error  id=\(id)")
            return
        }
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainKey,
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]

        var status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        if status == errSecSuccess {
            logger.info("StudentProfile.save: ok  id=\(id)  premium=\(isPremium)")
        } else {
            logger.error("StudentProfile.save: failed  status=\(status)  id=\(id)")
        }
    }

    /// Remove the stored profile on logout.
    static func clear() {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainKey,
        ]
        let status = SecItemDelete(query as CFDictionary)
        logger.info("StudentProfile.clear: status=\(status)")
    }
}
