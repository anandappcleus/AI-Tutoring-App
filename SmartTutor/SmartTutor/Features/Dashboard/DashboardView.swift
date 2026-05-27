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
    @State private var vm = DashboardViewModel()

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
            ZStack {
                // Full-screen gradient — NowAssist design system
                LinearGradient(
                    gradient: Gradient(colors: AppColors.gradientColors),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                VStack(spacing: 0) {
                    DashboardHeaderSection(
                        askText: $askText,
                        studentName: appState.currentProfile?.name ?? "Student",
                        language: appState.currentProfile?.preferredLanguage ?? .english,
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
                                .foregroundStyle(AppColors.textSecondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(AppColors.cardBackground)
                                .clipShape(Capsule())
                                .padding(.horizontal, 16)
                        }
                        TodaysFocusSection(
                            studyPlan: vm.studyPlan,
                            isLoading: vm.isLoading,
                            onPlannerTap: { selectedMainTab = 1 },
                            onStartLesson: { topic in
                                AppLogger.userAction(AppLogger.dashboard,
                                                     action: "start-ai-lesson",
                                                     context: topic)
                                pendingStudyTopic = "Explain the key concepts in \(topic) with a worked example and give me 2 JEE/NEET practice problems"
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
                }
            }
            .scrollContentBackground(.hidden)
            .ignoresSafeArea(edges: .top)
            } // ZStack
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
                        .background(AppColors.accent)
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

// MARK: - Header

private struct DashboardHeaderSection: View {
    @Binding var askText: String
    let studentName: String
    let language: StudentProfile.Language
    let onSubmit: () -> Void
    let onCameraTap: () -> Void
    let onMicTap: () -> Void

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

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: AppColors.gradientColors),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    Text(String(studentName.prefix(1).uppercased()))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome back,")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    Text("\(studentName) 👋")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
            .padding(.bottom, 20)

            // Ask / search bar
            HStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.system(size: 20))
                    .foregroundStyle(AppColors.textSecondary)

                TextField(askPlaceholder, text: $askText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                    .tint(AppColors.textPrimary)
                    .onSubmit { onSubmit() }

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    Button {
                        onCameraTap()
                    } label: {
                        Image(systemName: "camera")
                            .font(.system(size: 20))
                            .foregroundStyle(AppColors.textSecondary)
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
                                .fill(AppColors.accent)
                                .frame(width: 40, height: 40)
                                .shadow(color: AppColors.accent.opacity(0.35), radius: 6, y: 3)
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
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(.clear)
    }
}

// MARK: - Today's Focus

private struct TodaysFocusSection: View {
    let studyPlan: StudyPlanResponse?
    let isLoading: Bool
    let onPlannerTap: () -> Void
    let onStartLesson: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                Text("Today's Focus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Button(action: onPlannerTap) {
                    Label("AI Planner", systemImage: "cpu")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppColors.cardBackgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 28)
                    .fill(AppColors.cardBackground)

                // Decorative gradient blob
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.06), .white.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)
                    .offset(x: 20, y: -20)
                    .clipped()

                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading today\'s plan...")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                } else if let plan = studyPlan, let firstTopic = plan.topics.first {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            TagBadge(text: firstTopic.topic, color: AppColors.accent)
                            TagBadge(text: "AI Plan", color: .white.opacity(0.6))
                        }
                        .padding(.bottom, 14)

                        Text(firstTopic.topic)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(.bottom, 8)

                        let totalMin = plan.topics.reduce(0) { $0 + $1.durationMin }
                        Text("~\(firstTopic.durationMin) min for this topic · \(plan.topics.count) topic\(plan.topics.count == 1 ? "" : "s") · ~\(totalMin) min total today")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.textSecondary)
                            .lineSpacing(3)
                            .padding(.bottom, 20)

                        Button {
                            if let topic = studyPlan?.topics.first?.topic {
                                onStartLesson(topic)
                            } else {
                                onPlannerTap()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 15))
                                Text("Start AI Lesson")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(AppColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding(20)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(AppColors.textSecondary)
                        Text("Plan generates tonight")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("The AI tutor creates your personalised plan nightly at 2 AM IST.")
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Learning Modules")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(modules) { mod in
                    ModuleCard(item: mod) {
                        AppLogger.userAction(AppLogger.dashboard,
                                             action: "module-tap", context: mod.title)
                        switch mod.title {
                        case "Mock Tests":     showMockTests     = true
                            AppLogger.navigated(to: "MockTestsView",    from: "Dashboard")
                        case "Syllabus Map":   showSyllabusMap   = true
                            AppLogger.navigated(to: "SyllabusMapView",  from: "Dashboard")
                        case "Offline Packs":  showOfflinePacks  = true
                            AppLogger.navigated(to: "OfflinePacksView", from: "Dashboard")
                        case "Formula Sheets": showFormulaSheets = true
                            AppLogger.navigated(to: "FormulaSheetView", from: "Dashboard")
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
                    .foregroundStyle(AppColors.textPrimary)

                Text(item.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24))
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
