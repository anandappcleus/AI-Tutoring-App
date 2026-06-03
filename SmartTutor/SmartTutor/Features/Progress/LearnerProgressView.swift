//
//  LearnerProgressView.swift
//  SmartTutor
//
//  Converted from ProgressScreen.tsx
//  Stats cards, Charts framework line + bar charts, weak topics, exam readiness.
//

import SwiftUI
import Charts

struct LearnerProgressView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = ProgressViewModel()
    @State private var selectedSubjectName: String? = nil
    @State private var selectedDayName: String? = nil
    @AppStorage("selectedMainTab")   private var selectedMainTab   = 0
    @AppStorage("pendingStudyTopic") private var pendingStudyTopic = ""

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView("Loading progress…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    mainContent
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("My Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(
                LinearGradient(colors: [.indigo, .purple],
                               startPoint: .leading, endPoint: .trailing),
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task {
            AppLogger.navigated(to: "LearnerProgressView")
            if let id = appState.currentProfile?.id {
                await vm.load(studentId: id)
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let data = vm.progressData {
            ScrollView {
                VStack(spacing: 20) {
                    // ── Accuracy ring hero ──
                    AccuracyHeroCard(
                        accuracyPct:   data.overallAccuracyPct,
                        dayStreak:     data.dayStreak,
                        totalQuestions: data.totalQuestions,
                        studyMinWeek:  data.estimatedStudyMinWeek
                    )
                    .padding(.horizontal, 16)

                    // ── Cached data banner ──
                    if vm.isShowingCachedData {
                        Label("Showing cached data — refreshes when online",
                              systemImage: "wifi.slash")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color(UIColor.secondarySystemBackground))
                            .clipShape(Capsule())
                    }

                    // ── Weekly study time chart ──
                    if !data.dailyActivity.isEmpty {
                        ProgressSection(title: "Weekly Study Time", icon: "chart.line.uptrend.xyaxis", iconColor: .purple) {
                            Chart(data.dailyActivity, id: \.dayName) { item in
                                AreaMark(
                                    x: .value("Day", item.dayName),
                                    y: .value("Minutes", item.estimatedMin)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.purple.opacity(0.25), .purple.opacity(0.03)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                                LineMark(
                                    x: .value("Day", item.dayName),
                                    y: .value("Minutes", item.estimatedMin)
                                )
                                .foregroundStyle(Color.purple)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                                .symbol {
                                    Circle()
                                        .fill(Color.purple)
                                        .frame(width: 8, height: 8)
                                        .overlay(Circle().stroke(.white, lineWidth: 2))
                                }
                                .annotation(position: .top, spacing: 4) {
                                    if item.dayName == selectedDayName {
                                        ChartTooltipCard(title: item.dayName,
                                                         subtitle: "\(item.estimatedMin) min",
                                                         color: .purple)
                                    }
                                }
                            }
                            .chartYAxis {
                                AxisMarks(values: .automatic(desiredCount: 4)) {
                                    AxisValueLabel()
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color(UIColor.secondaryLabel))
                                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                                        .foregroundStyle(Color(UIColor.separator).opacity(0.5))
                                }
                            }
                            .chartXAxis {
                                AxisMarks {
                                    AxisValueLabel()
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color(UIColor.secondaryLabel))
                                }
                            }
                            .chartXSelection(value: $selectedDayName)
                            .frame(height: 160)
                        }
                        .padding(.horizontal, 16)
                    }

                    // ── Subject performance chart ──
                    let subjectOrder = ["Physics", "Chemistry", "Maths", "Mathematics", "Biology"]
                    let rawSubjects: [ProgressResponse.SubjectAccuracy] = data.subjectAccuracy.isEmpty
                        ? Array(data.topics.prefix(6).map {
                            ProgressResponse.SubjectAccuracy(
                                subject: $0.topic, total: $0.total,
                                correct: $0.correct, accuracyPct: $0.accuracyPct)
                          })
                        : data.subjectAccuracy
                    let subjectItems = Array(rawSubjects.sorted {
                        let i0 = subjectOrder.firstIndex(of: $0.subject) ?? Int.max
                        let i1 = subjectOrder.firstIndex(of: $1.subject) ?? Int.max
                        if i0 != i1 { return i0 < i1 }
                        return $0.total > $1.total
                    }.prefix(6))

                    if !subjectItems.isEmpty {
                        ProgressSection(title: "Subject Performance", icon: "chart.bar.fill", iconColor: .indigo) {
                            Chart(subjectItems, id: \.subject) { item in
                                BarMark(
                                    x: .value("Subject", item.subject),
                                    y: .value("Accuracy %", item.accuracyPct)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.indigo, .purple],
                                        startPoint: .bottom, endPoint: .top
                                    )
                                )
                                .cornerRadius(8)
                                .annotation(position: .top, spacing: 4) {
                                    if item.subject == selectedSubjectName {
                                        ChartTooltipCard(title: item.subject,
                                                         subtitle: "\(Int(item.accuracyPct))%",
                                                         color: .indigo)
                                    }
                                }
                            }
                            .chartYScale(domain: 0...110)
                            .chartYAxis {
                                AxisMarks(values: [0, 25, 50, 75, 100]) {
                                    AxisValueLabel()
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color(UIColor.secondaryLabel))
                                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                                        .foregroundStyle(Color(UIColor.separator).opacity(0.5))
                                }
                            }
                            .chartXAxis {
                                AxisMarks {
                                    AxisValueLabel()
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color(UIColor.secondaryLabel))
                                }
                            }
                            .chartXSelection(value: $selectedSubjectName)
                            .frame(height: 200)
                        }
                        .padding(.horizontal, 16)
                    }

                    // ── Weak topics ──
                    let attentionTopics: [ProgressResponse.TopicProgress] = {
                        let weak = data.topics.filter { data.weakTopics.contains($0.topic) }
                        if !weak.isEmpty { return weak }
                        let lowest = data.topics
                            .filter { $0.topic != "Uncategorised" }
                            .sorted { $0.accuracyPct < $1.accuracyPct }
                            .prefix(3)
                        guard lowest.contains(where: { $0.accuracyPct < 80 }) else { return [] }
                        return Array(lowest)
                    }()

                    if !attentionTopics.isEmpty {
                        WeakTopicsCard(
                            topics: attentionTopics,
                            onPractice: {
                                let topicList = data.weakTopics.prefix(3).joined(separator: ", ")
                                pendingStudyTopic = "Give me 3 JEE/NEET practice questions on: \(topicList)"
                                selectedMainTab = 1
                            }
                        )
                        .padding(.horizontal, 16)
                    }

                    // ── Exam readiness ──
                    let examLabel: String = {
                        let target = appState.currentProfile?.examTarget.rawValue ?? ""
                        return target.isEmpty ? "Exam Readiness" : "\(target) Exam Readiness"
                    }()
                    let readinessPct = data.totalQuestions > 0 ? data.overallAccuracyPct / 100.0 : 0.0
                    ExamReadinessProgressCard(
                        title:        examLabel,
                        accuracyPct:  data.overallAccuracyPct,
                        readinessPct: readinessPct,
                        weakTopics:   data.weakTopics
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
                .padding(.top, 16)
            }
        } else if let errMsg = vm.errorMessage {
            VStack(spacing: 16) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Couldn't load progress")
                    .font(.system(size: 17, weight: .semibold))
                Text(errMsg)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button {
                    if let id = appState.currentProfile?.id {
                        Task { await vm.load(studentId: id) }
                    }
                } label: {
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
        } else {
            // Empty state
            VStack(spacing: 16) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.secondary)
                Text("No progress yet")
                    .font(.system(size: 18, weight: .semibold))
                Text("Answer questions in the Study tab and your stats will appear here.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button {
                    selectedMainTab = 1
                } label: {
                    Label("Start Studying", systemImage: "brain.head.profile")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(colors: [.indigo, .purple],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Accuracy Hero Card

private struct AccuracyHeroCard: View {
    let accuracyPct:    Double
    let dayStreak:      Int
    let totalQuestions: Int
    let studyMinWeek:   Int
    @State private var appeared = false

    private var studyHoursText: String {
        let h = Double(studyMinWeek) / 60.0
        return h < 10 ? String(format: "%.1fh", h) : String(format: "%.0fh", h)
    }
    private var ringColor: Color {
        if accuracyPct >= 80 { return .green }
        if accuracyPct >= 60 { return Color(red: 0.12, green: 0.65, blue: 0.40) }
        return .orange
    }

    var body: some View {
        HStack(spacing: 20) {
            // Accuracy ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 9)
                    .frame(width: 90, height: 90)
                Circle()
                    .trim(from: 0, to: appeared ? min(accuracyPct / 100, 1.0) : 0)
                    .stroke(ringColor,
                            style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 90, height: 90)
                    .animation(.spring(response: 0.8, dampingFraction: 0.75), value: appeared)
                VStack(spacing: 1) {
                    Text("\(Int(accuracyPct))%")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(.white)
                    Text("accuracy")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .textCase(.uppercase)
                }
            }

            // Stat chips
            VStack(alignment: .leading, spacing: 10) {
                Text("This Week")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))

                HStack(spacing: 14) {
                    HeroChip(icon: "flame.fill",    value: "\(dayStreak)",      label: "Streak",    color: .orange)
                    HeroChip(icon: "book.fill",     value: "\(totalQuestions)", label: "Questions", color: .cyan)
                    HeroChip(icon: "clock.fill",    value: studyHoursText,      label: "Study",     color: .purple.opacity(0.6))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            LinearGradient(
                colors: [Color(red: 0.25, green: 0.32, blue: 0.92), .purple],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .indigo.opacity(0.35), radius: 12, y: 5)
        .onAppear { withAnimation { appeared = true } }
    }
}

private struct HeroChip: View {
    let icon:  String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)
        }
    }
}

