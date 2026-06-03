//
//  SyllabusMapView.swift
//  SmartTutor
//
//  Interactive syllabus browser.
//  Shows the full JEE / NEET / WBCHSE syllabus organised by subject + chapter.
//  Progress data from GET /progress is overlaid to show completion status.
//  Tapping a topic starts an AI study session for that topic.
//

import Foundation
import os.log
import SwiftUI

// MARK: - Data Model

struct SyllabusSubject: Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: Color
    let chapters: [SyllabusChapter]
}

struct SyllabusChapter: Identifiable {
    let id: String
    let title: String
    let topics: [String]
    var accuracy: Double? = nil   // nil = not attempted yet
}

// MARK: - Static Syllabus Catalog

private let jeeSyllabus: [SyllabusSubject] = [
    SyllabusSubject(id: "jee-phy", name: "Physics", icon: "bolt.fill", color: .blue, chapters: [
        SyllabusChapter(id: "jee-phy-1",  title: "Units & Measurement",       topics: ["SI units", "Dimensional analysis", "Significant figures"]),
        SyllabusChapter(id: "jee-phy-2",  title: "Kinematics",                topics: ["Motion in 1D", "Motion in 2D", "Projectile motion", "Relative motion"]),
        SyllabusChapter(id: "jee-phy-3",  title: "Laws of Motion",            topics: ["Newton's laws", "Friction", "Circular motion"]),
        SyllabusChapter(id: "jee-phy-4",  title: "Work, Energy & Power",      topics: ["Work-energy theorem", "Conservative forces", "Power"]),
        SyllabusChapter(id: "jee-phy-5",  title: "Rotational Motion",         topics: ["Torque", "Moment of inertia", "Angular momentum"]),
        SyllabusChapter(id: "jee-phy-6",  title: "Gravitation",               topics: ["Newton's law of gravitation", "Orbital velocity", "Escape velocity"]),
        SyllabusChapter(id: "jee-phy-7",  title: "Thermodynamics",            topics: ["Laws of thermodynamics", "Carnot engine", "Entropy"]),
        SyllabusChapter(id: "jee-phy-8",  title: "Waves & Oscillations",      topics: ["SHM", "Wave equation", "Doppler effect"]),
        SyllabusChapter(id: "jee-phy-9",  title: "Electrostatics",            topics: ["Coulomb's law", "Electric field", "Potential", "Capacitors"]),
        SyllabusChapter(id: "jee-phy-10", title: "Current Electricity",       topics: ["Ohm's law", "Kirchhoff's laws", "Wheatstone bridge"]),
        SyllabusChapter(id: "jee-phy-11", title: "Magnetism",                 topics: ["Biot-Savart law", "Ampere's law", "Magnetic force"]),
        SyllabusChapter(id: "jee-phy-12", title: "Electromagnetic Induction", topics: ["Faraday's law", "Lenz's law", "Self and mutual inductance"]),
        SyllabusChapter(id: "jee-phy-13", title: "Optics",                    topics: ["Reflection", "Refraction", "Lenses", "Wave optics"]),
        SyllabusChapter(id: "jee-phy-14", title: "Modern Physics",            topics: ["Photoelectric effect", "Atomic models", "Nuclear physics"]),
    ]),
    SyllabusSubject(id: "jee-chem", name: "Chemistry", icon: "flask.fill", color: .green, chapters: [
        SyllabusChapter(id: "jee-chem-1",  title: "Mole Concept",             topics: ["Avogadro's number", "Stoichiometry", "Concentration terms"]),
        SyllabusChapter(id: "jee-chem-2",  title: "Atomic Structure",         topics: ["Quantum numbers", "Orbitals", "Electronic configuration"]),
        SyllabusChapter(id: "jee-chem-3",  title: "Periodic Table",           topics: ["Trends", "Ionisation energy", "Electronegativity"]),
        SyllabusChapter(id: "jee-chem-4",  title: "Chemical Bonding",         topics: ["VSEPR", "Hybridisation", "Molecular orbital theory"]),
        SyllabusChapter(id: "jee-chem-5",  title: "Thermochemistry",          topics: ["Enthalpy", "Hess's law", "Bond energies"]),
        SyllabusChapter(id: "jee-chem-6",  title: "Equilibrium",              topics: ["Le Chatelier's principle", "Kp and Kc", "Solubility product"]),
        SyllabusChapter(id: "jee-chem-7",  title: "Electrochemistry",         topics: ["Galvanic cells", "Electrolysis", "Nernst equation"]),
        SyllabusChapter(id: "jee-chem-8",  title: "Organic Chemistry — I",    topics: ["IUPAC nomenclature", "Stereoisomerism", "Reaction mechanisms"]),
        SyllabusChapter(id: "jee-chem-9",  title: "Organic Chemistry — II",   topics: ["Alcohols", "Aldehydes & Ketones", "Carboxylic acids"]),
        SyllabusChapter(id: "jee-chem-10", title: "Coordination Compounds",   topics: ["IUPAC naming", "Crystal field theory", "Isomerism"]),
    ]),
    SyllabusSubject(id: "jee-math", name: "Mathematics", icon: "function", color: .indigo, chapters: [
        SyllabusChapter(id: "jee-math-1",  title: "Sets & Relations",         topics: ["Set operations", "Relations", "Functions"]),
        SyllabusChapter(id: "jee-math-2",  title: "Complex Numbers",          topics: ["Argand plane", "Polar form", "De Moivre's theorem"]),
        SyllabusChapter(id: "jee-math-3",  title: "Quadratic Equations",      topics: ["Roots", "Discriminant", "Inequalities"]),
        SyllabusChapter(id: "jee-math-4",  title: "Matrices & Determinants",  topics: ["Matrix operations", "Inverse", "Cramer's rule"]),
        SyllabusChapter(id: "jee-math-5",  title: "Permutation & Combination",topics: ["nPr", "nCr", "Binomial theorem"]),
        SyllabusChapter(id: "jee-math-6",  title: "Sequences & Series",       topics: ["AP", "GP", "HP", "Sum formulas"]),
        SyllabusChapter(id: "jee-math-7",  title: "Differential Calculus",    topics: ["Limits", "Continuity", "Differentiation", "Applications"]),
        SyllabusChapter(id: "jee-math-8",  title: "Integral Calculus",        topics: ["Indefinite integrals", "Definite integrals", "Area"]),
        SyllabusChapter(id: "jee-math-9",  title: "Coordinate Geometry",      topics: ["Straight lines", "Circles", "Conics"]),
        SyllabusChapter(id: "jee-math-10", title: "3D Geometry & Vectors",    topics: ["Dot product", "Cross product", "3D lines and planes"]),
        SyllabusChapter(id: "jee-math-11", title: "Probability & Statistics",  topics: ["Bayes theorem", "Distributions", "Mean/variance"]),
        SyllabusChapter(id: "jee-math-12", title: "Trigonometry",             topics: ["Identities", "Inverse trig", "Heights & distances"]),
    ]),
]

