//
//  FormulaSheetView.swift
//  SmartTutor
//
//  Quick-revision formula repository for JEE / NEET / WBCHSE.
//  Formulas are displayed with their name, symbolic expression, and
//  optional variable descriptions. Searchable by formula name or symbol.
//  Tapping any formula opens the AI tutor to explain it.
//

import Foundation
import os.log
import SwiftUI

// MARK: - Data Model

struct FormulaCategory: Identifiable {
    let id: String
    let name: String
    let subject: String        // Physics | Chemistry | Mathematics | Biology
    let icon: String
    let color: Color
    let formulas: [Formula]
}

struct Formula: Identifiable {
    let id: String
    let name: String
    let expression: String     // symbolic, e.g. "F = ma"
    let variables: String      // e.g. "F = force (N), m = mass (kg), a = acceleration (m/s²)"
    let tags: [String]         // for search
}

// MARK: - Catalog

private let formulaCategories: [FormulaCategory] = [

    // ─── Physics ───────────────────────────────────────────────────────────────

    FormulaCategory(id: "phy-mechanics", name: "Mechanics", subject: "Physics",
                    icon: "gauge.with.dots.needle.bottom.50percent", color: .blue, formulas: [
        Formula(id: "f-newton2", name: "Newton's Second Law",
                expression: "F = ma",
                variables: "F = net force (N), m = mass (kg), a = acceleration (m/s²)",
                tags: ["force", "newton", "mass", "acceleration"]),
        Formula(id: "f-kinetic-e", name: "Kinetic Energy",
                expression: "KE = ½mv²",
                variables: "m = mass (kg), v = velocity (m/s)",
                tags: ["kinetic", "energy", "velocity"]),
        Formula(id: "f-potential-e", name: "Gravitational PE",
                expression: "PE = mgh",
                variables: "m = mass (kg), g = 9.8 m/s², h = height (m)",
                tags: ["potential", "energy", "gravity", "height"]),
        Formula(id: "f-work", name: "Work Done",
                expression: "W = Fs·cosθ",
                variables: "F = force (N), s = displacement (m), θ = angle",
                tags: ["work", "force", "displacement"]),
        Formula(id: "f-momentum", name: "Momentum",
                expression: "p = mv",
                variables: "p = momentum (kg·m/s), m = mass (kg), v = velocity (m/s)",
                tags: ["momentum", "mass", "velocity"]),
        Formula(id: "f-projectile-range", name: "Projectile Range",
                expression: "R = v₀²sin(2θ)/g",
                variables: "v₀ = initial speed, θ = launch angle, g = 9.8 m/s²",
                tags: ["projectile", "range", "angle"]),
        Formula(id: "f-centripetal", name: "Centripetal Force",
                expression: "F = mv²/r",
                variables: "m = mass, v = speed, r = radius of circle",
                tags: ["centripetal", "circular", "force"]),
        Formula(id: "f-torque", name: "Torque",
                expression: "τ = r × F = rFsinθ",
                variables: "r = moment arm (m), F = force (N), θ = angle",
                tags: ["torque", "rotation", "moment"]),
    ]),

    FormulaCategory(id: "phy-waves", name: "Waves & Optics", subject: "Physics",
                    icon: "waveform", color: .cyan, formulas: [
        Formula(id: "f-wave-speed", name: "Wave Speed",
                expression: "v = fλ",
                variables: "v = speed (m/s), f = frequency (Hz), λ = wavelength (m)",
                tags: ["wave", "speed", "frequency", "wavelength"]),
        Formula(id: "f-snells", name: "Snell's Law",
                expression: "n₁sinθ₁ = n₂sinθ₂",
                variables: "n = refractive index, θ = angle of incidence/refraction",
                tags: ["snell", "refraction", "optics"]),
        Formula(id: "f-mirror", name: "Mirror Equation",
                expression: "1/f = 1/v + 1/u",
                variables: "f = focal length, v = image distance, u = object distance",
                tags: ["mirror", "lens", "focal", "image"]),
        Formula(id: "f-lens-maker", name: "Lens Maker's Equation",
                expression: "1/f = (n−1)(1/R₁ − 1/R₂)",
                variables: "n = refractive index, R₁, R₂ = radii of curvature",
                tags: ["lens", "focal", "refractive"]),
    ]),

    FormulaCategory(id: "phy-electro", name: "Electrostatics & Circuits", subject: "Physics",
                    icon: "bolt.fill", color: .yellow, formulas: [
        Formula(id: "f-coulomb", name: "Coulomb's Law",
                expression: "F = kq₁q₂/r²",
                variables: "k = 9×10⁹ N·m²/C², q = charges (C), r = separation (m)",
                tags: ["coulomb", "charge", "force", "electric"]),
        Formula(id: "f-ohm", name: "Ohm's Law",
                expression: "V = IR",
                variables: "V = voltage (V), I = current (A), R = resistance (Ω)",
                tags: ["ohm", "voltage", "current", "resistance"]),
        Formula(id: "f-power-circuit", name: "Electrical Power",
                expression: "P = VI = I²R = V²/R",
                variables: "P = power (W), V = voltage (V), I = current (A)",
                tags: ["power", "electrical", "voltage", "current"]),
        Formula(id: "f-capacitor", name: "Capacitance",
                expression: "C = Q/V = ε₀A/d",
                variables: "Q = charge (C), V = voltage (V), ε₀ = 8.85×10⁻¹² F/m",
                tags: ["capacitor", "capacitance", "charge"]),
        Formula(id: "f-kirchhoff-v", name: "Kirchhoff's Voltage Law",
                expression: "ΣV = 0 (around any closed loop)",
                variables: "Sum of all potential differences around a closed loop equals zero",
                tags: ["kirchhoff", "kvl", "voltage", "loop"]),
    ]),

    FormulaCategory(id: "phy-thermo", name: "Thermodynamics", subject: "Physics",
                    icon: "thermometer.medium", color: .orange, formulas: [
        Formula(id: "f-ideal-gas", name: "Ideal Gas Law",
                expression: "PV = nRT",
                variables: "P = pressure, V = volume, n = moles, R = 8.314 J/mol·K, T = temp (K)",
                tags: ["ideal", "gas", "pressure", "volume", "temperature"]),
        Formula(id: "f-1st-law", name: "First Law of Thermodynamics",
                expression: "ΔU = Q − W",
                variables: "ΔU = internal energy change, Q = heat added, W = work done by system",
                tags: ["thermodynamics", "internal energy", "heat", "work"]),
        Formula(id: "f-carnot", name: "Carnot Efficiency",
                expression: "η = 1 − T_cold/T_hot",
                variables: "η = efficiency, T in Kelvin",
                tags: ["carnot", "efficiency", "heat engine"]),
    ]),

    // ─── Chemistry ─────────────────────────────────────────────────────────────

    FormulaCategory(id: "chem-physical", name: "Physical Chemistry", subject: "Chemistry",
                    icon: "flask.fill", color: .green, formulas: [
        Formula(id: "f-molarity", name: "Molarity",
                expression: "M = n/V",
                variables: "n = moles of solute, V = volume of solution in litres",
                tags: ["molarity", "concentration", "moles"]),
        Formula(id: "f-nernst", name: "Nernst Equation",
                expression: "E = E° − (RT/nF)lnQ",
                variables: "E° = std. EMF, R = 8.314, T = temp (K), n = electrons, F = 96485 C",
                tags: ["nernst", "electrochemistry", "emf"]),
        Formula(id: "f-arrhenius", name: "Arrhenius Equation",
                expression: "k = Ae^(−Ea/RT)",
                variables: "k = rate constant, A = frequency factor, Eₐ = activation energy (J/mol)",
                tags: ["arrhenius", "kinetics", "rate", "activation energy"]),
        Formula(id: "f-henderson", name: "Henderson–Hasselbalch",
                expression: "pH = pKₐ + log([A⁻]/[HA])",
                variables: "[A⁻] = conjugate base concentration, [HA] = weak acid concentration",
                tags: ["henderson", "hasselbalch", "pH", "buffer"]),
    ]),

    // ─── Mathematics ───────────────────────────────────────────────────────────

    FormulaCategory(id: "math-calculus", name: "Calculus", subject: "Mathematics",
                    icon: "function", color: .indigo, formulas: [
        Formula(id: "f-derivative-power", name: "Power Rule",
                expression: "d/dx(xⁿ) = nxⁿ⁻¹",
                variables: "Derivative of xⁿ with respect to x",
                tags: ["derivative", "power rule", "differentiation"]),
        Formula(id: "f-chain-rule", name: "Chain Rule",
                expression: "d/dx[f(g(x))] = f'(g(x))·g'(x)",
                variables: "Composition of differentiable functions",
                tags: ["chain rule", "composite", "differentiation"]),
        Formula(id: "f-integration-power", name: "Integration Power Rule",
                expression: "∫xⁿ dx = xⁿ⁺¹/(n+1) + C",
                variables: "n ≠ −1, C = constant of integration",
                tags: ["integration", "power rule", "antiderivative"]),
        Formula(id: "f-by-parts", name: "Integration by Parts",
                expression: "∫u dv = uv − ∫v du",
                variables: "u, v are differentiable functions of x",
                tags: ["integration by parts", "product", "integration"]),
    ]),

    FormulaCategory(id: "math-coord", name: "Coordinate Geometry", subject: "Mathematics",
                    icon: "chart.xyaxis.line", color: .purple, formulas: [
        Formula(id: "f-distance", name: "Distance Formula",
                expression: "d = √[(x₂−x₁)² + (y₂−y₁)²]",
                variables: "(x₁,y₁) and (x₂,y₂) are the two points",
                tags: ["distance", "coordinate", "geometry"]),
        Formula(id: "f-midpoint", name: "Midpoint Formula",
                expression: "M = ((x₁+x₂)/2, (y₁+y₂)/2)",
                variables: "(x₁,y₁) and (x₂,y₂) are the endpoint coordinates",
                tags: ["midpoint", "coordinate", "geometry"]),
        Formula(id: "f-circle", name: "Equation of Circle",
                expression: "(x−h)² + (y−k)² = r²",
                variables: "(h,k) = centre, r = radius",
                tags: ["circle", "centre", "radius"]),
        Formula(id: "f-parabola", name: "Standard Parabola",
                expression: "y² = 4ax",
                variables: "a = distance from vertex to focus/directrix",
                tags: ["parabola", "conic", "focus"]),
    ]),

    FormulaCategory(id: "math-trig", name: "Trigonometry", subject: "Mathematics",
                    icon: "triangle.fill", color: .red, formulas: [
        Formula(id: "f-sin2-cos2", name: "Pythagorean Identity",
                expression: "sin²θ + cos²θ = 1",
                variables: "Fundamental identity valid for all θ",
                tags: ["pythagorean", "trigonometry", "identity"]),
        Formula(id: "f-double-angle-sin", name: "Double Angle (sin)",
                expression: "sin(2θ) = 2sinθcosθ",
                variables: "θ = angle",
                tags: ["double angle", "sine", "trigonometry"]),
        Formula(id: "f-double-angle-cos", name: "Double Angle (cos)",
                expression: "cos(2θ) = cos²θ − sin²θ = 1−2sin²θ",
                variables: "θ = angle",
                tags: ["double angle", "cosine", "trigonometry"]),
        Formula(id: "f-sum-to-product", name: "Sum-to-Product",
                expression: "sinA + sinB = 2sin((A+B)/2)cos((A−B)/2)",
                variables: "A, B = angles",
                tags: ["sum to product", "sine", "trigonometry"]),
        Formula(id: "f-sine-rule", name: "Sine Rule",
                expression: "a/sinA = b/sinB = c/sinC = 2R",
                variables: "a,b,c = sides; A,B,C = opposite angles; R = circumradius",
                tags: ["sine rule", "triangle", "geometry"]),
        Formula(id: "f-cosine-rule", name: "Cosine Rule",
                expression: "c² = a² + b² − 2ab·cosC",
                variables: "a,b,c = sides; C = included angle",
                tags: ["cosine rule", "triangle", "geometry"]),
    ]),
]

