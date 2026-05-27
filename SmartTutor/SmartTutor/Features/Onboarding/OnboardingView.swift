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
    @Environment(AppState.self) private var appState
    @State private var vm = OnboardingViewModel()

    // Phase 1 launch languages — Bengali + others added in Sprint 10
    let languages: [(code: String, name: String, flag: String)] = [
        ("en", "English",  "🇬🇧"),
        ("hi", "हिन्दी",   "🇮🇳"),
    ]

    // Coming-soon languages shown greyed out below the active list
    let comingSoonLanguages: [String] = [
        "বাংলা", "தமிழ்", "తెలుగు", "मराठी",
    ]

    let exams: [(id: String, name: String, icon: String)] = [
        ("jee",    "JEE (Mains & Advanced)", "🎓"),
        ("neet",   "NEET",                   "⚕️"),
        ("wbchse", "WB Board (Class 11-12)", "📚"),
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: AppColors.gradientColors),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar
                HStack(spacing: 8) {
                    ForEach(1...3, id: \.self) { s in
                        Capsule()
                            .fill(s <= vm.step ? Color.white : Color.white.opacity(0.3))
                            .frame(height: 4)
                            .animation(.easeInOut(duration: 0.3), value: vm.step)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)

                Spacer()

                Group {
                    switch vm.step {
                    case 1:
                        LanguageStepView(
                            languages: languages,
                            comingSoon: comingSoonLanguages,
                            selectedLanguage: $vm.selectedLanguage
                        )
                    case 2:
                        ExamStepView(exams: exams, selectedExam: $vm.selectedExam)
                    default:
                        NameStepView(name: $vm.name, selectedLanguage: vm.selectedLanguage, selectedExam: vm.selectedExam)
                    }
                }
                .padding(.horizontal, 24)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer()

                Button {
                    AppLogger.userAction(AppLogger.auth,
                                         action: vm.step == 3 ? "onboarding-submit" : "onboarding-continue",
                                         context: "step-\(vm.step)")
                    withAnimation(.easeInOut(duration: 0.35)) {
                        if vm.step < 3 {
                            vm.advance()
                        } else {
                            Task { await vm.submit(via: appState) }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if vm.isSubmitting {
                            ProgressView()
                                .tint(Color(red: 0.58, green: 0.28, blue: 0.91))
                        } else {
                            Text(vm.step == 3 ? "Get Started" : "Continue")
                                .font(.system(size: 17, weight: .bold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 15, weight: .bold))
                        }
                    }
                    .foregroundStyle(Color(red: 0.58, green: 0.28, blue: 0.91))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                }
                .disabled(!vm.canProceed || vm.isSubmitting)
                .opacity(vm.canProceed && !vm.isSubmitting ? 1 : 0.5)
                .padding(.horizontal, 24)
                .padding(.bottom, 52)
                .onChange(of: vm.isComplete) { _, done in
                    if done { isOnboardingComplete = true }
                }
            }
        }
    }
}

// MARK: - Step 1: Language

private struct LanguageStepView: View {
    let languages: [(code: String, name: String, flag: String)]
    let comingSoon: [String]
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
                        .foregroundStyle(.white)
                }
                Text("Choose Your Language")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Select your preferred learning language")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
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
                                .foregroundStyle(
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

            // Coming-soon languages (greyed out)
            if !comingSoon.isEmpty {
                VStack(spacing: 8) {
                    Text("More languages coming soon")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    HStack(spacing: 8) {
                        ForEach(comingSoon, id: \.self) { lang in
                            Text(lang)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Capsule())
                        }
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
                        .foregroundStyle(.white)
                }
                Text("Select Your Exam")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("What are you preparing for?")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
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
                                .foregroundStyle(selectedExam == exam.id ? .black : .white)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            if selectedExam == exam.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
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
                        .foregroundStyle(.white)
                }
                Text("Welcome!")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                Text("What should we call you?")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }

            VStack(spacing: 16) {
                TextField("Enter your name", text: $name)
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
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
                            .foregroundStyle(.white)
                    }
                    Divider().background(Color.white.opacity(0.3))
                    HStack {
                        Text("Language:")
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(selectedLanguage.uppercased())
                            .foregroundStyle(.white)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    HStack {
                        Text("Exam:")
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(selectedExam.uppercased())
                            .foregroundStyle(.white)
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