// MARK: - Section Card

private struct ProgressSection<C: View>: View {
    let title:      String
    let icon:       String
    let iconColor:  Color
    @ViewBuilder let content: () -> C

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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

// MARK: - Weak Topics Card

private struct WeakTopicsCard: View {
    let topics:     [ProgressResponse.TopicProgress]
    let onPractice: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                }
                Text("Needs Attention")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(UIColor.label))
                Spacer()
                Text("\(topics.count) topic\(topics.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.1))
                    .clipShape(Capsule())
            }

            // Topic rows
            VStack(spacing: 10) {
                ForEach(topics, id: \.topic) { topic in
                    ProgressWeakTopicRow(name: topic.topic,
                                         accuracy: Int(topic.accuracyPct),
                                         questions: topic.total)
                }
            }

            // CTA
            Button(action: onPractice) {
                Label("Practice Weak Topics", systemImage: "bolt.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        LinearGradient(colors: [.red, .orange],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(18)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20)
            .stroke(Color.red.opacity(0.15), lineWidth: 1))
        .shadow(color: .red.opacity(0.07), radius: 8, y: 3)
    }
}

// MARK: - Exam Readiness Progress Card

private struct ExamReadinessProgressCard: View {
    let title:        String
    let accuracyPct:  Double
    let readinessPct: Double
    let weakTopics:   [String]
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 42, height: 42)
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Overall Preparedness")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Text("\(Int(accuracyPct))%")
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(.white)
            }

            // Animated progress bar
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 10)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.7), .white],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * (appeared ? min(readinessPct, 1.0) : 0),
                                   height: 10)
                            .animation(.spring(response: 0.8, dampingFraction: 0.75), value: appeared)
                    }
                }
                .frame(height: 10)

                HStack {
                    Text("0%")
                    Spacer()
                    Text("50%")
                    Spacer()
                    Text("100%")
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            }

            // Narrative
            Text(weakTopics.isEmpty
                 ? "Great work! Keep practising to maintain your accuracy."
                 : "Focus on \(weakTopics.prefix(2).joined(separator: " and ")) to reach \(min(Int(accuracyPct) + 12, 100))% readiness.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.88))
                .lineSpacing(4)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.55, blue: 0.35),
                         Color(red: 0.05, green: 0.75, blue: 0.50)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .green.opacity(0.3), radius: 10, y: 4)
        .onAppear { withAnimation { appeared = true } }
    }
}