// MARK: - ViewModel

@MainActor
@Observable final class FormulaSheetViewModel {

    var searchText: String = ""
    private(set) var selectedSubject: String = "All"

    private let allCategories = formulaCategories

    let subjects: [String] = ["All", "Physics", "Chemistry", "Mathematics"]

    var filteredCategories: [FormulaCategory] {
        var cats = allCategories

        // Subject filter
        if selectedSubject != "All" {
            cats = cats.filter { $0.subject == selectedSubject }
        }

        // Text search
        if !searchText.isEmpty {
            cats = cats.map { cat in
                let filtered = cat.formulas.filter { formula in
                    formula.name.localizedCaseInsensitiveContains(searchText) ||
                    formula.expression.localizedCaseInsensitiveContains(searchText) ||
                    formula.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
                }
                return FormulaCategory(id: cat.id, name: cat.name, subject: cat.subject,
                                       icon: cat.icon, color: cat.color, formulas: filtered)
            }.filter { !$0.formulas.isEmpty }
        }

        return cats
    }

    var totalCount: Int { filteredCategories.reduce(0) { $0 + $1.formulas.count } }

    func selectSubject(_ subject: String) {
        AppLogger.userAction(AppLogger.formula, action: "subject-filter", context: subject)
        selectedSubject = subject
    }
}

