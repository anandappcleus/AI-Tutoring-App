"""
Packs router — offline question pack management.

Endpoints:
    GET /packs                      List all available topic packs
    GET /packs/{pack_id}/download   Return questions for a pack (for local caching)

Design (Sprint 8):
    Pack catalog is static — defined in _PACK_CATALOG below.
    Questions are hardcoded English-language development placeholders pending
    Bengali translation review (Sprint 8 Content QA task).

    No DB table is needed: packs are content, not user data.
    The iOS app saves downloaded questions to Core Data for offline access.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel

from app.routers.auth import get_current_student
from app.models.student import Student

log = logging.getLogger(__name__)
router = APIRouter()


# ── Pydantic schemas ──────────────────────────────────────────────────

class PackResponse(BaseModel):
    id: str
    subject: str
    topic: str
    exam_target: str
    language: str
    question_count: int
    size_kb: int
    icon_name: str   # SF Symbol name used by iOS
    color_hex: str   # Subject colour for the card


class QuestionItem(BaseModel):
    id: str
    topic: str
    subject: str
    question_text: str
    answer_text: str
    language: str


class PackDownloadResponse(BaseModel):
    pack_id: str
    questions: list[QuestionItem]


# ── Static pack catalog ───────────────────────────────────────────────

_PACK_CATALOG: list[dict] = [
    {
        "id":             "physics-mechanics-jee",
        "subject":        "Physics",
        "topic":          "Mechanics – Laws of Motion",
        "exam_target":    "JEE",
        "language":       "en",
        "question_count": 5,
        "size_kb":        12,
        "icon_name":      "bolt.fill",
        "color_hex":      "#3B82F6",
    },
    {
        "id":             "chemistry-organic-jee",
        "subject":        "Chemistry",
        "topic":          "Organic Chemistry – Reactions",
        "exam_target":    "JEE",
        "language":       "en",
        "question_count": 5,
        "size_kb":        10,
        "icon_name":      "flask.fill",
        "color_hex":      "#10B981",
    },
    {
        "id":             "maths-calculus-jee",
        "subject":        "Mathematics",
        "topic":          "Calculus – Integration",
        "exam_target":    "JEE",
        "language":       "en",
        "question_count": 5,
        "size_kb":         8,
        "icon_name":      "function",
        "color_hex":      "#8B5CF6",
    },
    {
        "id":             "physics-electro-jee",
        "subject":        "Physics",
        "topic":          "Electromagnetism",
        "exam_target":    "JEE",
        "language":       "en",
        "question_count": 5,
        "size_kb":        11,
        "icon_name":      "bolt.circle.fill",
        "color_hex":      "#3B82F6",
    },
    {
        "id":             "chemistry-thermo-jee",
        "subject":        "Chemistry",
        "topic":          "Physical Chemistry – Thermodynamics",
        "exam_target":    "JEE",
        "language":       "en",
        "question_count": 5,
        "size_kb":         9,
        "icon_name":      "thermometer.medium",
        "color_hex":      "#10B981",
    },
    {
        "id":             "maths-algebra-jee",
        "subject":        "Mathematics",
        "topic":          "Algebra – Quadratic Equations",
        "exam_target":    "JEE",
        "language":       "en",
        "question_count": 5,
        "size_kb":         7,
        "icon_name":      "x.squareroot",
        "color_hex":      "#8B5CF6",
    },
]

# ── Static questions (dev placeholders — Bengali translation needed in QA) ──

_PACK_QUESTIONS: dict[str, list[dict]] = {
    "physics-mechanics-jee": [
        {
            "id": "phys-mech-001",
            "topic": "Laws of Motion",
            "subject": "Physics",
            "question_text": "State Newton's Second Law of Motion and write its mathematical form.",
            "answer_text": (
                "Newton's Second Law states that the net force on an object equals the rate of change "
                "of its momentum. Mathematically: F = ma, where F is net force (N), m is mass (kg), "
                "and a is acceleration (m/s²). For JEE, remember: this law gives magnitude and "
                "direction of force simultaneously."
            ),
            "language": "en",
        },
        {
            "id": "phys-mech-002",
            "topic": "Conservation of Momentum",
            "subject": "Physics",
            "question_text": "Two balls of masses 2 kg and 3 kg collide. If the 2 kg ball was moving at 5 m/s and the 3 kg ball was at rest, find the velocity after a perfectly inelastic collision.",
            "answer_text": (
                "Using conservation of momentum: m₁v₁ + m₂v₂ = (m₁+m₂)v_f\n"
                "2×5 + 3×0 = (2+3)×v_f\n10 = 5v_f\nv_f = 2 m/s\n"
                "Both balls move together at 2 m/s after the collision."
            ),
            "language": "en",
        },
        {
            "id": "phys-mech-003",
            "topic": "Friction",
            "subject": "Physics",
            "question_text": "A block of mass 5 kg is placed on a horizontal surface with μₛ = 0.4 and μₖ = 0.3. What is the minimum force needed to start moving it? (g = 10 m/s²)",
            "answer_text": (
                "The minimum force to start motion equals the maximum static friction:\n"
                "F = μₛ × N = μₛ × mg = 0.4 × 5 × 10 = 20 N\n"
                "Once moving, kinetic friction = 0.3 × 50 = 15 N (less than static)."
            ),
            "language": "en",
        },
        {
            "id": "phys-mech-004",
            "topic": "Work-Energy Theorem",
            "subject": "Physics",
            "question_text": "State the Work-Energy theorem and use it to find the speed of a 2 kg object after a net work of 100 J, starting from rest.",
            "answer_text": (
                "Work-Energy Theorem: Net work done on an object = Change in kinetic energy\n"
                "W_net = ΔKE = ½mv² − ½mv₀²\n"
                "100 = ½ × 2 × v² − 0\n"
                "v² = 100 → v = 10 m/s"
            ),
            "language": "en",
        },
        {
            "id": "phys-mech-005",
            "topic": "Circular Motion",
            "subject": "Physics",
            "question_text": "A car moves in a circular path of radius 50 m at 10 m/s. Calculate the centripetal acceleration and the centripetal force if the car's mass is 1000 kg.",
            "answer_text": (
                "Centripetal acceleration: a_c = v²/r = 100/50 = 2 m/s²\n"
                "Centripetal force: F_c = ma_c = 1000 × 2 = 2000 N\n"
                "This force is directed towards the centre of the circular path."
            ),
            "language": "en",
        },
    ],

    "chemistry-organic-jee": [
        {
            "id": "chem-org-001",
            "topic": "Substitution Reactions",
            "subject": "Chemistry",
            "question_text": "Differentiate between SN1 and SN2 mechanisms with one example each.",
            "answer_text": (
                "SN1 (Unimolecular): 2-step — carbocation intermediate formed first.\n"
                "Rate depends only on substrate concentration. Favoured by tertiary carbons.\n"
                "Example: (CH₃)₃CBr + H₂O → (CH₃)₃COH\n\n"
                "SN2 (Bimolecular): 1-step — backside attack by nucleophile, inversion of configuration.\n"
                "Rate depends on both substrate and nucleophile. Favoured by primary carbons.\n"
                "Example: CH₃Br + OH⁻ → CH₃OH + Br⁻"
            ),
            "language": "en",
        },
        {
            "id": "chem-org-002",
            "topic": "Addition Reactions",
            "subject": "Chemistry",
            "question_text": "State Markovnikov's rule and give a JEE-level example.",
            "answer_text": (
                "Markovnikov's Rule: In electrophilic addition to an unsymmetrical alkene, "
                "the H adds to the carbon that already has more hydrogens.\n\n"
                "Example: CH₃-CH=CH₂ + HBr →\n"
                "Major product: CH₃-CHBr-CH₃ (2-bromopropane) — H adds to CH₂\n"
                "Minor product: CH₃-CH₂-CH₂Br (1-bromopropane)\n\n"
                "Anti-Markovnikov addition occurs in the presence of peroxides (free-radical mechanism)."
            ),
            "language": "en",
        },
        {
            "id": "chem-org-003",
            "topic": "Aldol Condensation",
            "subject": "Chemistry",
            "question_text": "What is the Aldol condensation reaction? Give its mechanism and one example.",
            "answer_text": (
                "Aldol condensation: Two molecules of an aldehyde/ketone with α-hydrogens react in "
                "base to form a β-hydroxy carbonyl compound (aldol), which on heating dehydrates to "
                "an α,β-unsaturated carbonyl compound.\n\n"
                "Mechanism: 1) Base removes α-H → enolate  2) Enolate attacks C=O of second molecule "
                "→ aldol product  3) Heating → dehydration\n\n"
                "Example: 2CH₃CHO → (base) → CH₃CH(OH)CH₂CHO → (Δ) → CH₃CH=CHCHO + H₂O"
            ),
            "language": "en",
        },
        {
            "id": "chem-org-004",
            "topic": "Elimination Reactions",
            "subject": "Chemistry",
            "question_text": "State Saytzeff's rule. A secondary alkyl halide undergoes elimination — which product is major?",
            "answer_text": (
                "Saytzeff's (Zaitsev's) Rule: In elimination reactions, the major product is the "
                "more substituted (more stable) alkene.\n\n"
                "Example: 2-bromobutane + KOH/alcohol →\n"
                "Major: but-2-ene (disubstituted, more stable)\n"
                "Minor: but-1-ene (monosubstituted)\n\n"
                "Exception: Bulky base (e.g. t-BuOK) favours Hofmann (less substituted) product."
            ),
            "language": "en",
        },
        {
            "id": "chem-org-005",
            "topic": "Nucleophilic Addition",
            "subject": "Chemistry",
            "question_text": "Explain nucleophilic addition to carbonyl compounds with the example of acetaldehyde + HCN.",
            "answer_text": (
                "Nucleophilic addition mechanism:\n"
                "1) CN⁻ (nucleophile) attacks the electrophilic carbonyl carbon\n"
                "2) Tetrahedral intermediate (alkoxide) forms\n"
                "3) Protonation gives the product\n\n"
                "CH₃CHO + HCN → CH₃CH(OH)CN (lactonitrile)\n\n"
                "Aldehydes are more reactive than ketones due to less steric hindrance and "
                "+I effect of alkyl groups reducing electrophilicity."
            ),
            "language": "en",
        },
    ],

    "maths-calculus-jee": [
        {
            "id": "math-calc-001",
            "topic": "Integration",
            "subject": "Mathematics",
            "question_text": "State the integration by parts formula and use it to evaluate ∫x·eˣ dx.",
            "answer_text": (
                "Integration by parts: ∫u·dv = u·v − ∫v·du\n\n"
                "Choose u = x (easy to differentiate), dv = eˣ dx\n"
                "Then du = dx, v = eˣ\n\n"
                "∫x·eˣ dx = x·eˣ − ∫eˣ dx = x·eˣ − eˣ + C = eˣ(x − 1) + C\n\n"
                "JEE tip: Use ILATE rule to choose u: Inverse, Logarithmic, Algebraic, "
                "Trigonometric, Exponential."
            ),
            "language": "en",
        },
        {
            "id": "math-calc-002",
            "topic": "Definite Integrals",
            "subject": "Mathematics",
            "question_text": "Evaluate ∫₀^π sin x dx and interpret the result geometrically.",
            "answer_text": (
                "∫₀^π sin x dx = [−cos x]₀^π = −cos(π) − (−cos 0) = −(−1) − (−1) = 1 + 1 = 2\n\n"
                "Geometric interpretation: The area under the curve y = sin x between x = 0 and "
                "x = π equals 2 square units. The entire curve lies above the x-axis in this "
                "interval, so the integral represents the actual area."
            ),
            "language": "en",
        },
        {
            "id": "math-calc-003",
            "topic": "Area Under Curve",
            "subject": "Mathematics",
            "question_text": "Find the area enclosed between y = x² and y = x.",
            "answer_text": (
                "Step 1: Find intersection points: x² = x → x(x−1) = 0 → x = 0 or x = 1\n"
                "Step 2: Determine which is upper curve in [0,1]: at x = 0.5, y=x gives 0.5, "
                "y=x² gives 0.25. So y=x is upper.\n"
                "Step 3: Area = ∫₀¹ (x − x²) dx = [x²/2 − x³/3]₀¹ = 1/2 − 1/3 = 1/6 sq. units"
            ),
            "language": "en",
        },
        {
            "id": "math-calc-004",
            "topic": "Integration by Substitution",
            "subject": "Mathematics",
            "question_text": "Evaluate ∫ 2x·(x² + 1)⁵ dx using substitution.",
            "answer_text": (
                "Let t = x² + 1 → dt = 2x dx\n\n"
                "∫ 2x·(x² + 1)⁵ dx = ∫ t⁵ dt = t⁶/6 + C = (x² + 1)⁶/6 + C\n\n"
                "Substitution works when you can identify a function and its derivative "
                "appearing together in the integrand."
            ),
            "language": "en",
        },
        {
            "id": "math-calc-005",
            "topic": "Integration",
            "subject": "Mathematics",
            "question_text": "Evaluate ∫ dx / (1 + x²) and state its significance.",
            "answer_text": (
                "∫ dx / (1 + x²) = arctan(x) + C = tan⁻¹(x) + C\n\n"
                "This is a standard result to memorise for JEE.\n\n"
                "As a definite integral: ∫₋∞^∞ dx/(1+x²) = π, which connects calculus to the "
                "constant π — a beautiful result in mathematical analysis."
            ),
            "language": "en",
        },
    ],

    "physics-electro-jee": [
        {
            "id": "phys-em-001",
            "topic": "Electromagnetic Induction",
            "subject": "Physics",
            "question_text": "State Faraday's laws of electromagnetic induction.",
            "answer_text": (
                "First Law: Whenever the magnetic flux linked with a conductor changes, an EMF is "
                "induced in the conductor.\n\n"
                "Second Law: The magnitude of the induced EMF is directly proportional to the rate "
                "of change of magnetic flux:\n"
                "ε = −dΦ/dt\n\n"
                "The negative sign reflects Lenz's law — the induced EMF opposes the change causing it."
            ),
            "language": "en",
        },
        {
            "id": "phys-em-002",
            "topic": "Electromagnetic Induction",
            "subject": "Physics",
            "question_text": "State Lenz's law and explain how it is a consequence of energy conservation.",
            "answer_text": (
                "Lenz's Law: The direction of induced current is such that it opposes the change in "
                "magnetic flux that caused it.\n\n"
                "Energy conservation link: If the induced current aided the flux change (instead of "
                "opposing it), it would cause more change → more current → runaway effect violating "
                "energy conservation. The opposing direction ensures work must be done to maintain "
                "the flux change, providing the electrical energy."
            ),
            "language": "en",
        },
        {
            "id": "phys-em-003",
            "topic": "Magnetism",
            "subject": "Physics",
            "question_text": "State Ampere's Circuital Law and use it to find the magnetic field inside a solenoid.",
            "answer_text": (
                "Ampere's Law: ∮ B·dl = μ₀·I_enclosed\n\n"
                "For a solenoid of n turns per unit length carrying current I:\n"
                "Choose a rectangular Amperian loop: B·L = μ₀·(nL·I)\n"
                "∴ B = μ₀nI\n\n"
                "The field inside is uniform, parallel to the axis. Outside ≈ 0 for an ideal solenoid."
            ),
            "language": "en",
        },
        {
            "id": "phys-em-004",
            "topic": "Electrostatics",
            "subject": "Physics",
            "question_text": "State Gauss's Law and use it to find the electric field due to an infinite plane sheet of charge density σ.",
            "answer_text": (
                "Gauss's Law: ∮ E·dA = Q_enclosed / ε₀\n\n"
                "For infinite plane sheet (charge density σ):\n"
                "Use a cylindrical Gaussian surface (pill box) with two circular caps of area A:\n"
                "2E·A = σA/ε₀\n"
                "E = σ / (2ε₀)\n\n"
                "The field is uniform, independent of distance from the sheet, and perpendicular to it."
            ),
            "language": "en",
        },
        {
            "id": "phys-em-005",
            "topic": "Electromagnetic Induction",
            "subject": "Physics",
            "question_text": "A rectangular coil of 100 turns and area 0.1 m² rotates at 50 rad/s in a 0.2 T magnetic field. Find the peak EMF.",
            "answer_text": (
                "Peak EMF formula: ε₀ = NBAω\n"
                "ε₀ = 100 × 0.2 × 0.1 × 50\n"
                "ε₀ = 100 V\n\n"
                "The EMF varies as ε = ε₀ sin(ωt) = 100 sin(50t) V\n"
                "This is the principle behind AC generators."
            ),
            "language": "en",
        },
    ],

    "chemistry-thermo-jee": [
        {
            "id": "chem-thermo-001",
            "topic": "Thermodynamics",
            "subject": "Chemistry",
            "question_text": "State Hess's Law and explain how it is used to calculate lattice energy (Born-Haber cycle).",
            "answer_text": (
                "Hess's Law: The total enthalpy change of a reaction is independent of the path "
                "taken — it depends only on the initial and final states.\n\n"
                "Born-Haber cycle (e.g. NaCl formation):\n"
                "ΔH_f = ΔH_sublimation + IE₁(Na) + ½D(Cl₂) + EA(Cl) + U(lattice)\n\n"
                "Since all other terms are measurable, lattice energy U can be calculated.\n"
                "This is crucial for JEE as lattice energy cannot be measured directly."
            ),
            "language": "en",
        },
        {
            "id": "chem-thermo-002",
            "topic": "Entropy",
            "subject": "Chemistry",
            "question_text": "Define entropy. Does entropy increase or decrease when ice melts? Explain.",
            "answer_text": (
                "Entropy (S) is a measure of the disorder or randomness of a system.\n"
                "ΔS = q_rev / T (reversible heat / temperature)\n\n"
                "When ice melts: Entropy INCREASES\n"
                "Reason: Liquid water has more disorder than solid ice — water molecules in liquid "
                "state have more freedom of movement than in the rigid crystal lattice.\n"
                "ΔS_fusion = ΔH_fusion / T_melting = 6020 J/mol / 273 K ≈ 22 J/mol·K > 0"
            ),
            "language": "en",
        },
        {
            "id": "chem-thermo-003",
            "topic": "Gibbs Free Energy",
            "subject": "Chemistry",
            "question_text": "What is Gibbs free energy? State the condition for spontaneity.",
            "answer_text": (
                "Gibbs Free Energy: G = H − TS\n"
                "Change: ΔG = ΔH − TΔS\n\n"
                "Spontaneity conditions:\n"
                "ΔG < 0 → Spontaneous\n"
                "ΔG > 0 → Non-spontaneous\n"
                "ΔG = 0 → System at equilibrium\n\n"
                "Summary table for JEE:\n"
                "ΔH−, ΔS+ → Always spontaneous\n"
                "ΔH+, ΔS− → Never spontaneous\n"
                "ΔH−, ΔS− → Spontaneous at low T\n"
                "ΔH+, ΔS+ → Spontaneous at high T"
            ),
            "language": "en",
        },
        {
            "id": "chem-thermo-004",
            "topic": "First Law of Thermodynamics",
            "subject": "Chemistry",
            "question_text": "State the First Law of Thermodynamics. A gas absorbs 500 J of heat and does 200 J of work. Find the change in internal energy.",
            "answer_text": (
                "First Law: Energy can neither be created nor destroyed, only converted.\n"
                "ΔU = q − w\n"
                "where q = heat absorbed by system, w = work done BY system\n\n"
                "ΔU = 500 − 200 = 300 J\n\n"
                "Sign convention (IUPAC): q > 0 (heat in), w > 0 (work done BY system)\n"
                "Alternative convention in some books: ΔU = q + w (w = work done ON system)"
            ),
            "language": "en",
        },
        {
            "id": "chem-thermo-005",
            "topic": "Enthalpy",
            "subject": "Chemistry",
            "question_text": "Define standard enthalpy of formation. What is ΔH°f for any element in its standard state?",
            "answer_text": (
                "Standard Enthalpy of Formation (ΔH°f): The enthalpy change when 1 mole of a "
                "compound is formed from its constituent elements in their standard states "
                "(298 K, 1 bar).\n\n"
                "Key rule: ΔH°f for any element in its standard state = 0\n"
                "Examples: ΔH°f(O₂, g) = 0, ΔH°f(C, graphite) = 0, ΔH°f(H₂, g) = 0\n\n"
                "Application: ΔH°rxn = Σ ΔH°f(products) − Σ ΔH°f(reactants)"
            ),
            "language": "en",
        },
    ],

    "maths-algebra-jee": [
        {
            "id": "math-alg-001",
            "topic": "Quadratic Equations",
            "subject": "Mathematics",
            "question_text": "For the quadratic ax² + bx + c = 0, define the discriminant and state what it tells us about the roots.",
            "answer_text": (
                "Discriminant: D = b² − 4ac\n\n"
                "D > 0: Two distinct real roots\n"
                "D = 0: Two equal (repeated) real roots; x = −b/(2a)\n"
                "D < 0: No real roots (two complex conjugate roots)\n\n"
                "JEE tip: For roots to be real and rational, D must be a perfect square."
            ),
            "language": "en",
        },
        {
            "id": "math-alg-002",
            "topic": "Quadratic Equations",
            "subject": "Mathematics",
            "question_text": "If α and β are the roots of x² − 5x + 6 = 0, find α + β, αβ, α² + β², and α³ + β³.",
            "answer_text": (
                "From Vieta's formulas: α + β = 5, αβ = 6\n\n"
                "α² + β² = (α+β)² − 2αβ = 25 − 12 = 13\n\n"
                "α³ + β³ = (α+β)(α² − αβ + β²) = (α+β)[(α+β)² − 3αβ]\n"
                "= 5 × (25 − 18) = 5 × 7 = 35\n\n"
                "Verification: Roots are x = 2 and x = 3 → 8 + 27 = 35 ✓"
            ),
            "language": "en",
        },
        {
            "id": "math-alg-003",
            "topic": "Quadratic Equations",
            "subject": "Mathematics",
            "question_text": "State Vieta's formulas for a general quadratic ax² + bx + c = 0.",
            "answer_text": (
                "For roots α and β of ax² + bx + c = 0:\n\n"
                "Sum of roots:    α + β = −b/a\n"
                "Product of roots: αβ  = c/a\n\n"
                "These allow you to form a quadratic when roots are known:\n"
                "x² − (α+β)x + αβ = 0\n\n"
                "Extension (cubic ax³ + bx² + cx + d = 0):\n"
                "α+β+γ = −b/a;  αβ+βγ+γα = c/a;  αβγ = −d/a"
            ),
            "language": "en",
        },
        {
            "id": "math-alg-004",
            "topic": "Quadratic Equations",
            "subject": "Mathematics",
            "question_text": "Complete the square for x² + 6x + 5 and hence solve the equation.",
            "answer_text": (
                "x² + 6x + 5\n"
                "= (x² + 6x + 9) − 9 + 5\n"
                "= (x + 3)² − 4\n\n"
                "Setting equal to zero: (x + 3)² = 4\n"
                "x + 3 = ±2\n"
                "x = −1  or  x = −5\n\n"
                "Completing the square is also used to convert a conic section from general "
                "to standard form in coordinate geometry."
            ),
            "language": "en",
        },
        {
            "id": "math-alg-005",
            "topic": "Quadratic Equations",
            "subject": "Mathematics",
            "question_text": "Derive the quadratic formula from ax² + bx + c = 0.",
            "answer_text": (
                "ax² + bx + c = 0\n"
                "Divide by a: x² + (b/a)x + c/a = 0\n"
                "Complete the square: (x + b/(2a))² = b²/(4a²) − c/a\n"
                "= (b² − 4ac) / (4a²)\n\n"
                "Taking square root: x + b/(2a) = ±√(b²−4ac) / (2a)\n"
                "x = [−b ± √(b²−4ac)] / (2a)\n\n"
                "This derivation is sometimes asked in JEE mains short-answer format."
            ),
            "language": "en",
        },
    ],
}


# ── Endpoints ─────────────────────────────────────────────────────────

@router.get("", response_model=list[PackResponse])
async def list_packs(
    _: Student = Depends(get_current_student),
) -> list[dict]:
    """Return the full catalog of available offline packs."""
    log.debug("packs.list  count=%d", len(_PACK_CATALOG))
    return _PACK_CATALOG


@router.get("/{pack_id}/download", response_model=PackDownloadResponse)
async def download_pack(
    pack_id: str,
    _: Student = Depends(get_current_student),
) -> PackDownloadResponse:
    """
    Return the questions for a pack as a JSON payload.
    The iOS app saves these to Core Data for offline access.
    """
    questions = _PACK_QUESTIONS.get(pack_id)
    if questions is None:
        log.warning("packs.download.not_found  pack_id=%s", pack_id)
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": "pack_not_found", "message": f"Pack '{pack_id}' does not exist."},
        )
    log.info("packs.download  pack_id=%s  questions=%d", pack_id, len(questions))
    return PackDownloadResponse(
        pack_id=pack_id,
        questions=[QuestionItem(**q) for q in questions],
    )
