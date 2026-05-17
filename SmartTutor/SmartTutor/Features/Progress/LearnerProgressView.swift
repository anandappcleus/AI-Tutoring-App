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
    @AppStorage("selectedMainTab")   private var selectedMainTab   = 0
    @AppStorage("pendingStudyTopic") private var pendingStudyTopic = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // ── Gradient header ─────────────────────────────────
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Progress")
                        .font(.system(size: 24, weight: .bold))
                    Text("Keep up the great work!")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 36)
                .background(
                    LinearGradient(
                        colors: [.indigo, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

                VStack(spacing: 16) {
                    if vm.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 100)
                    } else if let data = vm.progressData {

                        // ── Stats grid ──────────────────────────────
                        let studyHours = Double(data.estimatedStudyMinWeek) / 60.0
                        let studyHoursText = studyHours < 10
                            ? String(format: "%.1fh", studyHours)
                            : String(format: "%.0fh", studyHours)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ProgressStatCard(icon: "flame.fill",  iconColor: .orange, bgColor: .orange.opacity(0.12), value: "\(data.dayStreak)",               label: "Day Streak")
                            ProgressStatCard(icon: "target",      iconColor: .green,  bgColor: .green.opacity(0.12),  value: "\(Int(data.overallAccuracyPct))%", label: "Avg Accuracy")
                            ProgressStatCard(icon: "book.fill",   iconColor: .blue,   bgColor: .blue.opacity(0.12),   value: "\(data.totalQuestions)",           label: "Questions")
                            ProgressStatCard(icon: "clock.fill",  iconColor: .purple, bgColor: .purple.opacity(0.12), value: studyHoursText,                     label: "This Week")
                        }

                        // ── Weekly Study Time — line chart ───────────
                        if !data.dailyActivity.isEmpty {
                            ChartCard(title: "Weekly Study Time", trailingIcon: "arrow.up.right", trailingColor: .green) {
                                Chart(data.dailyActivity, id: \.dayName) { item in
                                    LineMark(
                                        x: .value("Day", item.dayName),
                                        y: .value("Minutes", item.estimatedMin)
                                    )
                                    .foregroundStyle(Color.purple.gradient)
                                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                                    .symbol(.circle)
                                    .symbolSize(36)
                                    AreaMark(
                                        x: .value("Day", item.dayName),
                                        y: .value("Minutes", item.estimatedMin)
                                    )
                                    .foregroundStyle(Color.purple.opacity(0.12).gradient)
                                }
                                .chartYAxis {
                                    AxisMarks(values: .automatic(desiredCount: 4)) {
                                        AxisValueLabel().font(.system(size: 11))
                                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    }
                                }
                                .chartXAxis {
                                    AxisMarks { AxisValueLabel().font(.system(size: 11)) }
                                }
                                .frame(height: 160)
                            }
                        }

                        // ── Subject Performance — bar chart ──────────
                        // Use subject_accuracy if populated; fall back to top topics
                        let subjectItems: [ProgressResponse.SubjectAccuracy] = data.subjectAccuracy.isEmpty
                            ? Array(data.topics.prefix(6).map {
                                ProgressResponse.SubjectAccuracy(
                                    subject: $0.topic, total: $0.total,
                                    correct: $0.correct, accuracyPct: $0.accuracyPct)
                              })
                            : data.subjectAccuracy

                        if !subjectItems.isEmpty {
                            ChartCard(title: "Subject Performance", trailingIcon: "rosette", trailingColor: .yellow) {
                                VStack(spacing: 8) {
                                    Chart(subjectItems, id: \.subject) { item in
                                        BarMark(
                                            x: .value("Subject", item.subject),
                                            y: .value("Accuracy %", item.accuracyPct)
                                        )
                                        .foregroundStyle(
                                            item.subject == selectedSubjectName
                                                ? Color.indigo.gradient
                                                : Color.purple.gradient
                                        )
                                        .cornerRadius(8)
                                    }
                                    .chartYScale(domain: 0...110)
                                    .chartYAxis {
                                        AxisMarks(values: [0, 25, 50, 75, 100]) {
                                            AxisValueLabel().font(.system(size: 11))
                                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                        }
                                    }
                                    .chartOverlay { proxy in
                                        GeometryReader { _ in
                                            Rectangle()
                                                .fill(.clear)
                                                .contentShape(Rectangle())
                                                .onTapGesture { location in
                                                    guard let subject = proxy.value(atX: location.x, as: String.self) else { return }
                                                    withAnimation(.easeInOut(duration: 0.2)) {
                                                        selectedSubjectName = selectedSubjectName == subject ? nil : subject
                                                    }
                                                }
                                        }
                                    }
                                    .frame(height: 200)

                                    if let name = selectedSubjectName,
                                       let sel = subjectItems.first(where: { $0.subject == name }) {
                                        Text("\(sel.subject) accuracy: \(Int(sel.accuracyPct))%")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.purple)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.purple.opacity(0.08))
                                            .clipShape(Capsule())
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                            }
                        }

                        // ── Topics Needing Attention ──────────────────
                        if !data.weakTopics.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(spacing: 10) {
                                    ZStack {
                                        Circle().fill(Color.red).frame(width: 32, height: 32)
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.white)
                                    }
                                    Text("Topics Needing Attention")
                                        .font(.system(size: 16, weight: .bold))
                                }

                                ForEach(data.topics.filter { data.weakTopics.contains($0.topic) }, id: \.topic) { topic in
                                    WeakTopicRow(
                                        name: topic.topic,
                                        accuracy: Int(topic.accuracyPct),
                                        questions: topic.total
                                    )
                                }

                                Button {
                                    let topicList = data.weakTopics.prefix(3).joined(separator: ", ")
                                    pendingStudyTopic = "Give me 3 JEE/NEET practice questions on: \(topicList)"
                                    selectedMainTab = 1
                                } label: {
                                    Text("Practice Weak Topics")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 48)
                                        .background(
                                            LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                            }
                            .padding(20)
                            .background(Color.red.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.red.opacity(0.15), lineWidth: 1))
                        }

                        // ── Exam Readiness card ───────────────────────
                        let examLabel: String = {
                            let target = appState.currentProfile?.examTarget.rawValue ?? ""
                            return target.isEmpty ? "Exam Readiness" : "\(target) Exam Readiness"
                        }()
                        let readinessPct = data.totalQuestions > 0 ? data.overallAccuracyPct / 100.0 : 0.0
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "rosette")
                                Text(examLabel)
                                    .font(.system(size: 17, weight: .bold))
                            }
                            HStack {
                                Text("Overall Preparedness").font(.system(size: 14))
                                Spacer()
                                Text("\(Int(data.overallAccuracyPct))%").font(.system(size: 14, weight: .bold))
                            }
                            LinearProgressBar(value: readinessPct, foreground: .white.opacity(0.9), background: .white.opacity(0.2))
                            Text(data.weakTopics.isEmpty
                                 ? "Great work! Keep practising to maintain your accuracy."
                                 : "Great progress! Focus on \(data.weakTopics.prefix(2).joined(separator: " and ")) to reach \(min(Int(data.overallAccuracyPct) + 12, 100))% readiness.")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineSpacing(3)
                        }
                        .foregroundStyle(.white)
                        .padding(20)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    } else if vm.errorMessage == nil {
                        // Empty state — no quiz answers yet
                        VStack(spacing: 12) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary.opacity(0.5))
                            Text("No progress yet")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Answer some questions in the Study tab and your progress will appear here.")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    }
                    if let errMsg = vm.errorMessage {
                        Text(errMsg)
                            .font(.system(size: 14))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(20)
                    } else if vm.isShowingCachedData {
                        Label("Showing cached data — will refresh when online", systemImage: "wifi.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(UIColor.secondarySystemBackground))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, -16)
                .padding(.bottom, 32)
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .ignoresSafeArea(edges: .top)
        .task {
            AppLogger.navigated(to: "LearnerProgressView")
            if let id = appState.currentProfile?.id {
                await vm.load(studentId: id)
            }
        }
    }
}

// MARK: - Supporting Views

private struct ProgressStatCard: View {
    let icon: String
    let iconColor: Color
    let bgColor: Color
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(bgColor).frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: 22, weight: .bold))
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

private struct ChartCard<ChartContent: View>: View {
    let title: String
    let trailingIcon: String
    let trailingColor: Color
    @ViewBuilder let chart: ChartContent

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title).font(.system(size: 16, weight: .bold))
                Spacer()
                Image(systemName: trailingIcon)
                    .foregroundStyle(trailingColor)
            }
            chart
        }
        .padding(20)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}

private struct WeakTopicRow: View {
    let name: String
    let accuracy: Int
    let questions: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.system(size: 14, weight: .semibold))
                    Text("\(questions) questions attempted")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(accuracy)%")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.red)
            }
            LinearProgressBar(
                value: Double(accuracy) / 100.0,
                foreground: .red,
                background: Color.gray.opacity(0.15),
                useGradient: true,
                gradientColors: [.red, .orange]
            )
        }
        .padding(16)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
