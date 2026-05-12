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

    private let topicAccuracy: [(topic: String, accuracy: Double)] = [
        ("Physics",   85),
        ("Chemistry", 72),
        ("Maths",     90),
        ("Biology",   65),
    ]

    private let weeklyStudyTime: [(day: String, minutes: Int)] = [
        ("Mon", 45), ("Tue", 60), ("Wed", 30),
        ("Thu", 75), ("Fri", 50), ("Sat", 90), ("Sun", 65),
    ]

    private let weakTopics: [(name: String, accuracy: Int, questions: Int)] = [
        ("Organic Chemistry - Reactions",  45, 12),
        ("Physics - Rotational Motion",    52,  8),
        ("Maths - Probability",            58, 15),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Gradient header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Progress")
                        .font(.system(size: 24, weight: .bold))
                    Text("Keep up the great work!")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(.white)
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
                    // Stats grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ProgressStatCard(icon: "flame.fill",  iconColor: .orange, bgColor: .orange.opacity(0.12), value: "7",    label: "Day Streak")
                        ProgressStatCard(icon: "target",       iconColor: .green,  bgColor: .green.opacity(0.12),  value: "78%",  label: "Avg Accuracy")
                        ProgressStatCard(icon: "book.fill",    iconColor: .blue,   bgColor: .blue.opacity(0.12),   value: "142",  label: "Questions")
                        ProgressStatCard(icon: "clock.fill",   iconColor: .purple, bgColor: .purple.opacity(0.12), value: "6.2h", label: "This Week")
                    }

                    // Weekly study time — line chart
                    ChartCard(title: "Weekly Study Time", trailingIcon: "chart.line.uptrend.xyaxis", trailingColor: .green) {
                        Chart(weeklyStudyTime, id: \.day) { item in
                            AreaMark(
                                x: .value("Day", item.day),
                                y: .value("Minutes", item.minutes)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.indigo.opacity(0.25), .indigo.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            LineMark(
                                x: .value("Day", item.day),
                                y: .value("Minutes", item.minutes)
                            )
                            .foregroundStyle(Color.indigo)
                            .lineStyle(StrokeStyle(lineWidth: 3))
                            .symbol(Circle().strokeBorder(lineWidth: 2))
                            .symbolSize(36)
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

                    // Subject performance — bar chart
                    ChartCard(title: "Subject Performance", trailingIcon: "rosette", trailingColor: .yellow) {
                        Chart(topicAccuracy, id: \.topic) { item in
                            BarMark(
                                x: .value("Subject", item.topic),
                                y: .value("Accuracy %", item.accuracy)
                            )
                            .foregroundStyle(Color.purple.gradient)
                            .cornerRadius(8)
                            .annotation(position: .top) {
                                Text("\(Int(item.accuracy))%")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .chartYScale(domain: 0...110)
                        .chartYAxis {
                            AxisMarks(values: [0, 25, 50, 75, 100]) {
                                AxisValueLabel().font(.system(size: 11))
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            }
                        }
                        .frame(height: 200)
                    }

                    // Weak topics
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(Color.red).frame(width: 32, height: 32)
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white)
                            }
                            Text("Topics Needing Attention")
                                .font(.system(size: 16, weight: .bold))
                        }

                        ForEach(weakTopics, id: \.name) { topic in
                            WeakTopicRow(
                                name: topic.name,
                                accuracy: topic.accuracy,
                                questions: topic.questions
                            )
                        }

                        Button {
                            // Practice weak topics
                        } label: {
                            Text("Practice Weak Topics")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
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

                    // Exam readiness
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "rosette")
                            Text("JEE Exam Readiness")
                                .font(.system(size: 17, weight: .bold))
                        }
                        HStack {
                            Text("Overall Preparedness").font(.system(size: 14))
                            Spacer()
                            Text("73%").font(.system(size: 14, weight: .bold))
                        }
                        LinearProgressBar(value: 0.73, foreground: .white.opacity(0.9), background: .white.opacity(0.2))
                        Text("Great progress! Focus on organic chemistry and rotational motion to reach 85% readiness.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.85))
                            .lineSpacing(3)
                    }
                    .foregroundColor(.white)
                    .padding(20)
                    .background(
                        LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                .padding(.horizontal, 16)
                .padding(.top, -16)
                .padding(.bottom, 32)
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .ignoresSafeArea(edges: .top)
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
                    .foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: 22, weight: .bold))
                Text(label).font(.system(size: 11)).foregroundColor(.secondary)
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
                    .foregroundColor(trailingColor)
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
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer()
                Text("\(accuracy)%")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.red)
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
