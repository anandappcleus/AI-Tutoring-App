//
//  StudyView.swift
//  SmartTutor
//
//  Converted from StudyScreen.tsx
//  AI tutor chat: message bubbles, voice input, paywall gate.
//

import os
import SwiftUI

struct StudyView: View {
    @Environment(AppState.self)       private var appState
    @Environment(StudyViewModel.self) private var vm
    @State private var inputText = ""
    @State private var isRecording = false
    @State private var showPaywall = false
    @State private var showVoiceInput = false

    /// Bridge from Dashboard / Syllabus / Formula "Ask AI" CTAs.
    /// Set by the caller before switching to the Study tab; consumed once on appear.
    @AppStorage("pendingStudyTopic") private var pendingStudyTopic = ""

    private let subjects = ["Physics", "Chemistry", "Maths", "Biology"]

    // Derived from ViewModel state
    private var isLoading: Bool { vm.viewState == .loading }
    private var isPremium: Bool { appState.currentProfile?.isPremium ?? false }
    private var questionsToday: Int { vm.questionsUsedToday }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Premium warning banner — only when running low
                if !isPremium && questionsToday >= 5 {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13))
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Running low on questions!")
                                .font(.system(size: 13, weight: .semibold))
                            Button {
                                AppLogger.userAction(AppLogger.study, action: "upgrade-tapped",
                                                     context: "daily-limit-banner")
                                showPaywall = true
                            } label: {
                                Text("Upgrade to Premium")
                                    .font(.system(size: 12))
                                    .underline()
                            }
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.yellow.opacity(0.85))
                }

                // Map ViewModel messages → ChatMessage for the existing scroll view
                ChatScrollView(
                    messages: vm.messages.map {
                        ChatMessage(
                            type: $0.role == .user ? .question : .answer,
                            text: $0.text,
                            image: $0.image
                        )
                    },
                    isLoading: isLoading,
                    onSuggestion: { question in
                        inputText = ""
                        vm.ask(question: question)
                    }
                )

                // Inline error banner (non-fatal errors)
                if case .error(let code) = vm.viewState, code != "daily_limit_reached", code != "unauthorized" {
                    Text("Something went wrong. Tap to retry.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.85))
                        .onTapGesture { vm.dismissError() }
                }

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
            .navigationTitle("AI Tutor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(
                LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing),
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Image(systemName: "book.fill")
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showPaywall = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 11))
                            Text(isPremium ? "∞" : "\(10 - questionsToday) left")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(onSubscribe: { showPaywall = false })
            }
            .sheet(isPresented: $showVoiceInput, onDismiss: { isRecording = false }) {
                let langCode = (appState.currentProfile?.preferredLanguage.rawValue ?? "bn") + "-IN"
                VoiceInputView(languageCode: langCode) { transcription in
                    inputText = transcription
                }
            }
            .onChange(of: vm.viewState) { _, state in
                if case .error(let code) = state {
                    if code == "daily_limit_reached" { showPaywall = true }
                    // "unauthorized" handled at ContentView level via AppState
                }
            }
            .onAppear {
                // Consume any topic pre-filled by Dashboard → Start AI Lesson, Syllabus Map,
                // Formula Sheets, Mock Tests, or camera/voice search bar submissions.
                let topic = pendingStudyTopic.trimmingCharacters(in: .whitespaces)
                guard !topic.isEmpty else { return }
                pendingStudyTopic = ""
                AppLogger.study.info("StudyView.onAppear: consuming pendingStudyTopic  preview=\(topic.prefix(60))")
                // Small delay so the tab transition animation completes first.
                Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    vm.ask(question: topic)
                }
            }
        }
    }

    // MARK: - Actions

    private func handleAsk() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        AppLogger.userAction(AppLogger.study, action: "send-question",
                             context: String(trimmed.prefix(80)))
        inputText = ""
        vm.ask(question: trimmed)
    }

    private func handleVoiceInput() {
        AppLogger.userAction(AppLogger.voice, action: "voice-input-opened")
        isRecording = true
        showVoiceInput = true
    }
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable {
    let id = UUID()
    let type: MessageType
    let text: String
    let image: UIImage?

    enum MessageType { case question, answer }

    init(type: MessageType, text: String, image: UIImage? = nil) {
        self.type  = type
        self.text  = text
        self.image = image
    }
}

