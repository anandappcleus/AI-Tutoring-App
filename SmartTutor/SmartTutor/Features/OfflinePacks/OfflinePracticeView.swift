//
//  OfflinePracticeView.swift
//  SmartTutor
//
//  Sprint 8 — Offline flashcard practice session.
//
//  Displayed as a sheet when the user taps "Practice Now" on a downloaded pack.
//  Loads OfflineQuestionEntity records from Core Data for the pack and steps
//  through them one-by-one with a flip animation to reveal the answer.
//

import SwiftUI

struct OfflinePracticeView: View {
    let pack: PackListItem

    @Environment(\.dismiss) private var dismiss
    @State private var questions: [OfflineQuestionEntity] = []
    @State private var currentIndex = 0
    @State private var showAnswer   = false
    @State private var isComplete   = false

    private var current: OfflineQuestionEntity? {
        guard !questions.isEmpty, questions.indices.contains(currentIndex) else { return nil }
        return questions[currentIndex]
    }

    private var progress: Double {
        guard !questions.isEmpty else { return 0 }
        return Double(currentIndex + 1) / Double(questions.count)
    }

    var body: some View {
        NavigationStack {
            Group {
                if questions.isEmpty {
                    ProgressView("Loading questions…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isComplete {
                    completionView
                } else {
                    flashcardView
                }
            }
            .navigationTitle(pack.topic)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            questions = CoreDataStack.shared.viewContext.fetchQuestions(for: pack.id)
        }
    }

    // MARK: - Flashcard

    private var flashcardView: some View {
        VStack(spacing: 24) {
            // Progress header
            VStack(spacing: 8) {
                HStack {
                    Text("Question \(currentIndex + 1) of \(questions.count)")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(pack.subject)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(pack.subjectColor)
                        .clipShape(Capsule())
                }
                ProgressView(value: progress)
                    .tint(.indigo)
            }
            .padding(.horizontal, 20)

            // Flip card
            ZStack {
                questionCard
                    .opacity(showAnswer ? 0 : 1)
                    .rotation3DEffect(.degrees(showAnswer ? -90 : 0), axis: (1, 0, 0))
                answerCard
                    .opacity(showAnswer ? 1 : 0)
                    .rotation3DEffect(.degrees(showAnswer ? 0 : 90), axis: (1, 0, 0))
            }
            .animation(.easeInOut(duration: 0.25), value: showAnswer)

            // Action buttons
            VStack(spacing: 12) {
                if !showAnswer {
                    Button("Reveal Answer") { showAnswer = true }
                        .buttonStyle(PracticeButtonStyle(style: .primary))
                } else {
                    HStack(spacing: 12) {
                        if currentIndex > 0 {
                            Button("← Prev") {
                                showAnswer = false
                                currentIndex -= 1
                            }
                            .buttonStyle(PracticeButtonStyle(style: .secondary))
                        }

                        if currentIndex < questions.count - 1 {
                            Button("Next →") {
                                showAnswer = false
                                currentIndex += 1
                            }
                            .buttonStyle(PracticeButtonStyle(style: .primary))
                        } else {
                            Button("Finish 🎉") { isComplete = true }
                                .buttonStyle(PracticeButtonStyle(style: .primary))
                        }
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding(.top, 20)
    }

    private var questionCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(.indigo)
            Text(current?.questionText ?? "")
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 180)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .padding(.horizontal, 20)
    }

    private var answerCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(.green)
            Text(current?.answerText ?? "")
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 180)
        .background(Color.green.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .padding(.horizontal, 20)
    }

    // MARK: - Completion

    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "star.fill")
                .font(.system(size: 64))
                .foregroundColor(.yellow)

            VStack(spacing: 8) {
                Text("Pack Complete!")
                    .font(.system(size: 26, weight: .bold))
                Text("You reviewed all \(questions.count) questions in \(pack.topic).")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                Button("Practice Again") {
                    currentIndex = 0
                    showAnswer   = false
                    isComplete   = false
                }
                .buttonStyle(PracticeButtonStyle(style: .primary))
                .padding(.horizontal, 40)

                Button("Done") { dismiss() }
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Button Style

private enum PracticeButtonKind { case primary, secondary }

private struct PracticeButtonStyle: ButtonStyle {
    let style: PracticeButtonKind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(style == .primary ? .white : .indigo)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                style == .primary
                    ? AnyShapeStyle(Color.indigo.opacity(configuration.isPressed ? 0.8 : 1))
                    : AnyShapeStyle(Color.indigo.opacity(configuration.isPressed ? 0.15 : 0.08))
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
