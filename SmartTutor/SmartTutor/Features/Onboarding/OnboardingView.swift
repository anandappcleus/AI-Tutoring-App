//
//  OnboardingView.swift
//  SmartTutor
//
//  Converted from OnboardingFlow.tsx
//  3-step: language → exam → name
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isOnboardingComplete: Bool
    @EnvironmentObject private var appState: AppState

    @State private var step = 1
    @State private var selectedLanguage = ""
    @State private var selectedExam = ""
    @State private var name = ""

    let languages: [(code: String, name: String, flag: String)] = [
        ("bn", "বাংলা", "🇮🇳"),
        ("hi", "हिन्दी", "🇮🇳"),
        ("en", "English", "🇬🇧"),
        ("ta", "தமிழ்", "🇮🇳"),
        ("te", "తెలుగు", "🇮🇳"),
        ("mr", "मराठी", "🇮🇳"),
    ]

    let exams: [(id: String, name: String, icon: String)] = [
        ("jee",    "JEE (Mains & Advanced)", "🎓"),
        ("neet",   "NEET",                   "⚕️"),
        ("wbchse", "WB Board (Class 11-12)", "📚"),
    ]

    private var canProceed: Bool {
        switch step {
        case 1: return !selectedLanguage.isEmpty
        case 2: return !selectedExam.isEmpty
        case 3: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        default: return false
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.36, green: 0.33, blue: 0.93),
                    Color(red: 0.58, green: 0.28, blue: 0.91),
                    Color(red: 0.93, green: 0.33, blue: 0.58),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar
                HStack(spacing: 8) {
                    ForEach(1...3, id: \.self) { s in
                        Capsule()
                            .fill(s <= step ? Color.white : Color.white.opacity(0.3))
                            .frame(height: 4)
                            .animation(.easeInOut(duration: 0.3), value: step)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)

                Spacer()

                Group {
                    switch step {
                    case 1:
                        LanguageStepView(languages: languages, selectedLanguage: $selectedLanguage)
                    case 2:
                        ExamStepView(exams: exams, selectedExam: $selectedExam)
                    default:
                        NameStepView(name: $name, selectedLanguage: selectedLanguage, selectedExam: selectedExam)
                    }
                }
                .padding(.horizontal, 24)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        if step < 3 {
                            step += 1
                        } else {
                            // Save language + exam preferences to server, then mark complete
                            let lang = selectedLanguage.isEmpty ? "en" : selectedLanguage
                            let exam = selectedExam.isEmpty ? "JEE" : selectedExam.uppercased()
                            let displayName = name.trimmingCharacters(in: .whitespaces)
                            Task {
                                await appState.updateProfile(
                                    language: lang,
                                    examTarget: exam,
                                    name: displayName.isEmpty ? nil : displayName
                                )
                            }
                            isOnboardingComplete = true
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(step == 3 ? "Get Started" : "Continue")
                            .font(.system(size: 17, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(Color(red: 0.58, green: 0.28, blue: 0.91))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                }
                .disabled(!canProceed)
                .opacity(canProceed ? 1 : 0.5)
                .padding(.horizontal, 24)
                .padding(.bottom, 52)
            }
        }
    }
}

// MARK: - Step 1: Language

private struct LanguageStepView: View {
    let languages: [(code: String, name: String, flag: String)]
    @Binding var selectedLanguage: String

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 72, height: 72)
                    Image(systemName: "globe")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                }
                Text("Choose Your Language")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text("Select your preferred learning language")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(languages, id: \.code) { lang in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedLanguage = lang.code
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text(lang.flag)
                                .font(.system(size: 32))
                            Text(lang.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(
                                    selectedLanguage == lang.code
                                    ? Color(red: 0.58, green: 0.28, blue: 0.91)
                                    : .white
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(selectedLanguage == lang.code ? Color.white : Color.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .scaleEffect(selectedLanguage == lang.code ? 1.05 : 1.0)
                    }
                }
            }
        }
    }
}

// MARK: - Step 2: Exam

private struct ExamStepView: View {
    let exams: [(id: String, name: String, icon: String)]
    @Binding var selectedExam: String

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 72, height: 72)
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                }
                Text("Select Your Exam")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text("What are you preparing for?")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }

            VStack(spacing: 12) {
                ForEach(exams, id: \.id) { exam in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedExam = exam.id
                        }
                    } label: {
                        HStack(spacing: 16) {
                            Text(exam.icon)
                                .font(.system(size: 30))
                            Text(exam.name)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(selectedExam == exam.id ? .black : .white)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            if selectedExam == exam.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 22))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .background(selectedExam == exam.id ? Color.white : Color.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .scaleEffect(selectedExam == exam.id ? 1.02 : 1.0)
                    }
                }
            }
        }
    }
}

// MARK: - Step 3: Name

private struct NameStepView: View {
    @Binding var name: String
    let selectedLanguage: String
    let selectedExam: String

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 72, height: 72)
                    Image(systemName: "sparkles")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                }
                Text("Welcome!")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
                Text("What should we call you?")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }

            VStack(spacing: 16) {
                TextField("Enter your name", text: $name)
                    .font(.system(size: 17))
                    .foregroundColor(.white)
                    .tint(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .background(Color.white.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                    )

                // Summary card
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text("✨")
                        Text("Your Setup")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Divider().background(Color.white.opacity(0.3))
                    HStack {
                        Text("Language:")
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text(selectedLanguage.uppercased())
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    HStack {
                        Text("Exam:")
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text(selectedExam.uppercased())
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .font(.system(size: 14))
                .padding(18)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }
}
