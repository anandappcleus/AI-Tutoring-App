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

    // Subject colour map (consistent with rest of app)
    private func subjectColor(_ subject: String) -> Color {
        switch subject {
        case "Physics":     return .blue
        case "Chemistry":   return .teal
        case "Mathematics": return .indigo
        default:            return .purple
        }
    }
    private func subjectIcon(_ subject: String) -> String {
        switch subject {
        case "Physics":     return "atom"
        case "Chemistry":   return "flask.fill"
        case "Mathematics": return "function"
        default:            return "books.vertical"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Search bar (sticky above scroll) ──
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search formulas…", text: $vm.searchText)
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
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // ── Subject filter chips ──
            FormulaSubjectFilterBar(
                subjects:        vm.subjects,
                selected:        vm.selectedSubject,
                subjectColor:    subjectColor,
                subjectIcon:     subjectIcon,
                onSelect:        vm.selectSubject
            )
            .padding(.bottom, 10)

            // ── Stats pill ──
            if !vm.searchText.isEmpty || vm.selectedSubject != "All" {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 11))
                    Text("\(vm.totalCount) formula\(vm.totalCount == 1 ? "" : "s") found")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color(UIColor.systemGray6))
                .clipShape(Capsule())
                .padding(.bottom, 8)
            }

            Divider()

            // ── List ──
            if vm.filteredCategories.isEmpty {
                FormulaEmptyState(query: vm.searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(vm.filteredCategories) { category in
                            FormulaCategoryCard(
                                category:      category,
                                isExpanded:    expandedCategory == category.id,
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
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 32)
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
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
}

// MARK: - Subject Filter Bar

private struct FormulaSubjectFilterBar: View {
    let subjects:     [String]
    let selected:     String
    let subjectColor: (String) -> Color
    let subjectIcon:  (String) -> String
    let onSelect:     (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(subjects, id: \.self) { subject in
                    let isSelected = selected == subject
                    Button { onSelect(subject) } label: {
                        HStack(spacing: 5) {
                            if subject == "All" {
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: 11, weight: .semibold))
                            } else {
                                Image(systemName: subjectIcon(subject))
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text(subject)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(isSelected ? .white : (subject == "All" ? Color(UIColor.label) : subjectColor(subject)))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            isSelected
                                ? AnyShapeStyle(subject == "All"
                                    ? AnyShapeStyle(LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing))
                                    : AnyShapeStyle(subjectColor(subject)))
                                : AnyShapeStyle(subject == "All"
                                    ? AnyShapeStyle(Color(UIColor.systemGray5))
                                    : AnyShapeStyle(subjectColor(subject).opacity(0.1)))
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Empty State

private struct FormulaEmptyState: View {
    let query: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: query.isEmpty ? "books.vertical" : "magnifyingglass")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
            Text(query.isEmpty ? "No formulas" : "No results for \"\(query)\"")
                .font(.system(size: 17, weight: .semibold))
            Text(query.isEmpty
                 ? "Select a subject above to browse formulas"
                 : "Try a different keyword or clear the filter")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Category Card

private struct FormulaCategoryCard: View {
    let category:    FormulaCategory
    let isExpanded:  Bool
    let onHeaderTap: () -> Void
    let onFormulaTap: (Formula) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // ── 4px subject-colour accent strip ──
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [category.color, category.color.opacity(0.5)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 4)

            // ── Header ──
            Button(action: onHeaderTap) {
                HStack(spacing: 12) {
                    // Gradient circle icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [category.color.opacity(0.18), category.color.opacity(0.07)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 46, height: 46)
                        Image(systemName: category.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(category.color)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(UIColor.label))

                        HStack(spacing: 6) {
                            // Subject pill
                            Text(category.subject)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(category.color)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(category.color.opacity(0.1))
                                .clipShape(Capsule())

                            Text("·")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 11))
                            Text("\(category.formulas.count) formulas")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Count badge + chevron
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(category.color.opacity(0.1))
                                .frame(width: 28, height: 28)
                            Text("\(category.formulas.count)")
                                .font(.system(size: 11, weight: .black))
                                .foregroundStyle(category.color)
                        }
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(category.name), \(category.subject), \(category.formulas.count) formulas. \(isExpanded ? "Expanded" : "Collapsed").")

            // ── Formula rows (animated expand) ──
            if isExpanded {
                Divider().padding(.horizontal, 14)
                ForEach(Array(category.formulas.enumerated()), id: \.element.id) { idx, formula in
                    FormulaRow(formula: formula, color: category.color,
                               onTap: { onFormulaTap(formula) })
                    if idx < category.formulas.count - 1 {
                        Divider().padding(.leading, 14)
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

// MARK: - Formula Row

private struct FormulaRow: View {
    let formula: Formula
    let color:   Color
    let onTap:   () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // Left colour stripe
                Capsule()
                    .fill(color.opacity(0.7))
                    .frame(width: 3)
                    .padding(.vertical, 10)
                    .padding(.leading, 14)

                HStack(alignment: .top, spacing: 10) {
                    // Expression badge — monospaced, pill background
                    Text(formula.expression)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(color.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: 72, alignment: .leading)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(formula.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(UIColor.label))
                        Text(formula.variables)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color.opacity(0.5))
                        .padding(.top, 2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(formula.name): \(formula.expression). \(formula.variables). Tap to ask AI to explain.")
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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Large expression hero ──
                    VStack(spacing: 6) {
                        Text(formula.expression)
                            .font(.system(size: 34, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(UIColor.label))
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity)
                            .padding(28)
                            .background(
                                LinearGradient(
                                    colors: [.indigo.opacity(0.1), .purple.opacity(0.06)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                            .overlay(
                                RoundedRectangle(cornerRadius: 22)
                                    .stroke(Color.indigo.opacity(0.15), lineWidth: 1)
                            )
                    }

                    // ── Variables ──
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Variables", systemImage: "x.squareroot")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.indigo)

                        let parts = formula.variables.components(separatedBy: ", ")
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(parts, id: \.self) { part in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(Color.indigo.opacity(0.4))
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 6)
                                    Text(part)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color(UIColor.label))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(14)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // ── Tags ──
                    if !formula.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Related topics", systemImage: "tag.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.indigo)
                            FlowLayout(formula.tags)
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }

            // ── Ask AI CTA ──
            VStack(spacing: 0) {
                Divider()
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
                        .background(
                            LinearGradient(
                                colors: [.indigo, .purple],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .background(Color(UIColor.systemBackground))
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