// MARK: - Root View

struct FormulaSheetView: View {
    @State private var vm = FormulaSheetViewModel()
    @State private var expandedCategory: String? = nil
    @State private var selectedFormula: Formula?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Inline search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search formulas\u{2026}", text: $vm.searchText)
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
                .padding(.vertical, 9)
                .background(Color(UIColor.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 4)

                // Subject filter pills
                subjectFilterRow
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 4)

                if vm.filteredCategories.isEmpty {
                    emptySearchView
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(vm.filteredCategories) { category in
                            FormulaCategoryCard(
                                category: category,
                                isExpanded: expandedCategory == category.id,
                                onHeaderTap: {
                                    AppLogger.userAction(AppLogger.formula,
                                                         action: "category-expand",
                                                         context: category.id)
                                    withAnimation(.spring(response: 0.3)) {
                                        expandedCategory = expandedCategory == category.id ? nil : category.id
                                    }
                                },
                                onFormulaTap: { formula in
                                    AppLogger.userAction(AppLogger.formula,
                                                         action: "formula-tapped",
                                                         context: formula.id)
                                    selectedFormula = formula
                                }
                            )
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle("Formula Sheets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(
            LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing),
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)

        .sheet(item: $selectedFormula) { formula in
            FormulaDetailSheet(formula: formula)
        }
        .onAppear {
            AppLogger.navigated(to: "FormulaSheetView", from: "Dashboard")
        }
    }