private let neetSyllabus: [SyllabusSubject] = [
    SyllabusSubject(id: "neet-phy", name: "Physics", icon: "bolt.fill", color: .blue, chapters: jeeSyllabus[0].chapters.prefix(8).map { $0 }),
    SyllabusSubject(id: "neet-chem", name: "Chemistry", icon: "flask.fill", color: .green, chapters: jeeSyllabus[1].chapters),
    SyllabusSubject(id: "neet-bio", name: "Biology", icon: "leaf.fill", color: .teal, chapters: [
        SyllabusChapter(id: "neet-bio-1", title: "Cell Biology",              topics: ["Cell structure", "Cell division", "Biomolecules"]),
        SyllabusChapter(id: "neet-bio-2", title: "Genetics",                  topics: ["Mendel's laws", "Chromosomal inheritance", "Mutations"]),
        SyllabusChapter(id: "neet-bio-3", title: "Human Physiology",          topics: ["Digestive system", "Circulatory system", "Nervous system"]),
        SyllabusChapter(id: "neet-bio-4", title: "Plant Physiology",          topics: ["Photosynthesis", "Respiration", "Hormones"]),
        SyllabusChapter(id: "neet-bio-5", title: "Ecology",                   topics: ["Ecosystems", "Biodiversity", "Environmental issues"]),
        SyllabusChapter(id: "neet-bio-6", title: "Evolution",                 topics: ["Darwin's theory", "Evidence", "Human evolution"]),
        SyllabusChapter(id: "neet-bio-7", title: "Biotechnology",             topics: ["Recombinant DNA", "PCR", "Applications"]),
    ]),
]

