//
//  SyllabusMapView.swift
//  SmartTutor
//
//  Interactive syllabus browser.
//  Shows the full JEE / NEET / WBCHSE syllabus organised by subject + chapter.
//  Progress data from GET /progress is overlaid to show completion status.
//  Tapping a topic starts an AI study session for that topic.
//

import Combine
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

    private func overlayProgress(studentId: String) async {
        isLoadingProgress = true
        AppLogger.apiStart(AppLogger.syllabus, endpoint: "GET /progress/\(studentId)")
        do {
            let progress: ProgressResponse = try await apiClient.request(.progress(studentId: studentId))
            // Build topic → accuracy map
            var accuracyMap: [String: Double] = [:]
            for t in progress.topics {
                accuracyMap[t.topic.lowercased()] = t.accuracyPct
            }
            // Overlay onto chapters
            subjects = subjects.map { subj in
                let updatedChapters = subj.chapters.map { chap -> SyllabusChapter in
                    let matchedAcc = accuracyMap[chap.title.lowercased()]
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

// MARK: - Root View

struct SyllabusMapView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = SyllabusMapViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.subjects.isEmpty {
                    ProgressView("Loading syllabus…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    syllabusContent
                }
            }
            .navigationTitle("Syllabus Map")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $vm.searchText, prompt: "Search topics or chapters")
            .toolbar {
                if vm.isLoadingProgress {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ProgressView()
                    }
                }
            }
        }
        .task {
            AppLogger.navigated(to: "SyllabusMapView", from: "Dashboard")
            await vm.load(examTarget: appState.currentProfile?.examTarget.rawValue,
                          studentId: appState.currentProfile?.id)
        }
    }

    private var syllabusContent: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(vm.filteredSubjects) { subject in
                    SubjectAccordion(
                        subject: subject,
                        isExpanded: vm.expandedSubjectId == subject.id,
                        onHeaderTap: { vm.toggleExpand(subject.id) }
                    )
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Subject Accordion

private struct SubjectAccordion: View {
    let subject: SyllabusSubject
    let isExpanded: Bool
    let onHeaderTap: () -> Void

    private var completedCount: Int {
        subject.chapters.filter { ($0.accuracy ?? 0) >= 60 }.count
    }
    private var progressFraction: Double {
        guard !subject.chapters.isEmpty else { return 0 }
        return Double(completedCount) / Double(subject.chapters.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: onHeaderTap) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(subject.color.opacity(0.12))
                            .frame(width: 42, height: 42)
                        Image(systemName: subject.icon)
                            .font(.system(size: 18))
                            .foregroundStyle(subject.color)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(subject.name)
                            .font(.system(size: 16, weight: .bold))
                        HStack(spacing: 6) {
                            Text("\(subject.chapters.count) chapters")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text("\(completedCount) done")
                                .font(.system(size: 12))
                                .foregroundStyle(subject.color)
                        }
                    }

                    Spacer()

                    // Mini progress ring
                    ZStack {
                        Circle()
                            .stroke(subject.color.opacity(0.15), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: progressFraction)
                            .stroke(subject.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(progressFraction * 100))%")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(subject.color)
                    }
                    .frame(width: 36, height: 36)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            // Chapters (animated expand)
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
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        .animation(.spring(response: 0.3), value: isExpanded)
    }
}

// MARK: - Chapter Row

private struct ChapterRow: View {
    let chapter: SyllabusChapter
    let color: Color
    @AppStorage("selectedMainTab")    private var selectedMainTab = 0
    @AppStorage("pendingStudyTopic")  private var pendingStudyTopic = ""

    private var statusIcon: String {
        guard let acc = chapter.accuracy else { return "circle" }
        return acc >= 60 ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }
    private var statusColor: Color {
        guard let acc = chapter.accuracy else { return .secondary }
        return acc >= 60 ? .green : .orange
    }

    var body: some View {
        Button {
            AppLogger.userAction(AppLogger.syllabus,
                                 action: "chapter-tapped",
                                 context: chapter.title)
            pendingStudyTopic = chapter.title
            selectedMainTab = 1
        } label: {
            HStack(spacing: 14) {
                Image(systemName: statusIcon)
                    .font(.system(size: 18))
                    .foregroundStyle(statusColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(chapter.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(chapter.topics.prefix(3).joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let acc = chapter.accuracy {
                    Text("\(Int(acc))%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(statusColor)
                }

                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(color.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}
