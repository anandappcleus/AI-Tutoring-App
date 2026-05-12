//
//  StudyView.swift
//  SmartTutor
//
//  Converted from StudyScreen.tsx
//  AI tutor chat: message bubbles, voice input, paywall gate.
//

import SwiftUI

struct StudyView: View {
    var isPremium: Bool = false

    @State private var inputText = ""
    @State private var isRecording = false
    @State private var isLoading = false
    @State private var questionsToday = 3
    @State private var showPaywall = false
    @State private var messages: [ChatMessage] = [
        ChatMessage(
            type: .answer,
            text: "নমস্কার! আমি আপনার AI শিক্ষক। আপনার যেকোনো প্রশ্ন আমাকে জিজ্ঞাসা করুন। (Hello! I'm your AI tutor. Ask me any question.)"
        ),
    ]

    private let subjects = ["Physics", "Chemistry", "Maths", "Biology"]

    var body: some View {
        VStack(spacing: 0) {
            StudyHeaderView(
                isPremium: isPremium,
                questionsToday: questionsToday,
                showPaywall: $showPaywall
            )

            ChatScrollView(messages: messages, isLoading: isLoading)

            InputAreaView(
                inputText: $inputText,
                isRecording: $isRecording,
                isLoading: isLoading,
                subjects: subjects,
                onAsk: handleAsk,
                onVoice: handleVoiceInput
            )
        }
        .background(Color(UIColor.systemBackground))
        .sheet(isPresented: $showPaywall) {
            PaywallView(onSubscribe: { showPaywall = false })
        }
    }

    // MARK: - Actions

    private func handleAsk() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if !isPremium && questionsToday >= 10 {
            showPaywall = true
            return
        }

        isLoading = true
        messages.append(ChatMessage(type: .question, text: trimmed))
        inputText = ""

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            messages.append(ChatMessage(
                type: .answer,
                text: "Newton's Second Law states that Force = Mass × Acceleration (F = ma). এই সূত্র অনুসারে, যখন একটি বস্তুর উপর বল প্রয়োগ করা হয়, তখন বস্তুটি ত্বরণ লাভ করে যা বলের সমানুপাতিক এবং ভরের ব্যস্তানুপাতিক।\n\nExample: If a 5 kg object is pushed with 10 N force, acceleration = 10/5 = 2 m/s²"
            ))
            isLoading = false
            questionsToday += 1
        }
    }

    private func handleVoiceInput() {
        isRecording.toggle()
        if isRecording {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                inputText = "নিউটনের দ্বিতীয় সূত্র কি?"
                isRecording = false
            }
        }
    }
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable {
    let id = UUID()
    let type: MessageType
    let text: String

    enum MessageType { case question, answer }
}

// MARK: - Header

private struct StudyHeaderView: View {
    let isPremium: Bool
    let questionsToday: Int
    @Binding var showPaywall: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 20))
                    Text("AI Tutor")
                        .font(.system(size: 20, weight: .bold))
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11))
                    Text(isPremium ? "∞" : "\(10 - questionsToday) left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.2))
                .clipShape(Capsule())
            }
            .foregroundColor(.white)

            if !isPremium && questionsToday >= 5 {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13))
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Running low on questions!")
                            .font(.system(size: 13, weight: .semibold))
                        Button {
                            showPaywall = true
                        } label: {
                            Text("Upgrade to Premium")
                                .font(.system(size: 12))
                                .underline()
                        }
                    }
                }
                .foregroundColor(.white)
                .padding(12)
                .background(Color.yellow.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [Color.indigo, Color.purple],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}

// MARK: - Chat Scroll

private struct ChatScrollView: View {
    let messages: [ChatMessage]
    let isLoading: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(messages) { msg in
                        ChatBubble(message: msg)
                            .id(msg.id)
                    }
                    if isLoading {
                        TypingIndicatorView()
                            .id("loading")
                    }
                    Color.clear.frame(height: 4).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .onChange(of: messages.count) { _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: isLoading) { _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: ChatMessage

    var isQuestion: Bool { message.type == .question }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isQuestion { Spacer(minLength: 48) }

            VStack(alignment: .leading, spacing: 8) {
                if !isQuestion {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(Color.indigo.opacity(0.15))
                                .frame(width: 24, height: 24)
                            Text("AI")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.indigo)
                        }
                        Text("AI Tutor")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.indigo)
                    }
                }
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundColor(isQuestion ? .white : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .padding(16)
            .background(
                isQuestion
                ? AnyShapeStyle(Color.indigo)
                : AnyShapeStyle(Color(UIColor.secondarySystemBackground))
            )
            .clipShape(
                RoundedRectangle(cornerRadius: 20)
            )

            if !isQuestion { Spacer(minLength: 48) }
        }
    }
}

// MARK: - Typing Indicator

private struct TypingIndicatorView: View {
    @State private var dotIndex = 0

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle().fill(Color.indigo.opacity(0.15)).frame(width: 24, height: 24)
                        Text("AI").font(.system(size: 8, weight: .bold)).foregroundColor(.indigo)
                    }
                    Text("AI Tutor").font(.system(size: 12, weight: .semibold)).foregroundColor(.indigo)
                }
                HStack(spacing: 4) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: 8, height: 8)
                            .scaleEffect(dotIndex == i ? 1.4 : 1.0)
                            .animation(
                                .easeInOut(duration: 0.4).repeatForever(autoreverses: true).delay(Double(i) * 0.15),
                                value: dotIndex
                            )
                    }
                }
                .onAppear {
                    Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { _ in
                        dotIndex = (dotIndex + 1) % 3
                    }
                }
            }
            .padding(16)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            Spacer(minLength: 48)
        }
    }
}

// MARK: - Input Area

private struct InputAreaView: View {
    @Binding var inputText: String
    @Binding var isRecording: Bool
    let isLoading: Bool
    let subjects: [String]
    let onAsk: () -> Void
    let onVoice: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Subject quick-pick pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(subjects, id: \.self) { subject in
                        Button {
                            inputText = "Explain a concept from \(subject)"
                        } label: {
                            Text(subject)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color(UIColor.secondarySystemBackground))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Text field + action buttons
            HStack(spacing: 8) {
                TextField("Ask in Bengali / English...", text: $inputText, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1.5)
                    )

                Button(action: onVoice) {
                    ZStack {
                        Circle()
                            .fill(isRecording ? Color.red : Color(UIColor.secondarySystemBackground))
                            .frame(width: 44, height: 44)
                        Image(systemName: isRecording ? "mic.fill" : "mic")
                            .font(.system(size: 18))
                            .foregroundColor(isRecording ? .white : .primary)
                    }
                }
                .scaleEffect(isRecording ? 1.1 : 1.0)
                .animation(.spring(response: 0.3), value: isRecording)

                Button(action: onAsk) {
                    ZStack {
                        Circle()
                            .fill(
                                inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading
                                ? Color.indigo.opacity(0.35)
                                : Color.indigo
                            )
                            .frame(width: 44, height: 44)
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    }
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(Color(UIColor.systemBackground))
        .overlay(Divider(), alignment: .top)
    }
}
