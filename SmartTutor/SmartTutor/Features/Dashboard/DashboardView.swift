//
//  DashboardView.swift
//  SmartTutor
//
//  Converted from Dashboard.tsx
//  Displays profile header, AI ask bar, Today's Focus card, and learning module grid.
//

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = DashboardViewModel()
    @State private var askText = ""
    @State private var showOfflinePacks = false
    @State private var showParentDashboard = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    DashboardHeaderSection(
                        askText: $askText,
                        studentName: appState.currentProfile?.name ?? "Student"
                    )

                    VStack(spacing: 28) {
                        TodaysFocusSection(studyPlan: vm.studyPlan, isLoading: vm.isLoading)
                        LearningModulesSection(
                            showOfflinePacks: $showOfflinePacks,
                            showParentDashboard: $showParentDashboard
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
            .ignoresSafeArea(edges: .top)
            .navigationDestination(isPresented: $showOfflinePacks) {
                OfflinePacksView()
            }
            .navigationDestination(isPresented: $showParentDashboard) {
                ParentDashboardView()
            }
        }
        .task {
            if let id = appState.currentProfile?.id {
                await vm.loadPlan(studentId: id)
            }
        }
    }
}

// MARK: - Header

private struct DashboardHeaderSection: View {
    @Binding var askText: String
    let studentName: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
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
                    Text("R")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome back,")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("\(studentName) 👋")
                        .font(.system(size: 22, weight: .bold))
                }

                Spacer()

                // Streak badge
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    Text("12")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.orange.opacity(0.15), lineWidth: 1))
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
            .padding(.bottom, 20)

            // Ask / search bar
            HStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.system(size: 20))
                    .foregroundColor(.indigo)

                TextField("Ask a doubt in Bengali...", text: $askText)
                    .font(.system(size: 15, weight: .medium))

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    Button {
                        // Camera action
                    } label: {
                        Image(systemName: "camera")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }

                    Rectangle()
                        .fill(Color.gray.opacity(0.25))
                        .frame(width: 1, height: 24)

                    Button {
                        // Mic action
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.indigo)
                                .frame(width: 40, height: 40)
                                .shadow(color: .indigo.opacity(0.35), radius: 6, y: 3)
                            Image(systemName: "mic.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                        }
                    }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                Text("Today's Focus")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Label("AI Planner", systemImage: "cpu")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.indigo)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.indigo.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color(UIColor.systemBackground))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 2)

                // Decorative gradient blob
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.indigo.opacity(0.08), .purple.opacity(0.03)],
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
                        Text("Loading today\'s plan...")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                } else if let plan = studyPlan, let firstTopic = plan.topics.first {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            TagBadge(text: firstTopic.topic, color: .purple)
                            TagBadge(text: "AI Plan", color: .indigo)
                        }
                        .padding(.bottom, 14)

                        Text(firstTopic.topic)
                            .font(.system(size: 20, weight: .bold))
                            .padding(.bottom, 8)

                        Text("\(firstTopic.durationMin) min · \(plan.topics.count) topic\(plan.topics.count == 1 ? "" : "s") today")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .lineSpacing(3)
                            .padding(.bottom, 20)

                        Button { } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 15))
                                Text("Start AI Lesson")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color(UIColor.label))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .gray.opacity(0.2), radius: 8, y: 3)
                        }
                    }
                    .padding(20)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.indigo.opacity(0.6))
                        Text("Plan generates tonight")
                            .font(.system(size: 16, weight: .semibold))
                        Text("The AI tutor creates your personalised plan nightly at 2 AM IST.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
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
    @Binding var showOfflinePacks: Bool
    @Binding var showParentDashboard: Bool

    struct ModuleItem: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        let iconColor: Color
        let bgColor: Color
    }

    let modules: [ModuleItem] = [
        ModuleItem(title: "Mock Tests",     subtitle: "JEE Mains 2026",    icon: "checkmark.circle.fill",    iconColor: .blue,   bgColor: .blue.opacity(0.1)),
        ModuleItem(title: "Syllabus Map",   subtitle: "Track progress",     icon: "chart.bar.fill",           iconColor: .green,  bgColor: .green.opacity(0.1)),
        ModuleItem(title: "Offline Packs",  subtitle: "Study without data", icon: "arrow.down.circle.fill",   iconColor: .orange, bgColor: .orange.opacity(0.1)),
        ModuleItem(title: "Formula Sheets", subtitle: "Quick revision",     icon: "book.fill",                iconColor: .purple, bgColor: .purple.opacity(0.1)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Learning Modules")
                .font(.system(size: 18, weight: .bold))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(modules) { mod in
                    ModuleCard(item: mod) {
                        if mod.title == "Offline Packs"  { showOfflinePacks = true }
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
                        .foregroundColor(item.iconColor)
                }
                .padding(.bottom, 14)

                Text(item.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)

                Text(item.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
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
            .foregroundColor(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