// MARK: - Supporting Views

private struct ProgressWeakTopicRow: View {
    let name: String
    let accuracy: Int
    let questions: Int
    @State private var appeared = false

    private var barColor: Color {
        if accuracy >= 70 { return .green }
        if accuracy >= 45 { return .orange }
        return .red
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left stripe
            Capsule()
                .fill(barColor)
                .frame(width: 4)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(UIColor.label))
                        Text("\(questions) questions attempted")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(accuracy)%")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(barColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(barColor.opacity(0.1))
                        .clipShape(Capsule())
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(barColor.opacity(0.12))
                            .frame(height: 8)
                        Capsule()
                            .fill(
                                LinearGradient(colors: [barColor.opacity(0.7), barColor],
                                               startPoint: .leading, endPoint: .trailing)
                            )
                            .frame(width: geo.size.width * (appeared ? min(Double(accuracy) / 100.0, 1.0) : 0), height: 8)
                            .animation(.spring(response: 0.7, dampingFraction: 0.8), value: appeared)
                    }
                }
                .frame(height: 8)
            }
            .padding(.leading, 12)
            .padding(.vertical, 12)
            .padding(.trailing, 14)
        }
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(barColor.opacity(0.15), lineWidth: 1))
        .onAppear { withAnimation { appeared = true } }
    }
}

private struct ChartTooltipCard: View {
    let title:    String
    let subtitle: String
    var color:    Color = .purple

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(UIColor.label))
            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}

struct LinearProgressBar: View {
    let value: Double
    var foreground: Color = .indigo
    var background: Color = Color.gray.opacity(0.15)
    var useGradient: Bool = false
    var gradientColors: [Color] = []

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(background)
                if useGradient && !gradientColors.isEmpty {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * min(max(value, 0), 1))
                } else {
                    Capsule()
                        .fill(foreground)
                        .frame(width: geo.size.width * min(max(value, 0), 1))
                }
            }
        }
        .frame(height: 8)
    }
}
