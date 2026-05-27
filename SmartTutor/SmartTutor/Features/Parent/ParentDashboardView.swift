//
//  ParentDashboardView.swift
//  SmartTutor
//
//  Converted from ParentDashboard.tsx
//  Weekly summary, alerts, daily activity log, exam readiness prediction, WhatsApp toggle.
//

import SwiftUI

struct ParentDashboardView: View {

    @Environment(AppState.self) private var appState
    @State private var vm = ParentDashboardViewModel()

    @State private var whatsappEnabled = true

    var body: some View {
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
                // Week range subtitle banner
                if let range = vm.weekRange {
                    Text(range)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.2))
                }

                VStack(spacing: 16) {
                    if vm.isLoading {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if let error = vm.errorMessage {
                        Text(error)
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    } else {
                    // Weekly summary
                    VStack(alignment: .leading, spacing: 16) {
                        Label("This Week's Summary", systemImage: "target")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            SummaryCell(value: vm.studyTimeFormatted,         label: "Study Time",    color: .blue)
                            SummaryCell(value: "\(vm.questionsAttempted)",    label: "Questions",     color: .green)
                            SummaryCell(value: "\(vm.avgAccuracy)%",          label: "Avg Accuracy",  color: .purple)
                            SummaryCell(value: vm.dayStreak > 0 ? "\(vm.dayStreak) days" : "—",
                                                                               label: "Streak",        color: .orange)
                        }
                    }
                    .padding(20)
                    .background(AppColors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

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
                                .foregroundStyle(AppColors.textPrimary)
                            VStack(spacing: 10) {
                                ForEach(vm.topicBreakdown, id: \.topic) { t in
                                    HStack {
                                        Text(t.topic)
                                            .font(.system(size: 14))
                                            .foregroundStyle(AppColors.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(Int(t.accuracyPct))%")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(t.accuracyPct >= 70 ? .green : .orange)
                                    }
                                    LinearProgressBar(
                                        value: t.accuracyPct / 100,
                                        foreground: t.accuracyPct >= 70 ? .green : .orange,
                                        background: Color.white.opacity(0.15)
                                    )
                                }
                            }
                        }
                        .padding(20)
                        .background(AppColors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }

                    // Daily Activity Log
                    if !vm.dailyActivity.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Daily Activity Log", systemImage: "calendar.day.timeline.left")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(AppColors.textPrimary)
                            VStack(spacing: 0) {
                                ForEach(Array(vm.dailyActivity.enumerated()), id: \.element.dayName) { idx, day in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(day.dayName)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(AppColors.textPrimary)
                                            Text("\(day.questions) questions")
                                                .font(.system(size: 12))
                                                .foregroundStyle(AppColors.textSecondary)
                                        }
                                        Spacer()
                                        HStack(spacing: 4) {
                                            Image(systemName: "clock")
                                                .font(.system(size: 11))
                                                .foregroundStyle(AppColors.textSecondary)
                                            Text("\(day.estimatedMin) min")
                                                .font(.system(size: 13))
                                                .foregroundStyle(AppColors.textSecondary)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(idx % 2 == 0
                                        ? AppColors.cardBackground
                                        : AppColors.cardBackgroundSecondary)
                                    if idx < vm.dailyActivity.count - 1 {
                                        Divider().padding(.leading, 16)
                                    }
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                        }
                        .padding(20)
                        .background(AppColors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }

                    // Exam prediction
                    VStack(alignment: .leading, spacing: 14) {
                        Label(vm.examReadinessTitle, systemImage: "target")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)

                        HStack {
                            Text("Predicted Score Range")
                                .font(.system(size: 14))
                            Spacer()
                            Text(vm.predictedScoreText)
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(.white)

                        LinearProgressBar(
                            value: vm.predictedScoreProgress,
                            foreground: .white.opacity(0.9),
                            background: .white.opacity(0.2)
                        )

                        Text(vm.readinessSummary)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineSpacing(3)

                        if !vm.subjectTags.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(vm.subjectTags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.white.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .padding(20)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: AppColors.gradientColors),
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
                                .foregroundStyle(AppColors.textPrimary)
                            Text("Get daily updates via WhatsApp")
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $whatsappEnabled)
                            .labelsHidden()
                            .tint(.green)
                    }
                    .padding(20)
                    .background(AppColors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.green.opacity(0.4), lineWidth: 1.5))
                    } // end else
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .scrollContentBackground(.hidden)
        } // ZStack
        .navigationTitle("Parent Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(
            LinearGradient(gradient: Gradient(colors: AppColors.gradientColors), startPoint: .top, endPoint: .bottom),
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(.white)
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
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(AppColors.cardBackgroundSecondary)
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
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(alert.topic)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(alert.message)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineSpacing(2)
                if isWarning {
                    Button {
                        // View practice plan
                    } label: {
                        Text("View Practice Plan →")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
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