// MARK: - Header (unused — kept for reference; logic moved to NavigationStack toolbar)

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
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.2))
                .clipShape(Capsule())
            }
            .foregroundStyle(.white)

            if !isPremium && questionsToday >= 5 {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13))
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Running low on questions!")
                            .font(.system(size: 13, weight: .semibold))
                        Button {
                            AppLogger.userAction(AppLogger.study,
                                                 action: "upgrade-tapped",
                                                 context: "daily-limit-banner")
                            showPaywall = true
                        } label: {
                            Text("Upgrade to Premium")
                                .font(.system(size: 12))
                                .underline()
                        }
                    }
                }
                .foregroundStyle(.white)
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

// MARK: - Corner Shape Helper

private struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Tutor Avatar

private struct TutorAvatar: View {
    var isLoading: Bool = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            if isLoading {
                Circle()
                    .fill(Color.indigo.opacity(0.18))
                    .frame(width: 38, height: 38)
                    .scaleEffect(pulse ? 1.35 : 1.0)
                    .opacity(pulse ? 0 : 0.7)
                    .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false), value: pulse)
                    .onAppear { pulse = true }
            }
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.indigo, Color(red: 0.50, green: 0.18, blue: 0.90)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
            Image(systemName: "brain.head.profile")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 38, height: 38)
    }
}

// MARK: - Chat Scroll

private struct ChatScrollView: View {
    let messages: [ChatMessage]
    let isLoading: Bool
    let onSuggestion: (String) -> Void

    /// Only the welcome message exists — show starter suggestions.
    private var showEmptyState: Bool {
        messages.filter { $0.type == .question }.isEmpty
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { msg in
                        ChatBubble(message: msg)
                            .id(msg.id)
                    }
                    if showEmptyState && !isLoading {
                        EmptyStateView(onSelect: onSuggestion)
                            .padding(.top, 8)
                            .id("emptyState")
                    }
                    if isLoading {
                        TypingIndicatorView()
                            .id("loading")
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .onChange(of: messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: isLoading) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }
}

// MARK: - Empty / Welcome State

private struct EmptyStateView: View {
    let onSelect: (String) -> Void

