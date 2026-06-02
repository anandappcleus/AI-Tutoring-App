//
//  OfflinePacksView.swift
//  SmartTutor
//
//  Sprint 8 — Wired to OfflinePacksViewModel + Core Data.
//  Downloads real packs from GET /packs and caches questions locally.
//  Redesigned: subject filter chips, accent-stripe cards, circular
//  storage gauge, delete confirmation, improved empty/error/loading states.
//

import SwiftUI

struct OfflinePacksView: View {

    @State private var vm = OfflinePacksViewModel()
    @Environment(AppState.self) private var appState
    @State private var practiceItem: PackListItem?
    @State private var selectedSubject: String? = nil

    private let totalKB = 500_000   // 500 MB storage cap

    // Distinct sorted subjects in the full catalog.
    private var subjects: [String] {
        Array(Set(vm.packs.map(\.subject))).sorted()
    }

    private var filteredDownloaded: [PackListItem] {
        guard let s = selectedSubject else { return vm.downloadedPacks }
        return vm.downloadedPacks.filter { $0.subject.lowercased() == s.lowercased() }
    }

    private var filteredAvailable: [PackListItem] {
        guard let s = selectedSubject else { return vm.availablePacks }
        return vm.availablePacks.filter { $0.subject.lowercased() == s.lowercased() }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // ── Circular storage gauge card ───────────────────────
                StorageHeroCard(usedKB: vm.usedKB, totalKB: totalKB)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 4)

                // ── Subject filter chips ──────────────────────────────
                if !vm.packs.isEmpty {
                    SubjectFilterBar(subjects: subjects, selected: $selectedSubject)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                }

                // ── Content ───────────────────────────────────────────
                VStack(spacing: 28) {
                    if vm.isLoading {
                        PackSkeletonView()
                    } else if let error = vm.errorMessage {
                        PackErrorView(message: error) {
                            Task { await vm.loadPacks() }
                        }
                    } else if vm.packs.isEmpty {
                        PackEmptyView()
                    } else {
                        // Downloaded packs
                        if !filteredDownloaded.isEmpty {
                            PackSection(title: "Downloaded", count: filteredDownloaded.count, accentColor: .green) {
                                ForEach(filteredDownloaded) { pack in
                                    DownloadedPackCard(pack: pack) {
                                        vm.deletePack(pack)
                                    } onPractice: {
                                        practiceItem = pack
                                    }
                                }
                            }
                        }

                        // Available packs
                        if !filteredAvailable.isEmpty {
                            PackSection(title: "Available to Download", count: filteredAvailable.count, accentColor: .indigo) {
                                ForEach(filteredAvailable) { pack in
                                    AvailablePackCard(
                                        pack: pack,
                                        isDownloading: vm.downloadingPackId == pack.id,
                                        progress: vm.downloadProgress[pack.id] ?? 0
                                    ) {
                                        Task { await vm.download(pack) }
                                    }
                                }
                            }
                        }

                        // Filter produced no results
                        if filteredDownloaded.isEmpty && filteredAvailable.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary)
                                Text("No \(selectedSubject?.capitalized ?? "") packs yet")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 40)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("Offline Packs")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(
            LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing),
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            AppLogger.navigated(to: "OfflinePacksView")
            await vm.loadPacks()
        }
        .sheet(item: $practiceItem) { pack in
            OfflinePracticeView(pack: pack)
        }
    }
}

// MARK: - Storage Hero Card

private struct StorageHeroCard: View {
    let usedKB: Int
    let totalKB: Int

    private var fraction: Double { min(Double(usedKB) / Double(totalKB), 1.0) }
    private var usedMBLabel: String { String(format: "%.1f MB", Double(usedKB) / 1000.0) }
    private var gaugeColor: Color {
        switch fraction {
        case ..<0.6:  return .green
        case ..<0.85: return .orange
        default:      return .red
        }
    }

    var body: some View {
        HStack(spacing: 20) {
            // Animated circular gauge
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 7)
                    .frame(width: 64, height: 64)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 64, height: 64)
                    .animation(.easeOut(duration: 0.7), value: fraction)
                Text("\(Int(fraction * 100))%")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Offline Storage")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(usedMBLabel) used of 500 MB")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                LinearProgressBar(
                    value: fraction,
                    foreground: gaugeColor,
                    background: .white.opacity(0.2)
                )
                .frame(height: 5)
            }

            Spacer()

            Image(systemName: "internaldrive.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            LinearGradient(
                colors: [.indigo, Color(red: 0.55, green: 0.2, blue: 0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .indigo.opacity(0.35), radius: 14, y: 5)
    }
}

// MARK: - Subject Filter Bar

private struct SubjectFilterBar: View {
    let subjects: [String]
    @Binding var selected: String?

    private func color(for subject: String) -> Color {
        switch subject.lowercased() {
        case "physics":              return .blue
        case "chemistry":            return .teal
        case "maths", "mathematics": return .orange
        case "biology":              return .green
        default:                     return .purple
        }
    }