private let wbchseSyllabus: [SyllabusSubject] = [
    SyllabusSubject(id: "wb-phy", name: "Physics", icon: "bolt.fill", color: .blue, chapters: jeeSyllabus[0].chapters.prefix(10).map { $0 }),
    SyllabusSubject(id: "wb-chem", name: "Chemistry", icon: "flask.fill", color: .green, chapters: jeeSyllabus[1].chapters.prefix(8).map { $0 }),
    SyllabusSubject(id: "wb-math", name: "Mathematics", icon: "function", color: .indigo, chapters: jeeSyllabus[2].chapters),
    SyllabusSubject(id: "wb-bio", name: "Biology", icon: "leaf.fill", color: .teal, chapters: neetSyllabus[2].chapters.prefix(5).map { $0 }),
]

// MARK: - ViewModel

@MainActor
@Observable final class SyllabusMapViewModel {

    private(set) var subjects: [SyllabusSubject] = []
    private(set) var isLoadingProgress: Bool = false
    private(set) var expandedSubjectId: String? = nil
    var searchText: String = ""

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    var filteredSubjects: [SyllabusSubject] {
        guard !searchText.isEmpty else { return subjects }
        return subjects.map { subject in
            let matchedChapters = subject.chapters.filter { chapter in
                chapter.title.localizedCaseInsensitiveContains(searchText) ||
                chapter.topics.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
            return SyllabusSubject(id: subject.id, name: subject.name,
                                   icon: subject.icon, color: subject.color,
                                   chapters: matchedChapters)
        }.filter { !$0.chapters.isEmpty }
    }

    func load(examTarget: String?, studentId: String?) async {
        // Load correct syllabus
        switch examTarget {
        case "NEET":    subjects = neetSyllabus
        case "WBCHSE":  subjects = wbchseSyllabus
        default:        subjects = jeeSyllabus          // JEE default
        }
        AppLogger.syllabus.info("SyllabusMapViewModel: loaded  exam=\(examTarget ?? "JEE")  subjects=\(self.subjects.count)")

        // Overlay progress if student ID is available
        guard let sid = studentId else { return }
        await overlayProgress(studentId: sid)
    }

    /// Normalise a topic/chapter name for fuzzy matching.
    /// Converts "Work, Energy & Power" and "Work, Energy and Power" to the same key.
    private func normalizedKey(_ s: String) -> String {
        s.lowercased()
         .replacingOccurrences(of: " & ", with: " and ")
         .replacingOccurrences(of: " \u{2014} ", with: " - ")   // em-dash (Organic Chemistry — I)
    }

    private func overlayProgress(studentId: String) async {
        isLoadingProgress = true
        AppLogger.apiStart(AppLogger.syllabus, endpoint: "GET /progress/\(studentId)")
        do {
            let progress: ProgressResponse = try await apiClient.request(.progress(studentId: studentId))
            // Build topic → accuracy map with normalised keys so that
            // "&" vs "and" differences between backend and iOS titles don't cause misses.
            var accuracyMap: [String: Double] = [:]
            for t in progress.topics {
                accuracyMap[normalizedKey(t.topic)] = t.accuracyPct
            }
            // Overlay onto chapters
            subjects = subjects.map { subj in
                let updatedChapters = subj.chapters.map { chap -> SyllabusChapter in
                    let matchedAcc = accuracyMap[normalizedKey(chap.title)]
                    var updated = chap
                    updated.accuracy = matchedAcc
                    return updated
                }
                return SyllabusSubject(id: subj.id, name: subj.name,
                                       icon: subj.icon, color: subj.color,
                                       chapters: updatedChapters)
            }
            AppLogger.apiSuccess(AppLogger.syllabus,
                                 endpoint: "GET /progress/\(studentId)",
                                 detail: "topics=\(progress.topics.count)")
        } catch {
            AppLogger.apiFailure(AppLogger.syllabus,
                                 endpoint: "GET /progress/\(studentId)", error: error)
        }
        isLoadingProgress = false
    }

    func toggleExpand(_ subjectId: String) {
        AppLogger.userAction(AppLogger.syllabus, action: "toggle-subject", context: subjectId)
        expandedSubjectId = expandedSubjectId == subjectId ? nil : subjectId
    }
}

// MARK: - Chapter Status

private enum ChapterStatus: String, CaseIterable, Identifiable {
    case notStarted = "Not Started"
    case needsWork  = "Needs Work"
    case mastered   = "Mastered"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .notStarted: return "circle.dashed"
        case .needsWork:  return "exclamationmark.circle.fill"
        case .mastered:   return "checkmark.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .notStarted: return Color(UIColor.secondaryLabel)
        case .needsWork:  return .orange
        case .mastered:   return .green
        }
    }
    func matches(_ chapter: SyllabusChapter) -> Bool {
        switch self {
        case .notStarted: return chapter.accuracy == nil
        case .needsWork:  return chapter.accuracy != nil && (chapter.accuracy ?? 0) < 60
        case .mastered:   return (chapter.accuracy ?? 0) >= 60
        }
    }
}

