//
//  OfflinePacksView.swift
//  SmartTutor
//
//  Sprint 8 — Wired to OfflinePacksViewModel + Core Data.
//  Downloads real packs from GET /packs and caches questions locally.
//

import SwiftUI

struct OfflinePacksView: View {

    @State private var vm = OfflinePacksViewModel()
    @Environment(AppState.self) private var appState
    @State private var practiceItem: PackListItem?

    private let totalKB = 500_000   // 500 MB storage cap for display

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // ── Header ────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Offline Packs")
                            .font(.system(size: 24, weight: .bold))
                        Text("Study without internet")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }

                    // Storage bar
                    HStack(spacing: 12) {
                        Image(systemName: "internaldrive.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Storage Used")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                                Text(storageLabel)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            LinearProgressBar(
                                value: Double(vm.usedKB) / Double(totalKB),
                                foreground: .white.opacity(0.9),
                                background: .white.opacity(0.2)
                            )
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
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

                // ── Content ───────────────────────────────────────────
                VStack(spacing: 24) {
                    if vm.isLoading {
                        ProgressView("Loading packs…")
                            .padding(.top, 40)
                    } else if let error = vm.errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Retry") {
                                Task { await vm.loadPacks() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 40)

                    } else {
                        // Downloaded packs
                        if !vm.downloadedPacks.isEmpty {
                            PacksSectionView(
                                title: "Downloaded (\(vm.downloadedPacks.count))",
                                icon: "checkmark.circle.fill",
                                iconColor: .green
                            ) {
                                ForEach(vm.downloadedPacks) { pack in
                                    DownloadedPackCard(pack: pack) {
                                        vm.deletePack(pack)
                                    } onPractice: {
                                        practiceItem = pack
                                    }
                                }
                            }
                        }

                        // Available packs
                        if !vm.availablePacks.isEmpty {
                            PacksSectionView(
                                title: "Available to Download (\(vm.availablePacks.count))",
                                icon: "arrow.down.circle.fill",
                                iconColor: .blue
                            ) {
                                ForEach(vm.availablePacks) { pack in
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

                        // Empty state
                        if vm.packs.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "tray.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.secondary)
                                Text("No packs available")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 40)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, -16)
                .padding(.bottom, 32)
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            AppLogger.navigated(to: "OfflinePacksView")
            await vm.loadPacks()
        }
        .sheet(item: $practiceItem) { pack in
            OfflinePracticeView(pack: pack)
        }
    }

    private var storageLabel: String {
        let usedMB = Double(vm.usedKB) / 1000.0
        return String(format: "%.1f MB / 500 MB", usedMB)
    }
}

// MARK: - Section wrapper

private struct PacksSectionView<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(iconColor)
            VStack(spacing: 12) { content }
        }
    }
}

// MARK: - Downloaded Pack Card

private struct DownloadedPackCard: View {
    let pack: PackListItem
    let onDelete: () -> Void
    let onPractice: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(pack.subjectColor.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: pack.iconName)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(pack.subjectColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(pack.topic)
                        .font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 8) {
                        Label("\(pack.questionCount) questions", systemImage: "book")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("•").foregroundStyle(.secondary)
                        Text(pack.sizeDisplay)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 15))
                        .foregroundStyle(.red)
                        .frame(width: 36, height: 36)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            Button {
                onPractice()
            } label: {
                Text("Practice Now")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color.indigo.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}

// MARK: - Available Pack Card

private struct AvailablePackCard: View {
    let pack: PackListItem
    let isDownloading: Bool
    let progress: Double
    let onDownload: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(pack.subjectColor.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: pack.iconName)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(pack.subjectColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(pack.topic)
                        .font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 8) {
                        Label("\(pack.questionCount) questions", systemImage: "book")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("•").foregroundStyle(.secondary)
                        Text(pack.sizeDisplay)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if isDownloading {
                VStack(spacing: 6) {
                    HStack {
                        Text("Downloading…")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.indigo)
                    }
                    LinearProgressBar(
                        value: progress,
                        foreground: .indigo,
                        background: Color.gray.opacity(0.15),
                        useGradient: true,
                        gradientColors: [.indigo, .purple]
                    )
                }
            } else {
                Button(action: onDownload) {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color.indigo)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(16)
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}