    private func icon(for subject: String) -> String {
        switch subject.lowercased() {
        case "physics":              return "atom"
        case "chemistry":            return "flask.fill"
        case "maths", "mathematics": return "function"
        case "biology":              return "leaf.fill"
        default:                     return "book.fill"
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                SubjectChip(label: "All", icon: "square.grid.2x2.fill",
                            isSelected: selected == nil, color: .indigo) {
                    selected = nil
                }
                ForEach(subjects, id: \.self) { subject in
                    SubjectChip(
                        label: subject.capitalized,
                        icon: icon(for: subject),
                        isSelected: selected?.lowercased() == subject.lowercased(),
                        color: color(for: subject)
                    ) {
                        selected = selected?.lowercased() == subject.lowercased() ? nil : subject
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
    }
}

private struct SubjectChip: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? .white : color)
            .background(isSelected ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.1)))
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .accessibilityLabel("\(label) filter\(isSelected ? ", selected" : "")")
    }
}

// MARK: - Section Header

private struct PackSection<Content: View>: View {
    let title: String
    let count: Int
    let accentColor: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                // Left accent pill
                Capsule()
                    .fill(accentColor)
                    .frame(width: 4, height: 20)
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                // Count badge
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(accentColor.opacity(0.12))
                    .clipShape(Capsule())
            }
            VStack(spacing: 12) { content }
        }
    }
}

// MARK: - Downloaded Pack Card

private struct DownloadedPackCard: View {
    let pack: PackListItem
    let onDelete: () -> Void
    let onPractice: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Subject accent strip along the top
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [pack.subjectColor, pack.subjectColor.opacity(0.5)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 4)

            VStack(spacing: 12) {
                // Header row
                HStack(spacing: 14) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [pack.subjectColor.opacity(0.18), pack.subjectColor.opacity(0.05)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 54, height: 54)
                        Image(systemName: pack.iconName)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(pack.subjectColor)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(pack.topic)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Text(pack.subject.capitalized)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(pack.subjectColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(pack.subjectColor.opacity(0.12))
                                .clipShape(Capsule())
                            Text("·").foregroundStyle(.tertiary)
                            Label("\(pack.questionCount) Q", systemImage: "questionmark.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Delete button with confirmation
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                            .frame(width: 38, height: 38)
                            .background(Color.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                    }
                    .accessibilityLabel("Delete \(pack.topic)")
                    .confirmationDialog(
                        "Delete \"\(pack.topic)\"?",
                        isPresented: $showDeleteConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive, action: onDelete)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("You'll need to re-download this pack to use it offline.")
                    }
                }

                // Status row
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                    Text("Ready offline")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(pack.sizeDisplay)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                // Practice CTA — full subject color
                Button(action: onPractice) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13))
                        Text("Start Practice")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        LinearGradient(
                            colors: [pack.subjectColor, pack.subjectColor.opacity(0.78)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: pack.subjectColor.opacity(0.35), radius: 6, y: 3)
                }
            }
            .padding(16)
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}

// MARK: - Available Pack Card

private struct AvailablePackCard: View {
    let pack: PackListItem
    let isDownloading: Bool
    let progress: Double
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Left subject-colour accent bar
            Rectangle()
                .fill(pack.subjectColor)
                .frame(width: 5)

            VStack(spacing: 12) {
                // Header
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(pack.subjectColor.opacity(0.1))
                            .frame(width: 50, height: 50)
                        Image(systemName: pack.iconName)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(pack.subjectColor)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(pack.topic)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Text(pack.subject.capitalized)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(pack.subjectColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(pack.subjectColor.opacity(0.1))
                                .clipShape(Capsule())
                            Text("·").foregroundStyle(.tertiary)
                            Label("\(pack.questionCount) Q", systemImage: "questionmark.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text("·").foregroundStyle(.tertiary)
                            Text(pack.sizeDisplay)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                // Download / progress
                if isDownloading {
                    VStack(spacing: 6) {
                        HStack {
                            Text("Downloading…")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(pack.subjectColor)
                        }
                        LinearProgressBar(
                            value: progress,
                            foreground: pack.subjectColor,
                            background: Color.gray.opacity(0.15),
                            useGradient: true,
                            gradientColors: [pack.subjectColor, pack.subjectColor.opacity(0.6)]
                        )
                    }
                } else {
                    Button(action: onDownload) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 16))
                            Text("Download  \(pack.sizeDisplay)")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(pack.subjectColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(pack.subjectColor.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(pack.subjectColor.opacity(0.3), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel("Download \(pack.topic), \(pack.sizeDisplay)")
                }
            }
            .padding(14)
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

// MARK: - Loading skeleton

private struct PackSkeletonView: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                    .frame(height: 96)
                    .opacity(pulse ? 0.45 : 1.0)
            }
        }
        .padding(.top, 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Error state

private struct PackErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Couldn't load packs")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: onRetry) {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
        }
        .padding(.top, 48)
    }
}

// MARK: - Empty state

private struct PackEmptyView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 52))
                .foregroundStyle(.indigo.opacity(0.55))
            Text("No packs yet")
                .font(.title3.bold())
            Text("Available packs will appear here.\nDownload one to study without internet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 60)
    }
}