// MARK: - Root View

struct SyllabusMapView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = SyllabusMapViewModel()
    @State private var selectedStatus: ChapterStatus? = nil

    var body: some View {
        Group {
            if vm.subjects.isEmpty {
                ProgressView("Loading syllabus…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                syllabusContent
            }
        }
        .navigationTitle("Syllabus Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(
            LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing),
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if vm.isLoadingProgress {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ProgressView().tint(.white)
                }
            }
        }
        .task {
            AppLogger.navigated(to: "SyllabusMapView", from: "Dashboard")
            await vm.load(examTarget: appState.currentProfile?.examTarget.rawValue,
                          studentId: appState.currentProfile?.id)
        }
    }

    // Subjects filtered by both text search and status chip
    private var displayedSubjects: [SyllabusSubject] {
        let textFiltered = vm.filteredSubjects
        guard let status = selectedStatus else { return textFiltered }
        return textFiltered.map { subj in
            SyllabusSubject(
                id: subj.id, name: subj.name,
                icon: subj.icon, color: subj.color,
                chapters: subj.chapters.filter { status.matches($0) }
            )
        }.filter { !$0.chapters.isEmpty }
    }

    // Overall stats across all (unfiltered) subjects
    private var totalChapters: Int    { vm.subjects.reduce(0) { $0 + $1.chapters.count } }
    private var attemptedChapters: Int { vm.subjects.flatMap(\.chapters).filter { $0.accuracy != nil }.count }
    private var masteredChapters: Int  { vm.subjects.flatMap(\.chapters).filter { ($0.accuracy ?? 0) >= 60 }.count }
    private var overallAccuracy: Double? {
        let values = vm.subjects.flatMap(\.chapters).compactMap(\.accuracy)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    @ViewBuilder
    private var syllabusContent: some View {
        ScrollView {
            VStack(spacing: 0) {

                // ── Stats hero card ──
                SyllabusStatsCard(
                    totalChapters:    totalChapters,
                    masteredChapters: masteredChapters,
                    attemptedChapters: attemptedChapters,
                    overallAccuracy:  overallAccuracy
                )
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 12)

                // ── Search bar ──
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search topics or chapters", text: $vm.searchText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !vm.searchText.isEmpty {
                        Button { vm.searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(UIColor.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

                // ── Status filter chips ──
                StatusFilterBar(selected: $selectedStatus)
                    .padding(.bottom, 14)

                // ── Subject list or empty state ──
                if displayedSubjects.isEmpty {
                    SyllabusEmptyState(
                        hasFilter: selectedStatus != nil || !vm.searchText.isEmpty
                    )
                    .padding(.top, 48)
                    .padding(.bottom, 32)
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(displayedSubjects) { subject in
                            SubjectAccordion(
                                subject: subject,
                                isExpanded: vm.expandedSubjectId == subject.id,
                                onHeaderTap: { vm.toggleExpand(subject.id) }
                            )
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
}

// MARK: - Stats Hero Card

private struct SyllabusStatsCard: View {
    let totalChapters: Int
    let masteredChapters: Int
    let attemptedChapters: Int
    let overallAccuracy: Double?

    private var coverageFraction: Double {
        guard totalChapters > 0 else { return 0 }
        return Double(attemptedChapters) / Double(totalChapters)
    }
    private var masteryFraction: Double {
        guard totalChapters > 0 else { return 0 }
        return Double(masteredChapters) / Double(totalChapters)
    }

    var body: some View {
        HStack(spacing: 20) {
            // Dual-ring gauge: outer = attempted, inner = mastered
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 5)
                    .frame(width: 72, height: 72)
                Circle()
                    .trim(from: 0, to: coverageFraction)
                    .stroke(Color.white.opacity(0.6),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 72, height: 72)
                    .animation(.spring(response: 0.7), value: coverageFraction)

                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 5)
                    .frame(width: 50, height: 50)
                Circle()
                    .trim(from: 0, to: masteryFraction)
                    .stroke(Color.green.opacity(0.9),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 50, height: 50)
                    .animation(.spring(response: 0.7), value: masteryFraction)

                VStack(spacing: 1) {
                    Text("\(Int(masteryFraction * 100))%")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(.white)
                    Text("done")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .textCase(.uppercase)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Your Progress")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))

                HStack(spacing: 16) {
                    SyllabusStatChip(value: "\(masteredChapters)",
                                     label: "Mastered",     color: .green)
                    SyllabusStatChip(value: "\(attemptedChapters - masteredChapters)",
                                     label: "Needs Work",   color: .orange)
                    SyllabusStatChip(value: "\(totalChapters - attemptedChapters)",
                                     label: "Not Started",  color: .white.opacity(0.5))
                }

                if let acc = overallAccuracy {
                    HStack(spacing: 6) {
                        Text("Avg accuracy")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("\(Int(acc))%")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            LinearGradient(
                colors: [Color.indigo, Color.purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .indigo.opacity(0.35), radius: 12, y: 5)
    }
}

private struct SyllabusStatChip: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
    }
}

// MARK: - Status Filter Bar

private struct StatusFilterBar: View {
    @Binding var selected: ChapterStatus?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" chip
                let isAllSelected = selected == nil
                Button { selected = nil } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 11, weight: .semibold))
                        Text("All")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(isAllSelected ? .white : Color(UIColor.label))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        isAllSelected
                            ? AnyShapeStyle(LinearGradient(
                                colors: [.indigo, .purple],
                                startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Color(UIColor.systemGray5))
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                ForEach(ChapterStatus.allCases) { status in
                    let isSelected = selected == status
                    Button { selected = isSelected ? nil : status } label: {
                        HStack(spacing: 5) {
                            Image(systemName: status.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(status.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(isSelected ? .white : status.color)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            isSelected
                                ? AnyShapeStyle(status.color)
                                : AnyShapeStyle(status.color.opacity(0.1))
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Empty State

private struct SyllabusEmptyState: View {
    let hasFilter: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: hasFilter ? "line.3.horizontal.decrease.circle" : "books.vertical")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
            Text(hasFilter ? "No chapters match" : "No syllabus loaded")
                .font(.system(size: 17, weight: .semibold))
            Text(hasFilter
                 ? "Try a different filter or clear your search"
                 : "Check your connection and try again")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Subject Accordion

private struct SubjectAccordion: View {
    let subject: SyllabusSubject
    let isExpanded: Bool
    let onHeaderTap: () -> Void

    private var masteredCount: Int {
        subject.chapters.filter { ($0.accuracy ?? 0) >= 60 }.count
    }
    private var progressFraction: Double {
        guard !subject.chapters.isEmpty else { return 0 }
        return Double(masteredCount) / Double(subject.chapters.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Top subject-colour accent strip ──
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [subject.color, subject.color.opacity(0.55)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 4)

            // ── Header ──
            Button(action: onHeaderTap) {
                HStack(spacing: 14) {
                    // Subject icon in gradient circle
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [subject.color.opacity(0.18), subject.color.opacity(0.07)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                        Image(systemName: subject.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(subject.color)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(subject.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(UIColor.label))

                        HStack(spacing: 6) {
                            Text("\(subject.chapters.count) chapters")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text("·")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text("\(masteredCount) mastered")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(subject.color)
                        }

                        // Horizontal progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(subject.color.opacity(0.12))
                                    .frame(height: 5)
                                Capsule()
                                    .fill(subject.color)
                                    .frame(width: geo.size.width * progressFraction, height: 5)
                                    .animation(.spring(response: 0.5), value: progressFraction)
                            }
                        }
                        .frame(height: 5)
                    }

                    Spacer()

                    VStack(spacing: 4) {
                        Text("\(Int(progressFraction * 100))%")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(subject.color)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            // ── Chapters (animated expand) ──
            if isExpanded {
                Divider().padding(.horizontal, 16)
                ForEach(Array(subject.chapters.enumerated()), id: \.element.id) { idx, chapter in
                    ChapterRow(chapter: chapter, color: subject.color)
                    if idx < subject.chapters.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
        }
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        .animation(.spring(response: 0.3), value: isExpanded)
    }
}

// MARK: - Chapter Row

private struct ChapterRow: View {
    let chapter: SyllabusChapter
    let color: Color
    @AppStorage("selectedMainTab")    private var selectedMainTab = 0
    @AppStorage("pendingStudyTopic")  private var pendingStudyTopic = ""

    private var status: ChapterStatus {
        guard let acc = chapter.accuracy else { return .notStarted }
        return acc >= 60 ? .mastered : .needsWork
    }

    var body: some View {
        Button {
            AppLogger.userAction(AppLogger.syllabus,
                                 action: "chapter-tapped",
                                 context: chapter.title)
            pendingStudyTopic = "Explain \(chapter.title) with key concepts, a worked example, and 2 practice problems"
            selectedMainTab = 1
        } label: {
            HStack(spacing: 0) {
                // Left status-colour stripe
                Capsule()
                    .fill(status.color)
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .padding(.leading, 14)

                HStack(spacing: 12) {
                    Image(systemName: status.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(status.color)
                        .frame(width: 24)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(chapter.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(UIColor.label))
                        Text(chapter.topics.prefix(3).joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if let acc = chapter.accuracy {
                        VStack(spacing: 2) {
                            Text("\(Int(acc))%")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(status.color)
                            Text("accuracy")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Study →")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(color.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chapter.title). \(chapter.accuracy.map { "Accuracy \(Int($0)) percent" } ?? "Not started"). Tap to study.")
    }
}