    // MARK: Subject Filter

    private var subjectFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.subjects, id: \.self) { subject in
                    Button(subject) { vm.selectSubject(subject) }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(vm.selectedSubject == subject ? Color.indigo : Color(UIColor.systemGray5))
                        .foregroundStyle(vm.selectedSubject == subject ? .white : .primary)
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: Empty search

    private var emptySearchView: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))
                .padding(.top, 60)
            Text("No formulas found for \"\(vm.searchText)\"")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Category Card

private struct FormulaCategoryCard: View {
    let category: FormulaCategory
    let isExpanded: Bool
    let onHeaderTap: () -> Void
    let onFormulaTap: (Formula) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: onHeaderTap) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(category.color.opacity(0.12))
                            .frame(width: 38, height: 38)
                        Image(systemName: category.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(category.color)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name)
                            .font(.system(size: 15, weight: .bold))
                        Text("\(category.subject) · \(category.formulas.count) formulas")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            // Formula rows
            if isExpanded {
                Divider().padding(.horizontal, 14)
                ForEach(Array(category.formulas.enumerated()), id: \.element.id) { idx, formula in
                    FormulaRow(formula: formula, color: category.color, onTap: { onFormulaTap(formula) })
                    if idx < category.formulas.count - 1 {
                        Divider().padding(.leading, 48)
                    }
                }
            }
        }
        .background(Color(UIColor.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

// MARK: - Formula Row

private struct FormulaRow: View {
    let formula: Formula
    let color: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Expression badge
                Text(formula.expression)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(minWidth: 80, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(formula.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(formula.variables)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Formula Detail Sheet

struct FormulaDetailSheet: View {
    let formula: Formula
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedMainTab")   private var selectedMainTab = 0
    @AppStorage("pendingStudyTopic") private var pendingStudyTopic = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                // Formula expression (large)
                VStack(spacing: 8) {
                    Text(formula.expression)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(.indigo)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .background(Color.indigo.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }

                // Variables
                VStack(alignment: .leading, spacing: 8) {
                    Label("Variables", systemImage: "square.and.pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(formula.variables)
                        .font(.system(size: 15))
                }

                // Tags
                if !formula.tags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Related topics", systemImage: "tag")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                        FlowLayout(formula.tags)
                    }
                }

                Spacer()

                // Ask AI
                Button {
                    AppLogger.userAction(AppLogger.formula,
                                         action: "ask-ai-about-formula",
                                         context: formula.id)
                    pendingStudyTopic = "Explain the formula \(formula.name): \(formula.expression). \(formula.variables)"
                    dismiss()
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        selectedMainTab = 1
                    }
                } label: {
                    Label("Ask AI to Explain", systemImage: "brain.head.profile")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.indigo)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .navigationTitle(formula.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - FlowLayout (tag chips)

private struct FlowLayout: View {
    let tags: [String]

    init(_ tags: [String]) { self.tags = tags }

    var body: some View {
        // Simple wrapping layout using alignmentGuide
        GeometryReader { geo in
            self.generateContent(in: geo)
        }
    }

    private func generateContent(in g: GeometryProxy) -> some View {
        var width: CGFloat  = 0
        var height: CGFloat = 0
        return ZStack(alignment: .topLeading) {
            ForEach(tags.indices, id: \.self) { i in
                tagChip(tags[i])
                    .padding([.trailing, .bottom], 6)
                    .alignmentGuide(.leading) { d in
                        if abs(width - d.width) > g.size.width {
                            width = 0
                            height -= d.height + 6
                        }
                        let result = width
                        if i == tags.count - 1 { width = 0 }
                        else { width -= d.width + 6 }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if i == tags.count - 1 { height = 0 }
                        return result
                    }
            }
        }
    }

    private func tagChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.indigo)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.indigo.opacity(0.1))
            .clipShape(Capsule())
    }
}
