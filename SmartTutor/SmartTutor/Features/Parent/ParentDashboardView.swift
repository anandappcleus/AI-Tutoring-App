//
//  ParentDashboardView.swift
//  SmartTutor
//
//  Converted from ParentDashboard.tsx
//  Weekly summary, alerts, daily activity log, exam readiness prediction, WhatsApp toggle.
//

import SwiftUI

struct ParentDashboardView: View {

    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = ParentDashboardViewModel()

    @State private var whatsappEnabled = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 20))
                        Text("Parent Dashboard")
                            .font(.system(size: 24, weight: .bold))
                    }
                    Text(vm.weekRange.map { "Week: \($0)" } ?? "Monitoring your child's progress")
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
                        colors: [Color(red: 0.16, green: 0.44, blue: 0.95), .cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

                VStack(spacing: 16) {
                    if vm.isLoading {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if let error = vm.errorMessage {
                        Text(error)
                            .foregroundColor(.secondary)
                            .padding(.top, 40)
                    } else {
                    // Weekly summary
                    VStack(alignment: .leading, spacing: 16) {
                        Label("This Week's Summary", systemImage: "target")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            SummaryCell(value: "—",                              label: "Study Time",    color: .blue)
                            SummaryCell(value: "\(vm.questionsAttempted)",       label: "Questions",     color: .green)
                            SummaryCell(value: "\(vm.avgAccuracy)%",             label: "Avg Accuracy",  color: .purple)
                            SummaryCell(value: "—",                              label: "Streak",        color: .orange)
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                            Text("Study time & streak coming soon")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(20)
                    .background(Color(UIColor.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)

                    // Alerts derived from weak topics
                    if !vm.weakTopics.isEmpty {
                        ForEach(vm.weakTopics, id: \.self) { topic in
                            AlertCard(alert: ParentAlert(
                                type: .warning,
                                topic: topic,
                                message: "Needs more practice on \(topic) — accuracy below 70%"
                            ))
                        }
                    }

                    // Topic accuracy breakdown
                    if !vm.topicBreakdown.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Topic Accuracy", systemImage: "chart.bar.fill")
                                .font(.system(size: 16, weight: .bold))
                            VStack(spacing: 10) {
                                ForEach(vm.topicBreakdown, id: \.topic) { t in
                                    HStack {
                                        Text(t.topic)
                                            .font(.system(size: 14))
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(Int(t.accuracyPct))%")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(t.accuracyPct >= 70 ? .green : .orange)
                                    }
                                    LinearProgressBar(
                                        value: t.accuracyPct / 100,
                                        foreground: t.accuracyPct >= 70 ? .green : .orange,
                                        background: Color(UIColor.systemGray5)
                                    )
                                }
                            }
                        }
                        .padding(20)
                        .background(Color(UIColor.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                    }

                    // Exam prediction
                    VStack(alignment: .leading, spacing: 14) {
                        Label("JEE Exam Readiness Prediction", systemImage: "target")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)

                        HStack {
                            Text("Predicted Score Range")
                                .font(.system(size: 14))
                            Spacer()
                            Text("165–185 / 300")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(.white)

                        LinearProgressBar(
                            value: 0.62,
                            foreground: .white.opacity(0.9),
                            background: .white.opacity(0.2)
                        )

                        Text("Based on current performance, Riya is on track for a good score. Consistent practice on weak topics can improve the score by 15–20 marks.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.85))
                            .lineSpacing(3)

                        let subjectTags = ["Physics: 78%", "Chemistry: 65%", "Maths: 82%"]
                        HStack(spacing: 8) {
                            ForEach(subjectTags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(20)
                    .background(
                        LinearGradient(
                            colors: [.indigo, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    // WhatsApp alerts
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 48, height: 48)
                            Text("💬").font(.system(size: 22))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("WhatsApp Alerts")
                                .font(.system(size: 15, weight: .bold))
                            Text("Get daily updates via WhatsApp")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $whatsappEnabled)
                            .labelsHidden()
                            .tint(.green)
                    }
                    .padding(20)
                    .background(Color(UIColor.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.green.opacity(0.25), lineWidth: 2))
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                    } // end else
                }
                .padding(.horizontal, 16)
                .padding(.top, -16)
                .padding(.bottom, 32)
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .ignoresSafeArea(edges: .top)
        .navigationTitle("Parent Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let id = appState.currentProfile?.id {
                await vm.load(studentId: id)
            }
        }
    }
}

// MARK: - Model Types

fileprivate struct ParentAlert: Identifiable {
    let id = UUID()
    let type: AlertKind
    let topic: String
    let message: String
    enum AlertKind { case warning, success }
}

// MARK: - Supporting Views

private struct SummaryCell: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct AlertCard: View {
    let alert: ParentAlert

    private var isWarning: Bool { alert.type == .warning }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(isWarning ? Color.yellow : Color.green)
                    .frame(width: 40, height: 40)
                Image(systemName: isWarning ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(alert.topic)
                    .font(.system(size: 15, weight: .semibold))
                Text(alert.message)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
                if isWarning {
                    Button {
                        // View practice plan
                    } label: {
                        Text("View Practice Plan →")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(16)
        .background(
            isWarning
            ? Color.yellow.opacity(0.07)
            : Color.green.opacity(0.07)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(isWarning ? Color.yellow.opacity(0.3) : Color.green.opacity(0.3), lineWidth: 1)
        )
    }
}
