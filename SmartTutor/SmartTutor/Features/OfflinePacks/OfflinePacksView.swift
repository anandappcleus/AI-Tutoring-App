//
//  OfflinePacksView.swift
//  SmartTutor
//
//  Converted from OfflinePacksScreen.tsx
//  Download management with simulated progress, storage meter.
//

import SwiftUI

struct OfflinePacksView: View {

    struct OfflinePack: Identifiable {
        let id: String
        let subject: String
        let topic: String
        let questions: Int
        let sizeMB: Int
        var downloaded: Bool
        let icon: String
        let color: Color
    }

    @State private var packs: [OfflinePack] = [
        OfflinePack(id: "1", subject: "Physics",   topic: "Mechanics – Laws of Motion",         questions: 50, sizeMB: 12, downloaded: true,  icon: "⚡", color: .blue),
        OfflinePack(id: "2", subject: "Chemistry",  topic: "Organic Chemistry – Reactions",      questions: 45, sizeMB: 10, downloaded: false, icon: "🧪", color: .green),
        OfflinePack(id: "3", subject: "Maths",     topic: "Calculus – Integration",              questions: 60, sizeMB:  8, downloaded: true,  icon: "📐", color: .purple),
        OfflinePack(id: "4", subject: "Physics",   topic: "Electromagnetism",                    questions: 40, sizeMB: 11, downloaded: false, icon: "⚡", color: .blue),
        OfflinePack(id: "5", subject: "Chemistry",  topic: "Physical Chemistry – Thermodynamics",questions: 38, sizeMB:  9, downloaded: false, icon: "🧪", color: .green),
        OfflinePack(id: "6", subject: "Maths",     topic: "Algebra – Quadratic Equations",       questions: 55, sizeMB:  7, downloaded: false, icon: "📐", color: .purple),
    ]

    @State private var downloadingId: String? = nil
    @State private var downloadProgress: Double = 0
    @State private var downloadTimer: Timer? = nil

    private var downloadedPacks: [OfflinePack] { packs.filter(\.downloaded) }
    private var availablePacks:  [OfflinePack] { packs.filter { !$0.downloaded } }
    private var usedMB: Int { downloadedPacks.reduce(0) { $0 + $1.sizeMB } }
    private let totalMB = 500

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Offline Packs")
                                .font(.system(size: 24, weight: .bold))
                            Text("Study without internet")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.85))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(downloadedPacks.count)")
                                .font(.system(size: 26, weight: .bold))
                            Text("Downloaded")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }

                    // Storage bar
                    HStack(spacing: 12) {
                        Image(systemName: "internaldrive.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Storage Used")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("\(usedMB) / \(totalMB) MB")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            LinearProgressBar(
                                value: Double(usedMB) / Double(totalMB),
                                foreground: .white.opacity(0.9),
                                background: .white.opacity(0.2)
                            )
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
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

                VStack(spacing: 24) {
                    // Downloaded section
                    if !downloadedPacks.isEmpty {
                        PacksSection(
                            title: "Downloaded (\(downloadedPacks.count))",
                            icon: "checkmark.circle.fill",
                            iconColor: .green
                        ) {
                            ForEach(downloadedPacks) { pack in
                                DownloadedPackCard(pack: pack) {
                                    if let idx = packs.firstIndex(where: { $0.id == pack.id }) {
                                        packs[idx].downloaded = false
                                    }
                                }
                            }
                        }
                    }

                    // Available section
                    if !availablePacks.isEmpty {
                        PacksSection(
                            title: "Available to Download (\(availablePacks.count))",
                            icon: "arrow.down.circle.fill",
                            iconColor: .blue
                        ) {
                            ForEach(availablePacks) { pack in
                                AvailablePackCard(
                                    pack: pack,
                                    isDownloading: downloadingId == pack.id,
                                    progress: downloadingId == pack.id ? downloadProgress : 0
                                ) {
                                    startDownload(packId: pack.id)
                                }
                            }
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
        .navigationTitle("Offline Packs")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Download logic

    private func startDownload(packId: String) {
        guard downloadingId == nil else { return }
        downloadingId = packId
        downloadProgress = 0

        downloadTimer?.invalidate()
        downloadTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
            downloadProgress += 0.1
            if downloadProgress >= 1.0 {
                timer.invalidate()
                downloadTimer = nil
                if let idx = packs.firstIndex(where: { $0.id == packId }) {
                    packs[idx].downloaded = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    downloadingId = nil
                    downloadProgress = 0
                }
            }
        }
    }
}

// MARK: - Section wrapper

private struct PacksSection<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(iconColor)

            VStack(spacing: 12) {
                content
            }
        }
    }
}

// MARK: - Downloaded Pack Card

private struct DownloadedPackCard: View {
    let pack: OfflinePacksView.OfflinePack
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(pack.color.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Text(pack.icon).font(.system(size: 24))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(pack.topic)
                        .font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 8) {
                        Label("\(pack.questions) questions", systemImage: "book")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("•").foregroundColor(.secondary)
                        Text("\(pack.sizeMB) MB")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 15))
                        .foregroundColor(.red)
                        .frame(width: 36, height: 36)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            Button {
                // Practice this pack
            } label: {
                Text("Practice Now")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.indigo)
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
    let pack: OfflinePacksView.OfflinePack
    let isDownloading: Bool
    let progress: Double
    let onDownload: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(pack.color.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Text(pack.icon).font(.system(size: 24))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(pack.topic)
                        .font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 8) {
                        Label("\(pack.questions) questions", systemImage: "book")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("•").foregroundColor(.secondary)
                        Text("\(pack.sizeMB) MB")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }

            if isDownloading {
                VStack(spacing: 6) {
                    HStack {
                        Text("Downloading...")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(.indigo)
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
                        .foregroundColor(.white)
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