    private let suggestions: [(subject: String, icon: String, color: Color, question: String)] = [
        ("Physics",   "atom",              .blue,   "Explain Newton's Laws with a worked example and 2 JEE practice problems"),
        ("Chemistry", "testtube.2",        .teal,   "What is the difference between ionic and covalent bonds?"),
        ("Maths",     "function",          .orange, "Walk me through integration by parts with an example"),
        ("Biology",   "leaf.fill",         .green,  "Explain the mechanism of DNA replication for NEET"),
    ]

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        LinearGradient(colors: [.indigo, .purple],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text("What would you like to learn today?")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Tap a suggestion or type your own question below")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            VStack(spacing: 10) {
                ForEach(suggestions, id: \.question) { s in
                    Button { onSelect(s.question) } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(s.color.opacity(0.12))
                                    .frame(width: 38, height: 38)
                                Image(systemName: s.icon)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(s.color)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.subject)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(s.color)
                                Text(s.question)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(Color(UIColor.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: ChatMessage
    var isQuestion: Bool { message.type == .question }

    var body: some View {
        if isQuestion {
            StudentBubble(message: message)
        } else {
            TutorAnswerCard(message: message)
        }
    }
}

// MARK: - Student Bubble (right-aligned, indigo gradient)

private struct StudentBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: 56)
            VStack(alignment: .trailing, spacing: 8) {
                if let img = message.image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                MathTextView(message.text, fontSize: 15)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                LinearGradient(
                    colors: [Color.indigo, Color(red: 0.50, green: 0.18, blue: 0.90)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(
                RoundedCornerShape(radius: 18, corners: [.topLeft, .topRight, .bottomLeft])
            )
        }
    }
}

// MARK: - Tutor Answer Card (left-aligned, white card)

private struct TutorAnswerCard: View {
    let message: ChatMessage

    private var isOffline: Bool    { message.text.hasPrefix("⏳") }
    private var accentColor: Color { isOffline ? .orange : .indigo }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            TutorAvatar()
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 5) {
                    Text("AI Tutor")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accentColor)
                    if isOffline {
                        Text("OFFLINE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 7)

                Rectangle()
                    .fill(accentColor.opacity(0.12))
                    .frame(height: 1)
                    .padding(.horizontal, 12)

                MathTextView(message.text, fontSize: 15)
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .background(
                isOffline
                    ? Color.orange.opacity(0.07)
                    : Color(UIColor.systemBackground)
            )
            .clipShape(
                RoundedCornerShape(radius: 18, corners: [.topLeft, .topRight, .bottomRight])
            )
            .overlay(
                RoundedCornerShape(radius: 18, corners: [.topLeft, .topRight, .bottomRight])
                    .stroke(accentColor.opacity(isOffline ? 0.30 : 0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 5, y: 2)

            Spacer(minLength: 44)
        }
    }
}

// MARK: - Typing Indicator

private struct TypingIndicatorView: View {
    @State private var animating = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            TutorAvatar(isLoading: true)
                .padding(.top, 2)
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.indigo.opacity(0.45))
                        .frame(width: 7, height: 7)
                        .offset(y: animating ? -4 : 0)
                        .animation(
                            .easeInOut(duration: 0.45)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedCornerShape(radius: 18, corners: [.topLeft, .topRight, .bottomRight]))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
            Spacer(minLength: 44)
        }
        .onAppear { animating = true }
    }
}

// MARK: - Input Area

private struct SubjectChip: View {
    let name: String
    let icon: String
    let color: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(name)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.20), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct InputAreaView: View {
    @Binding var inputText: String
    @Binding var isRecording: Bool
    let isLoading: Bool
    let subjects: [String]
    let onAsk: () -> Void
    let onVoice: () -> Void

    private let subjectConfig: [(name: String, icon: String, color: Color)] = [
        ("Physics",   "atom",         .blue),
        ("Chemistry", "testtube.2",   .teal),
        ("Maths",     "function",     .orange),
        ("Biology",   "leaf.fill",    .green),
    ]

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !isLoading
    }

    var body: some View {
        VStack(spacing: 10) {
            // Color-coded subject chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(subjectConfig, id: \.name) { s in
                        SubjectChip(name: s.name, icon: s.icon, color: s.color) {
                            inputText = "Explain a key concept from \(s.name) for my exam"
                        }
                    }
                }
                .padding(.horizontal, 14)
            }

            // Text field + action buttons
            HStack(spacing: 10) {
                TextField("Ask in Bengali / English...", text: $inputText, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(Color.indigo.opacity(inputText.isEmpty ? 0.12 : 0.35), lineWidth: 1.5)
                    )

                // Mic button
                Button(action: onVoice) {
                    ZStack {
                        Circle()
                            .fill(isRecording ? Color.red.opacity(0.15) : Color(UIColor.secondarySystemBackground))
                            .frame(width: 42, height: 42)
                        Image(systemName: isRecording ? "mic.fill" : "mic")
                            .font(.system(size: 17))
                            .foregroundStyle(isRecording ? .red : .secondary)
                    }
                }
                .scaleEffect(isRecording ? 1.1 : 1.0)
                .animation(.spring(response: 0.3), value: isRecording)

                // Send button — pulsing indigo when active
                Button(action: onAsk) {
                    ZStack {
                        Circle()
                            .fill(canSend ? Color.indigo : Color.indigo.opacity(0.25))
                            .frame(width: 42, height: 42)
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .offset(x: 1)
                    }
                }
                .disabled(!canSend)
                .scaleEffect(canSend ? 1.0 : 0.92)
                .animation(.spring(response: 0.25), value: canSend)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .padding(.top, 10)
        .background(
            Color(UIColor.systemBackground)
                .shadow(color: .black.opacity(0.06), radius: 8, y: -3)
        )
    }
}
