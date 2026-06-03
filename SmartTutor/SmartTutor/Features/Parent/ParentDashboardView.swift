//
//  ParentDashboardView.swift
//  SmartTutor
//
//  Redesigned: weekly summary hero, activity bar chart, topic accuracy,
//  weak-topic alert cards, exam readiness, WhatsApp toggle.
//

import SwiftUI

// MARK: - Root View

struct ParentDashboardView: View {

    @Environment(AppState.self) private var appState
    @State private var vm = ParentDashboardViewModel()
    @State private var whatsappEnabled = true

    var body: some View {
        Group {
            if vm.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.4)
                    Text("Loading report…")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.errorMessage {
                ParentErrorState(message: error) {
                    if let id = appState.currentProfile?.id {
                        Task {
                            await vm.load(
                                studentId:   id,
                                examTarget:  appState.currentProfile?.examTarget.rawValue ?? "JEE",
                                studentName: appState.currentProfile?.name ?? "Student"
                            )
                        }
                    }
                }
            } else {
                dashboardContent
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("Parent Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(
            LinearGradient(colors: [Color(red: 0.25, green: 0.32, blue: 0.92), .purple],
                           startPoint: .leading, endPoint: .trailing),
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Parent Dashboard")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .task {
            AppLogger.navigated(to: "ParentDashboardView")
            if let id = appState.currentProfile?.id {
                await vm.load(
                    studentId:   id,
                    examTarget:  appState.currentProfile?.examTarget.rawValue ?? "JEE",
                    studentName: appState.currentProfile?.name ?? "Student"
                )
            }
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private var dashboardContent: some View {
        ScrollView {
            VStack(spacing: 20) {

                // ── Hero: weekly summary ──
                WeeklySummaryHero(
                    studyTime:         vm.studyTimeFormatted,
                    questions:         vm.questionsAttempted,
                    accuracy:          vm.avgAccuracy,
                    streak:            vm.dayStreak,
                    weekRange:         vm.weekRange
                )
                .padding(.horizontal, 16)

                // ── Activity bar chart ──
                if !vm.dailyActivity.isEmpty {
                    ParentSection(title: "Daily Activity", icon: "calendar.badge.clock") {
                        ActivityBarChart(days: vm.dailyActivity)
                    }
                    .padding(.horizontal, 16)
                }

                // ── Weak topic alerts ──
                if !vm.weakTopics.isEmpty {
                    ParentSection(title: "Needs Attention", icon: "exclamationmark.triangle.fill",
                                  iconColor: .orange) {
                        VStack(spacing: 10) {
                            ForEach(vm.weakTopics, id: \.self) { topic in
                                WeakTopicRow(topic: topic)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // ── Topic accuracy breakdown ──
                if !vm.topicBreakdown.isEmpty {
                    ParentSection(title: "Topic Accuracy", icon: "chart.bar.fill") {
                        VStack(spacing: 14) {
                            ForEach(vm.topicBreakdown, id: \.topic) { t in
                                TopicAccuracyRow(topic: t.topic, accuracy: t.accuracyPct)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // ── Exam readiness card ──
                ExamReadinessCard(
                    title:           vm.examReadinessTitle,
                    scoreText:       vm.predictedScoreText,
                    progress:        vm.predictedScoreProgress,
                    summary:         vm.readinessSummary,
                    subjectTags:     vm.subjectTags
                )
                .padding(.horizontal, 16)

                // ── WhatsApp toggle ──
                WhatsAppToggleRow(isEnabled: $whatsappEnabled)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
            }
            .padding(.top, 16)
        }
    }
}

// MARK: - Error State

private struct ParentErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
            Text("Couldn't load report")
                .font(.system(size: 18, weight: .semibold))
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(action: onRetry) {
                Text("Try Again")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 11)
                    .background(Color.indigo)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Section Wrapper

private struct ParentSection<Content: View>: View {
    let title: String
    let icon: String
    var iconColor: Color = .indigo
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(UIColor.label))
            }
            content()
        }
        .padding(18)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }
}

// MARK: - Weekly Summary Hero

private struct WeeklySummaryHero: View {
    let studyTime: String
    let questions: Int
    let accuracy:  Int
    let streak:    Int
    let weekRange: String?

    var body: some View {
        VStack(spacing: 0) {
            // Gradient header band
            VStack(spacing: 4) {
                Text("This Week's Report")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                if let range = weekRange {
                    Text(range)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.25, green: 0.32, blue: 0.92), .purple],
                    startPoint: .leading, endPoint: .trailing
                )
            )

            // 2×2 stat grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                HeroStatCell(value: studyTime, label: "Study Time",
                             icon: "clock.fill",              color: .blue,   isTopLeft: true,  isTopRight: false)
                HeroStatCell(value: "\(questions)", label: "Questions",
                             icon: "questionmark.circle.fill", color: .green,  isTopLeft: false, isTopRight: true)
                HeroStatCell(value: "\(accuracy)%", label: "Avg Accuracy",
                             icon: "target",                  color: .purple, isTopLeft: false, isTopRight: false)
                HeroStatCell(value: streak > 0 ? "\(streak) days" : "—", label: "Day Streak",
                             icon: "flame.fill",              color: .orange, isTopLeft: false, isTopRight: false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.07), radius: 10, y: 4)
    }
}

private struct HeroStatCell: View {
    let value:       String
    let label:       String
    let icon:        String
    let color:       Color
    let isTopLeft:   Bool
    let isTopRight:  Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(Color(UIColor.label))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(UIColor.systemBackground))
        .overlay(alignment: .trailing) {
            if isTopLeft || (!isTopLeft && !isTopRight) {
                Rectangle()
                    .fill(Color(UIColor.separator).opacity(0.4))
                    .frame(width: 0.5)
            }
        }
        .overlay(alignment: .bottom) {
            if isTopLeft || isTopRight {
                Rectangle()
                    .fill(Color(UIColor.separator).opacity(0.4))
                    .frame(height: 0.5)
            }
        }
    }
}

// MARK: - Activity Bar Chart

private struct ActivityBarChart: View {
    let days: [ProgressResponse.DailyActivity]
    @State private var appeared = false

    private var maxQuestions: Int { max(days.map(\.questions).max() ?? 1, 1) }
    private let chartHeight: CGFloat = 90
    private let barWidth:    CGFloat = 28
    // Y-axis gridline values
    private var gridValues: [Int] {
        let top = maxQuestions
        guard top > 0 else { return [0] }
        return [0, top / 2, top].map { $0 }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {

                // ── Y-axis gridlines ──
                VStack(spacing: 0) {
                    ForEach(gridValues.reversed(), id: \.self) { val in
                        HStack(spacing: 6) {
                            Text("\(val)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color(UIColor.tertiaryLabel))
                                .frame(width: 16, alignment: .trailing)
                            Rectangle()
                                .fill(Color(UIColor.separator).opacity(0.35))
                                .frame(height: 0.5)
                        }
                        if val != gridValues.first { Spacer() }
                    }
                }
                .frame(height: chartHeight)
                .padding(.leading, 0)
                .padding(.bottom, 32) // room for x-axis labels

                // ── Bars + x-axis labels ──
                HStack(alignment: .bottom, spacing: 0) {
                    Spacer().frame(width: 24) // y-axis label gutter
                    ForEach(days, id: \.dayName) { day in
                        let fraction = appeared
                            ? Double(day.questions) / Double(maxQuestions)
                            : 0.0
                        let barH = max(chartHeight * fraction, day.questions > 0 ? 8 : 3)

                        VStack(spacing: 0) {
                            // Value label above bar
                            ZStack {
                                if day.questions > 0 {
                                    Text("\(day.questions)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.indigo.opacity(0.75))
                                        .clipShape(Capsule())
                                        .opacity(fraction > 0.15 ? 1 : 0)
                                } else {
                                    Color.clear.frame(height: 14)
                                }
                            }
                            .frame(height: 16)

                            // Bar
                            RoundedRectangle(cornerRadius: 7)
                                .fill(
                                    day.questions > 0
                                        ? AnyShapeStyle(LinearGradient(
                                            colors: [.indigo, .purple],
                                            startPoint: .bottom, endPoint: .top))
                                        : AnyShapeStyle(Color(UIColor.systemGray5))
                                )
                                .frame(width: barWidth, height: barH)
                                .animation(.spring(response: 0.55, dampingFraction: 0.75)
                                           .delay(Double(days.firstIndex(where: { $0.dayName == day.dayName }) ?? 0) * 0.06),
                                           value: appeared)

                            // X-axis: abbreviated day
                            Text(String(day.dayName.prefix(3)).uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(day.questions > 0
                                    ? Color(UIColor.label)
                                    : .secondary)
                                .padding(.top, 5)

                            // Time label
                            Text(day.estimatedMin > 0 ? "\(day.estimatedMin)m" : "—")
                                .font(.system(size: 9))
                                .foregroundStyle(Color(UIColor.tertiaryLabel))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: chartHeight + 32) // bars + label rows
            }
        }
        .frame(height: chartHeight + 32)
        .onAppear { withAnimation { appeared = true } }
    }
}

// MARK: - Weak Topic Row

private struct WeakTopicRow: View {
    let topic: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(topic)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(UIColor.label))
                Text("Accuracy below 70% — extra practice recommended")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.orange.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(Color.orange.opacity(0.2), lineWidth: 1))
        .accessibilityLabel("\(topic). Accuracy below 70 percent. Needs extra practice.")
    }
}

// MARK: - Topic Accuracy Row

private struct TopicAccuracyRow: View {
    let topic:    String
    let accuracy: Double
    @State private var appeared = false

    private var color: Color {
        if accuracy >= 80 { return .green }
        if accuracy >= 60 { return .orange }
        return .red
    }
    private var label: String {
        if accuracy >= 80 { return "Strong" }
        if accuracy >= 60 { return "Improving" }
        return "Weak"
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(topic)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(UIColor.label))
                    .lineLimit(1)
                Spacer()
                // Status pill
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.1))
                    .clipShape(Capsule())
                Text("\(Int(accuracy))%")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(color)
                    .frame(minWidth: 36, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(color.opacity(0.1))
                        .frame(height: 10)
                    // Fill
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.7), color],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * (appeared ? min(accuracy / 100, 1.0) : 0),
                               height: 10)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: appeared)
                }
            }
            .frame(height: 10)
        }
        .onAppear { withAnimation { appeared = true } }
        .accessibilityLabel("\(topic), \(Int(accuracy)) percent accuracy, \(label)")
    }
}

