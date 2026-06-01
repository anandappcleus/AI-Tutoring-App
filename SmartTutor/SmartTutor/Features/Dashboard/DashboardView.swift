//
//  DashboardView.swift
//  SmartTutor
//
//  Home tab — profile header, AI search bar, Today's Focus, and learning module grid.
//  Sprint 7+: camera & voice input, Mock Tests, Syllabus Map, Formula Sheets, Start AI Lesson.
//

import os
import SwiftUI


struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var vm          = DashboardViewModel()
    @State private var progressVM   = ProgressViewModel()

    // Tab navigation bridge
    @AppStorage("selectedMainTab")   private var selectedMainTab   = 0
    @AppStorage("pendingStudyTopic") private var pendingStudyTopic = ""

    // Search bar state
    @State private var askText = ""

    // Sheet / navigation flags
    @State private var showOfflinePacks    = false
    @State private var showParentDashboard = false
    @State private var showMockTests       = false
    @State private var showSyllabusMap     = false
    @State private var showFormulaSheets   = false
    @State private var showVoiceInput      = false
    @State private var showCameraPicker    = false
    @State private var pickedImageItem: IdentifiableImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    DashboardHeaderSection(
                        askText: $askText,
                        studentName: appState.currentProfile?.name ?? "Student",
                        language: appState.currentProfile?.preferredLanguage ?? .english,
                        examTarget: appState.currentProfile?.examTarget,
                        dayStreak: progressVM.progressData?.dayStreak ?? 0,
                        onSubmit: {
                            let q = askText.trimmingCharacters(in: .whitespaces)
                            guard !q.isEmpty else { return }
                            AppLogger.userAction(AppLogger.dashboard,
                                                 action: "search-submit", context: q)
                            pendingStudyTopic = q
                            askText = ""
                            selectedMainTab = 1
                            AppLogger.navigated(to: "StudyView", from: "DashboardSearchBar")
                        },
                        onCameraTap: {
                            AppLogger.userAction(AppLogger.camera, action: "camera-tap")
                            showCameraPicker = true
                        },
                        onMicTap: {
                            AppLogger.userAction(AppLogger.voice, action: "mic-tap-from-search-bar")
                            showVoiceInput = true
                        }
                    )

                    VStack(spacing: 28) {
                        if vm.isShowingCachedPlan {
                            Label("Showing cached plan — will refresh when online", systemImage: "wifi.slash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color(UIColor.secondarySystemBackground))
                                .clipShape(Capsule())
                                .padding(.horizontal, 16)
                        }
                        if let progress = progressVM.progressData {
                            QuickStatsStrip(
                                dayStreak:         progress.dayStreak,
                                questionsThisWeek: progress.totalQuestions,
                                accuracyPct:       progress.overallAccuracyPct
                            )
                        }
                        TodaysFocusSection(
                            studyPlan: vm.studyPlan,
                            isLoading: vm.isLoading,
                            onPlannerTap: { selectedMainTab = 1 },
                            onStartLesson: { topic in
                                AppLogger.userAction(AppLogger.dashboard,
                                                     action: "start-ai-lesson",
                                                     context: topic)
                                // If the plan contains a generic placeholder name (e.g. "Weak Topic 1")
                                // the backend doesn't know what it means either. Ask the AI to teach
                                // the student's most important weak topic instead — the backend injects
                                // the real weak-topic list from quiz history into the system prompt.
                                let isPlaceholder = topic.range(
                                    of: #"^[Ww]eak\s+[Tt]opic\s*\d+$"#,
                                    options: .regularExpression
                                ) != nil
                                let prompt = isPlaceholder
                                    ? "Explain the key concepts in my most important weak topic with a worked example and give me 2 JEE/NEET practice problems"
                                    : "Explain the key concepts in \(topic) with a worked example and give me 2 JEE/NEET practice problems"
                                pendingStudyTopic = prompt
                                selectedMainTab = 1
                                AppLogger.navigated(to: "StudyView[topic=\(topic)]",
                                                    from: "TodaysFocus")
                            }
                        )
                        #if DEBUG
                        if vm.studyPlan == nil && !vm.isLoading {
                            VStack(spacing: 6) {
                                Button {
                                    if let id = appState.currentProfile?.id {
                                        Task { await vm.triggerNightlyCrew(studentId: id) }
                                    }
                                } label: {
                                    Label(
                                        vm.isGeneratingPlan ? "Triggering crew…" : "⚡ Trigger Nightly Crew [DEV]",
                                        systemImage: vm.isGeneratingPlan ? "hourglass" : "bolt.fill"
                                    )
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .background(vm.isGeneratingPlan ? Color.gray : Color.orange)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(vm.isGeneratingPlan)

                                if vm.isGeneratingPlan {
                                    Text("Crew running in background — pull to refresh in ~60s")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        #endif
                        LearningModulesSection(
                            showOfflinePacks:    $showOfflinePacks,
                            showParentDashboard: $showParentDashboard,
                            showMockTests:       $showMockTests,
                            showSyllabusMap:     $showSyllabusMap,
                            showFormulaSheets:   $showFormulaSheets,
                            examTarget: appState.currentProfile?.examTarget.rawValue,
                            onNavigateToStudy: { selectedMainTab = 1 }
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                }
            }
            .refreshable {
                if let id = appState.currentProfile?.id {
                    await vm.forceRefresh(studentId: id)
                    await progressVM.load(studentId: id)
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
            .ignoresSafeArea(edges: .top)
            // ── Navigation destinations ──
            .navigationDestination(isPresented: $showOfflinePacks) {
                OfflinePacksView()
            }
            .navigationDestination(isPresented: $showParentDashboard) {
                ParentDashboardView()
            }
            .navigationDestination(isPresented: $showMockTests) {
                MockTestsView()
            }
            .navigationDestination(isPresented: $showSyllabusMap) {
                SyllabusMapView()
            }
            .navigationDestination(isPresented: $showFormulaSheets) {
                FormulaSheetView()
            }
        }
        // ── Camera picker sheet ──
        .sheet(isPresented: $showCameraPicker) {
            ImagePickerView { image in
                AppLogger.camera.info("DashboardView: onImage called  size=\(image.size.width)×\(image.size.height)")
                // Wait for picker dismiss animation, then set the item.
                // Use sheet(item:) so SwiftUI passes the image directly — no stale-closure nil race.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    AppLogger.camera.info("DashboardView: setting pickedImageItem")
                    pickedImageItem = IdentifiableImage(image: image)
                }
            }
        }
        // ── Picked image preview sheet — item-based, image is always non-nil ──
        .sheet(item: $pickedImageItem) { item in
            let _ = AppLogger.camera.info("DashboardView: PickedImageQuerySheet rendering  size=\(item.image.size.width)×\(item.image.size.height)")
            PickedImageQuerySheet(image: item.image) { query in
                AppLogger.userAction(AppLogger.camera,
                                     action: "image-query-submitted", context: query)
                pendingStudyTopic = query
                pickedImageItem = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    selectedMainTab = 1
                    AppLogger.navigated(to: "StudyView[image-query]", from: "Dashboard")
                }
            }
        }
        // ── Voice input sheet (from search bar mic) ──
        .sheet(isPresented: $showVoiceInput) {
            let langCode = (appState.currentProfile?.preferredLanguage.rawValue ?? "en") + "-IN"
            VoiceInputView(languageCode: langCode) { transcript in
                AppLogger.voice.info("DashboardView: voice transcript received  preview=\(transcript.prefix(60))")
                askText = transcript
                showVoiceInput = false
            }
        }
        .task {
            if let id = appState.currentProfile?.id {
                AppLogger.dashboard.info("DashboardView.task: loading plan  studentId=\(id)")
                await vm.loadPlan(studentId: id)
                await progressVM.load(studentId: id)
            }
        }
    }
}

// MARK: - Identifiable Image (for sheet(item:) presentation)

/// Wraps UIImage with an Identifiable conformance so it can drive `.sheet(item:)`.
private struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - Picked Image Query Sheet

private struct PickedImageQuerySheet: View {
    let image: UIImage
    let onSubmit: (String) -> Void
    @State private var questionText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = AppLogger.camera.info("PickedImageQuerySheet: body evaluated  size=\(image.size.width)×\(image.size.height)")
        return NavigationStack {
            VStack(spacing: 20) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(radius: 4)

                Text("What would you like to know about this?")
                    .font(.system(size: 15, weight: .semibold))

                TextField("e.g. Solve this problem step by step", text: $questionText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3, reservesSpace: true)

                Button {
                    // Compress image to ~200KB JPEG, base64-encode, store for API call.
                    // UIImage stored separately so StudyView can render the thumbnail.
                    PendingImageStore.shared.image = image
                    PendingImageStore.shared.imageBase64 = compressToBase64(image: image)
                    let q = questionText.trimmingCharacters(in: .whitespaces)
                    let userQuestion = q.isEmpty ? "Explain and solve this question" : q
                    AppLogger.camera.info("PickedImageQuerySheet: submitting with image")
                    onSubmit(userQuestion)
                } label: {
                    Label("Ask AI Tutor", systemImage: "brain.head.profile")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.indigo)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .navigationTitle("Question from Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Image Compression

    /// Scale image down to max 800 px on the longest side and encode as JPEG at 70% quality.
    /// Typical output is 50–150 KB — well within the 4 MB backend limit.
    private func compressToBase64(image: UIImage) -> String? {
        let maxDimension: CGFloat = 800
        let scale = min(maxDimension / max(image.size.width, image.size.height), 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        guard let jpegData = resized.jpegData(compressionQuality: 0.7) else { return nil }
        return jpegData.base64EncodedString()
    }
}

// MARK: - Quick Stats Strip

private struct QuickStatsStrip: View {
    let dayStreak:         Int
    let questionsThisWeek: Int
    let accuracyPct:       Double

    var body: some View {
        HStack(spacing: 10) {
            StatPill(
                icon: "flame.fill",
                value: "\(dayStreak)",
                label: "Day Streak",
                iconColor: .orange,
                bgColor: .orange.opacity(0.09)
            )
            StatPill(
                icon: "checkmark.circle.fill",
                value: "\(questionsThisWeek)",
                label: "This Week",
                iconColor: Color(red: 0.12, green: 0.65, blue: 0.40),
                bgColor: Color(red: 0.12, green: 0.65, blue: 0.40).opacity(0.09)
            )
            StatPill(
                icon: "target",
                value: "\(Int(accuracyPct))%",
                label: "Accuracy",
                iconColor: .indigo,
                bgColor: .indigo.opacity(0.09)
            )
        }
    }
}

private struct StatPill: View {
    let icon:      String
    let value:     String
    let label:     String
    let iconColor: Color
    let bgColor:   Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
            Text(value)
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(Color(UIColor.label))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(bgColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(iconColor.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Header

private struct DashboardHeaderSection: View {
    @Binding var askText: String
    let studentName: String
    let language:    StudentProfile.Language
    let examTarget:  StudentProfile.ExamTarget?
    let dayStreak:   Int
    let onSubmit:    () -> Void
    let onCameraTap: () -> Void
    let onMicTap:    () -> Void

    private var askPlaceholder: String {
        switch language {
        case .english: return "Ask a doubt in English..."
        case .hindi:   return "हिंदी में प्रश्न पूछें..."
        case .bengali: return "বাংলায় প্রশ্ন করুন..."
        case .tamil:   return "தமிழில் கேள்வி கேளுங்கள்..."
        case .telugu:  return "తెలుగులో సందేహం అడగండి..."
        case .marathi: return "मराठीत प्रश्न विचारा..."
        }
    }

    private func daysToExam(_ target: StudentProfile.ExamTarget) -> Int {
        var comps        = DateComponents()
        comps.hour       = 0; comps.minute = 0; comps.second = 0
        switch target {
        case .jee:    comps.month = 4;  comps.day = 5
        case .neet:   comps.month = 5;  comps.day = 5
        case .wbchse: comps.month = 3;  comps.day = 10
        }
        let cal  = Calendar.current
        let now  = Date()
        comps.year = cal.component(.year, from: now)
        guard var examDate = cal.date(from: comps) else { return 0 }
        if examDate <= now {
            comps.year = (comps.year ?? 2026) + 1
            examDate   = cal.date(from: comps) ?? examDate
        }
        return max(0, cal.dateComponents([.day], from: now, to: examDate).day ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.indigo, .purple, Color(red: 0.88, green: 0.22, blue: 0.88)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    Text(String(studentName.prefix(1).uppercased()))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 3)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Welcome back,")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("\(studentName) 👋")
                        .font(.system(size: 22, weight: .bold))
                    // Exam countdown pill
                    if let exam = examTarget {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 10, weight: .semibold))
                            Text("\(exam.rawValue) · \(daysToExam(exam)) days to go")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.indigo)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.indigo.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }

                Spacer()

                // Streak badge — only shown once at least 1 day is active
                if dayStreak > 0 {
                    VStack(spacing: 2) {
                        Text("🔥")
                            .font(.system(size: 22))
                        Text("\(dayStreak)")
                            .font(.system(size: 17, weight: .black))
                            .foregroundStyle(Color(red: 0.93, green: 0.42, blue: 0.08))
                        Text("streak")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
            .padding(.bottom, 20)

            // Ask / search bar
            HStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.system(size: 20))
                    .foregroundStyle(.indigo)

                TextField(askPlaceholder, text: $askText)
                    .font(.system(size: 15, weight: .medium))
                    .onSubmit { onSubmit() }

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    Button {
                        onCameraTap()
                    } label: {
                        Image(systemName: "camera")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Camera — photograph a question")

                    Rectangle()
                        .fill(Color.gray.opacity(0.25))
                        .frame(width: 1, height: 24)

                    Button {
                        onMicTap()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.indigo)
                                .frame(width: 40, height: 40)
                                .shadow(color: .indigo.opacity(0.35), radius: 6, y: 3)
                            Image(systemName: "mic.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                        }
                    }
                    .accessibilityLabel("Voice input — speak your question")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.gray.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color(UIColor.systemBackground))
        .clipShape(
            .rect(
                topLeadingRadius: 0,
                bottomLeadingRadius: 32,
                bottomTrailingRadius: 32,
                topTrailingRadius: 0
            )
        )
        .shadow(color: .black.opacity(0.03), radius: 10, y: 2)
    }
}

// MARK: - Today's Focus

private struct TodaysFocusSection: View {
    let studyPlan: StudyPlanResponse?
    let isLoading: Bool
    let onPlannerTap: () -> Void
    let onStartLesson: (String) -> Void
    @State private var selectedCard = 0

    // One gradient pair per slot (loops if > 4 topics)
    private let cardColors: [(start: Color, end: Color)] = [
        (Color(red: 0.36, green: 0.41, blue: 0.96), Color(red: 0.55, green: 0.26, blue: 0.84)), // indigo → violet
        (Color(red: 0.04, green: 0.62, blue: 0.58), Color(red: 0.09, green: 0.78, blue: 0.52)), // teal → emerald
        (Color(red: 0.95, green: 0.47, blue: 0.09), Color(red: 0.99, green: 0.73, blue: 0.04)), // amber → gold
        (Color(red: 0.84, green: 0.18, blue: 0.34), Color(red: 0.96, green: 0.44, blue: 0.24)), // crimson → coral
    ]

    private func subject(for topic: String) -> (label: String, icon: String) {
        let t = topic.lowercased()
        let mathWords = ["vector", "algebra", "matrices", "matrix", "calculus", "integration",
                         "differentiation", "trigonometry", "probability", "statistics",
                         "coordinate", "function", "sequence", "series", "progression",
                         "binomial", "complex", "determinant", "inverse"]
        let chemWords = ["bonding", "organic", "inorganic", "reaction", "mole", "equilibrium",
                         "kinetics", "electrochemistry", "polymer", "solution", "acid",
                         "base", "redox", "hydrocarbon", "aldehyde", "ketone", "amine",
                         "periodic", "element", "compound", "chemistry"]
        if mathWords.contains(where: { t.contains($0) }) { return ("Mathematics", "function") }
        if chemWords.contains(where: { t.contains($0) }) { return ("Chemistry", "flask.fill") }
        return ("Physics", "atom")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ── Section header ─────────────────────────────────────────
            HStack(alignment: .bottom) {
                Text("Today's Focus")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button(action: onPlannerTap) {
                    Label("AI Planner", systemImage: "cpu")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.indigo)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.indigo.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            if isLoading {
                // ── Loading state ─────────────────────────────────────
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(UIColor.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 12, y: 2)
                    .frame(height: 200)
                    .overlay {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading today\'s plan...")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }

            } else if let plan = studyPlan, !plan.topics.isEmpty {
                // ── Gradient topic cards ───────────────────────────────
                VStack(spacing: 10) {
                    TabView(selection: $selectedCard) {
                        ForEach(Array(plan.topics.enumerated()), id: \.element.topic) { idx, slot in
                            let colors = cardColors[idx % cardColors.count]
                            let sub = subject(for: slot.topic)
                            Button { onStartLesson(slot.topic) } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    // Large watermark digit
                                    Text("\(idx + 1)")
                                        .font(.system(size: 130, weight: .black))
                                        .foregroundStyle(.white.opacity(0.07))
                                        .offset(x: 10, y: 28)

                                    VStack(alignment: .leading, spacing: 0) {
                                        // Top row: subject badge + duration
                                        HStack {
                                            Label(sub.label, systemImage: sub.icon)
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(.white.opacity(0.92))
                                                .padding(.horizontal, 9)
                                                .padding(.vertical, 5)
                                                .background(.white.opacity(0.18))
                                                .clipShape(Capsule())
                                            Spacer()
                                            HStack(spacing: 4) {
                                                Image(systemName: "clock")
                                                    .font(.system(size: 10))
                                                Text("~\(slot.durationMin) min")
                                                    .font(.system(size: 11, weight: .medium))
                                            }
                                            .foregroundStyle(.white.opacity(0.8))
                                        }
                                        .padding(.bottom, 18)

                                        // Topic name
                                        Text(slot.topic)
                                            .font(.system(size: 22, weight: .bold))
                                            .foregroundStyle(.white)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)

                                        Spacer(minLength: 16)

                                        // CTA — white pill, text in card's start color
                                        HStack(spacing: 7) {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 12, weight: .bold))
                                            Text("Start AI Lesson")
                                                .font(.system(size: 14, weight: .bold))
                                        }
                                        .foregroundStyle(colors.start)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 46)
                                        .background(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                    }
                                    .padding(20)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 220)
                                .background(
                                    LinearGradient(
                                        colors: [colors.start, colors.end],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 24))
                                .shadow(color: colors.start.opacity(0.35), radius: 14, y: 6)
                                .padding(.horizontal, 4)
                                .padding(.bottom, 6)
                            }
                            .buttonStyle(.plain)
                            .tag(idx)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 248)

                    // ── Custom animated pill indicators ────────────────
                    if plan.topics.count > 1 {
                        HStack(spacing: 6) {
                            ForEach(0..<plan.topics.count, id: \.self) { i in
                                Capsule()
                                    .fill(i == selectedCard
                                          ? cardColors[i % cardColors.count].start
                                          : Color(UIColor.systemFill))
                                    .frame(width: i == selectedCard ? 22 : 7, height: 7)
                                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: selectedCard)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

            } else {
                // ── Empty / pre-plan state ─────────────────────────────
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(UIColor.systemBackground))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 2)
                    .frame(minHeight: 160)
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "moon.stars.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.indigo.opacity(0.6))
                            Text("Plan generates tonight")
                                .font(.system(size: 16, weight: .semibold))
                            Text("The AI tutor creates your personalised plan nightly at 2 AM IST.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        .padding(32)
                    }
            }
        }
    }
}

// MARK: - Learning Modules

private struct LearningModulesSection: View {
    @Binding var showOfflinePacks:    Bool
    @Binding var showParentDashboard: Bool
    @Binding var showMockTests:       Bool
    @Binding var showSyllabusMap:     Bool
    @Binding var showFormulaSheets:   Bool
    let examTarget: String?            // from StudentProfile — nil before profile loads
    let onNavigateToStudy: () -> Void

    struct ModuleItem: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        let iconColor: Color
        let bgColor: Color
    }

    /// All subtitles derived from the student's exam target — no hardcoded strings.
    private var modules: [ModuleItem] {
        let exam = examTarget ?? "JEE"
        let year = Calendar.current.component(.year, from: Date())

        return [
            ModuleItem(
                title: "Mock Tests",
                subtitle: "\(exam) \(year) Papers",
                icon: "checkmark.circle.fill",
                iconColor: .blue,
                bgColor: .blue.opacity(0.1)
            ),
            ModuleItem(
                title: "Syllabus Map",
                subtitle: "\(exam) syllabus",
                icon: "chart.bar.fill",
                iconColor: .green,
                bgColor: .green.opacity(0.1)
            ),
            ModuleItem(
                title: "Offline Packs",
                subtitle: "Study without data",
                icon: "arrow.down.circle.fill",
                iconColor: .orange,
                bgColor: .orange.opacity(0.1)
            ),
            ModuleItem(
                title: "Formula Sheets",
                subtitle: "\(exam) quick revision",
                icon: "book.fill",
                iconColor: .purple,
                bgColor: .purple.opacity(0.1)
            ),
            ModuleItem(
                title: "Parent Dashboard",
                subtitle: "Monitor progress",
                icon: "person.2.fill",
                iconColor: .blue,
                bgColor: .blue.opacity(0.1)
            ),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Learning Modules")
                .font(.system(size: 18, weight: .bold))

            // ── Featured: Mock Tests — full-width dark card ────────────────
            let featuredExam = examTarget ?? "JEE"
            Button { showMockTests = true } label: {
                ZStack {
                    // Background gradient
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.10, green: 0.08, blue: 0.38),
                                         Color(red: 0.28, green: 0.10, blue: 0.56)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    // Subtle dot-grid watermark
                    Canvas { context, size in
                        let sp: CGFloat = 18
                        for x in stride(from: 0, through: size.width, by: sp) {
                            for y in stride(from: 0, through: size.height, by: sp) {
                                context.fill(
                                    Path(ellipseIn: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)),
                                    with: .color(.white.opacity(0.07))
                                )
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    // Content
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Label("Mock Tests", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("\(featuredExam) · Full papers · Timed · Detailed solutions")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .padding(.bottom, 18)

                        HStack(spacing: 6) {
                            Image(systemName: "play.fill").font(.system(size: 12, weight: .bold))
                            Text("Start Practice")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(Color(red: 0.28, green: 0.10, blue: 0.56))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(18)
                }
                .frame(height: 148)
            }
            .buttonStyle(.plain)
            .shadow(
                color: Color(red: 0.28, green: 0.10, blue: 0.56).opacity(0.30),
                radius: 14, y: 6
            )

            // ── 2 × 2 grid for remaining modules ──────────────────────────
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(modules.filter { $0.title != "Mock Tests" }) { mod in
                    ModuleCard(item: mod) {
                        AppLogger.userAction(AppLogger.dashboard,
                                             action: "module-tap", context: mod.title)
                        switch mod.title {
                        case "Syllabus Map":     showSyllabusMap     = true
                            AppLogger.navigated(to: "SyllabusMapView",    from: "Dashboard")
                        case "Offline Packs":    showOfflinePacks    = true
                            AppLogger.navigated(to: "OfflinePacksView",   from: "Dashboard")
                        case "Formula Sheets":   showFormulaSheets   = true
                            AppLogger.navigated(to: "FormulaSheetView",   from: "Dashboard")
                        case "Parent Dashboard": showParentDashboard = true
                            AppLogger.navigated(to: "ParentDashboardView", from: "Dashboard")
                        default:
                            AppLogger.dashboard.warning("module-tap: unhandled module '\(mod.title)'")
                        }
                    }
                }
            }
        }
    }
}

private struct ModuleCard: View {
    let item: LearningModulesSection.ModuleItem
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(item.bgColor)
                        .frame(width: 44, height: 44)
                    Image(systemName: item.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(item.iconColor)
                }
                .padding(.bottom, 14)

                Text(item.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)

                Text(item.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.04), radius: 10, y: 2)
            .scaleEffect(pressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.spring(response: 0.2)) { pressed = true } }
                .onEnded   { _ in withAnimation(.spring(response: 0.3)) { pressed = false } }
        )
    }
}

// MARK: - Tag Badge (shared)

struct TagBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