// MARK: - Exam Readiness Card

private struct ExamReadinessCard: View {
    let title:       String
    let scoreText:   String
    let progress:    Double
    let summary:     String
    let subjectTags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header row
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Score Prediction")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(scoreText)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                    Text("predicted")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            // Progress bar
            VStack(alignment: .leading, spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 8)
                        Capsule()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: geo.size.width * min(progress, 1.0), height: 8)
                            .animation(.spring(response: 0.6), value: progress)
                    }
                }
                .frame(height: 8)
                HStack {
                    Text("0")
                    Spacer()
                    Text("50%")
                    Spacer()
                    Text("100%")
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            }

            // Narrative
            Text(summary)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.88))
                .lineSpacing(4)

            // Subject tags
            if !subjectTags.isEmpty {
                FlowLayout(spacing: 7) {
                    ForEach(subjectTags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(red: 0.25, green: 0.32, blue: 0.92),
                         Color(red: 0.54, green: 0.22, blue: 0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .indigo.opacity(0.35), radius: 12, y: 5)
    }
}

// MARK: - WhatsApp Toggle Row

private struct WhatsAppToggleRow: View {
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.07, green: 0.78, blue: 0.42),
                                     Color(red: 0.02, green: 0.60, blue: 0.32)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                Image(systemName: "message.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("WhatsApp Alerts")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(UIColor.label))
                Text("Receive daily progress updates")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .tint(Color(red: 0.07, green: 0.78, blue: 0.42))
        }
        .padding(16)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    isEnabled
                        ? Color(red: 0.07, green: 0.78, blue: 0.42).opacity(0.35)
                        : Color(UIColor.separator).opacity(0.3),
                    lineWidth: 1.5
                )
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}

// MARK: - Flow Layout (wrapping HStack for subject tags)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var rowH: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowH + spacing; x = bounds.minX; rowH = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

// MARK: - Model Types (unchanged)

fileprivate struct ParentAlert: Identifiable {
    let id = UUID()
    let type: AlertKind
    let topic: String
    let message: String
    enum AlertKind { case warning, success }
}
