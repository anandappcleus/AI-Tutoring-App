//
//  MathTextView.swift
//  SmartTutor
//
//  Pure-SwiftUI LaTeX renderer — no third-party libraries, no WebView.
//
//  Inline math is delimited by $...$  (or $$...$$).
//  Math segments are parsed into tokens and rendered using Text concatenation
//  with .baselineOffset() for super/subscripts, Unicode for symbols,
//  and (num/den) notation for fractions.
//
//  Usage:
//      MathTextView("The answer is $\\frac{H}{2}$ units.")
//          .foregroundStyle(Color.primary)
//

import SwiftUI

// MARK: - Public View

struct MathTextView: View {
    let rawText: String
    var fontSize: CGFloat = 15

    init(_ rawText: String, fontSize: CGFloat = 15) {
        self.rawText = rawText
        self.fontSize = fontSize
    }

    var body: some View {
        _buildText()
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(3)
    }

    private func _buildText() -> Text {
        _splitSegments(rawText).reduce(Text("")) { acc, seg in
            acc + _renderSegment(seg)
        }
    }

    private func _renderSegment(_ seg: _MathSegment) -> Text {
        switch seg {
        case .plain(let s):
            return Text(s).font(.system(size: fontSize))
        case .math(let latex):
            return _LatexRenderer.render(latex, fontSize: fontSize)
        }
    }
}

// MARK: - Segment model

private enum _MathSegment {
    case plain(String)
    case math(String)
}

// MARK: - Segment splitter  (splits on $...$ and $$...$$)

private func _splitSegments(_ text: String) -> [_MathSegment] {
    var result: [_MathSegment] = []
    var plain = ""
    var i = text.startIndex

    while i < text.endIndex {
        guard text[i] == "$" else {
            plain.append(text[i])
            i = text.index(after: i)
            continue
        }
        // Determine delimiter length ($ vs $$)
        let next = text.index(after: i)
        let isDouble = next < text.endIndex && text[next] == "$"
        let delimLen = isDouble ? 2 : 1
        let delimiter = isDouble ? "$$" : "$"

        if !plain.isEmpty { result.append(.plain(plain)); plain = "" }

        let searchFrom = text.index(i, offsetBy: delimLen)
        if let closeRange = text.range(of: delimiter, range: searchFrom..<text.endIndex) {
            result.append(.math(String(text[searchFrom..<closeRange.lowerBound])))
            i = closeRange.upperBound
        } else {
            // No closing delimiter — treat as plain text
            plain.append(text[i])
            i = text.index(after: i)
        }
    }
    if !plain.isEmpty { result.append(.plain(plain)) }
    return result
}

// MARK: - Token model

private enum _Token {
    case text(String)
    case command(String)
    case sup(String)        // ^{...} or ^x
    case sub(String)        // _{...} or _x
    case frac(String, String)
    case sqrt(String, String?)   // content, optional index
    case paren(String)           // \left( ... \right)  — rendered as (...)
}

// MARK: - LaTeX renderer

private enum _LatexRenderer {

    static func render(_ latex: String, fontSize: CGFloat) -> Text {
        tokenize(latex).reduce(Text("")) { acc, tok in
            acc + renderToken(tok, fontSize: fontSize)
        }
    }

    // MARK: Tokenizer

    private static func tokenize(_ s: String) -> [_Token] {
        var tokens: [_Token] = []
        var i = s.startIndex

        while i < s.endIndex {
            let c = s[i]
            switch c {
            case "\\":
                let (cmd, j) = readCommand(s, from: s.index(after: i))
                i = j
                switch cmd {
                case "frac":
                    let (num, j2) = readGroup(s, from: i)
                    let (den, j3) = readGroup(s, from: j2)
                    tokens.append(.frac(num, den)); i = j3
                case "sqrt":
                    var idx: String? = nil
                    var j2 = i
                    if j2 < s.endIndex && s[j2] == "[" {
                        let (idxStr, j3) = readBracket(s, from: s.index(after: j2))
                        idx = idxStr; j2 = j3
                    }
                    let (content, j3) = readGroup(s, from: j2)
                    tokens.append(.sqrt(content, idx)); i = j3
                case "left":
                    // Skip the bracket char after \left
                    if i < s.endIndex { i = s.index(after: i) }
                case "right":
                    if i < s.endIndex { i = s.index(after: i) }
                case "!", ",", ";", ":", " ", "quad", "qquad",
                     "mathrm", "mathbf", "mathit", "mathbb",
                     "mathcal", "mathfrak", "text", "mbox":
                    // Spacing / font commands — consume optional following {group}
                    if i < s.endIndex && s[i] == "{" {
                        let (inner, j2) = readGroup(s, from: i)
                        tokens.append(.text(inner)); i = j2
                    } else if cmd == "quad" {
                        tokens.append(.text("  "))
                    } else if cmd == "qquad" {
                        tokens.append(.text("    "))
                    }
                default:
                    tokens.append(.command(cmd))
                }

            case "^":
                i = s.index(after: i)
                let (content, j) = readGroup(s, from: i)
                tokens.append(.sup(content)); i = j

            case "_":
                i = s.index(after: i)
                let (content, j) = readGroup(s, from: i)
                tokens.append(.sub(content)); i = j

            case "{", "}":
                i = s.index(after: i)   // skip bare braces

            default:
                tokens.append(.text(String(c)))
                i = s.index(after: i)
            }
        }
        return tokens
    }

    // MARK: Token renderer

    private static func renderToken(_ tok: _Token, fontSize: CGFloat) -> Text {
        let mono = Font.system(size: fontSize, design: .monospaced)
        switch tok {

        case .text(let s):
            return Text(s).font(mono)

        case .command(let cmd):
            return Text(symbol(cmd)).font(.system(size: fontSize))

        case .sup(let s):
            return render(s, fontSize: fontSize * 0.68)
                .baselineOffset(fontSize * 0.42)

        case .sub(let s):
            return render(s, fontSize: fontSize * 0.68)
                .baselineOffset(-(fontSize * 0.22))

        case .frac(let num, let den):
            // Rendered as (num/den) inline — readable and correct
            return Text("(").font(mono)
                + render(num, fontSize: fontSize)
                + Text("/").font(mono)
                + render(den, fontSize: fontSize)
                + Text(")").font(mono)

        case .sqrt(let content, let idx):
            let radical: Text
            if let ix = idx, !ix.isEmpty {
                radical = render(ix, fontSize: fontSize * 0.6).baselineOffset(fontSize * 0.5)
                    + Text("√").font(.system(size: fontSize))
            } else {
                radical = Text("√").font(.system(size: fontSize))
            }
            return radical
                + Text("(").font(mono)
                + render(content, fontSize: fontSize)
                + Text(")").font(mono)

        case .paren(let s):
            return Text("(").font(mono)
                + render(s, fontSize: fontSize)
                + Text(")").font(mono)
        }
    }

    // MARK: Symbol table

    // swiftlint:disable cyclomatic_complexity
    private static func symbol(_ cmd: String) -> String {
        switch cmd {
        // Greek lowercase
        case "alpha":              return "α"
        case "beta":               return "β"
        case "gamma":              return "γ"
        case "delta":              return "δ"
        case "epsilon","varepsilon": return "ε"
        case "zeta":               return "ζ"
        case "eta":                return "η"
        case "theta","vartheta":   return "θ"
        case "iota":               return "ι"
        case "kappa":              return "κ"
        case "lambda":             return "λ"
        case "mu":                 return "μ"
        case "nu":                 return "ν"
        case "xi":                 return "ξ"
        case "pi","varpi":         return "π"
        case "rho","varrho":       return "ρ"
        case "sigma","varsigma":   return "σ"
        case "tau":                return "τ"
        case "upsilon":            return "υ"
        case "phi","varphi":       return "φ"
        case "chi":                return "χ"
        case "psi":                return "ψ"
        case "omega":              return "ω"
        // Greek uppercase
        case "Gamma":   return "Γ"
        case "Delta":   return "Δ"
        case "Theta":   return "Θ"
        case "Lambda":  return "Λ"
        case "Xi":      return "Ξ"
        case "Pi":      return "Π"
        case "Sigma":   return "Σ"
        case "Upsilon": return "Υ"
        case "Phi":     return "Φ"
        case "Psi":     return "Ψ"
        case "Omega":   return "Ω"
        // Operators
        case "times":   return "×"
        case "div":     return "÷"
        case "cdot":    return "·"
        case "pm":      return "±"
        case "mp":      return "∓"
        case "leq","le": return "≤"
        case "geq","ge": return "≥"
        case "neq","ne": return "≠"
        case "approx":  return "≈"
        case "equiv":   return "≡"
        case "sim":     return "∼"
        case "propto":  return "∝"
        case "infty":   return "∞"
        case "partial": return "∂"
        case "nabla":   return "∇"
        case "forall":  return "∀"
        case "exists":  return "∃"
        case "in":      return "∈"
        case "notin":   return "∉"
        case "subset":  return "⊂"
        case "supset":  return "⊃"
        case "cup":     return "∪"
        case "cap":     return "∩"
        case "emptyset":return "∅"
        case "int":     return "∫"
        case "oint":    return "∮"
        case "sum":     return "∑"
        case "prod":    return "∏"
        // Arrows
        case "rightarrow","to":       return "→"
        case "leftarrow","gets":      return "←"
        case "leftrightarrow":        return "↔"
        case "Rightarrow":            return "⇒"
        case "Leftarrow":             return "⇐"
        case "Leftrightarrow":        return "⇔"
        case "uparrow":               return "↑"
        case "downarrow":             return "↓"
        case "mapsto":                return "↦"
        // Dots
        case "cdots": return "⋯"
        case "ldots","dots": return "…"
        case "vdots": return "⋮"
        case "ddots": return "⋱"
        // Functions (keep as plain text)
        case "ln","log","sin","cos","tan","cot","sec","csc",
             "arcsin","arccos","arctan","sinh","cosh","tanh",
             "exp","lim","max","min","sup","inf","det",
             "gcd","lcm","mod","arg","ker","dim","deg":
            return cmd
        // Misc
        case "hbar":    return "ℏ"
        case "ell":     return "ℓ"
        case "Re":      return "ℜ"
        case "Im":      return "ℑ"
        case "angle":   return "∠"
        case "perp":    return "⊥"
        case "parallel":return "∥"
        case "circ":    return "∘"
        case "bullet":  return "•"
        case "oplus":   return "⊕"
        case "otimes":  return "⊗"
        case "langle":  return "⟨"
        case "rangle":  return "⟩"
        case "lfloor":  return "⌊"
        case "rfloor":  return "⌋"
        case "lceil":   return "⌈"
        case "rceil":   return "⌉"
        case "to":      return "→"
        case "neg","lnot": return "¬"
        case "land":    return "∧"
        case "lor":     return "∨"
        case "degree":  return "°"
        default:        return cmd   // unknown — show name as-is
        }
    }
    // swiftlint:enable cyclomatic_complexity

    // MARK: Parsing helpers

    /// Read a command name (letters) or single non-letter char after backslash.
    private static func readCommand(_ s: String, from start: String.Index) -> (String, String.Index) {
        var i = start
        if i >= s.endIndex { return ("", i) }
        guard s[i].isLetter else {
            return (String(s[i]), s.index(after: i))
        }
        var cmd = ""
        while i < s.endIndex && s[i].isLetter {
            cmd.append(s[i]); i = s.index(after: i)
        }
        // Consume single trailing space
        if i < s.endIndex && s[i] == " " { i = s.index(after: i) }
        return (cmd, i)
    }

    /// Read {braced group} or single character.
    private static func readGroup(_ s: String, from start: String.Index) -> (String, String.Index) {
        var i = start
        while i < s.endIndex && s[i] == " " { i = s.index(after: i) }
        guard i < s.endIndex else { return ("", i) }
        if s[i] == "{" {
            i = s.index(after: i)
            var content = ""; var depth = 1
            while i < s.endIndex {
                if s[i] == "{" { depth += 1 }
                else if s[i] == "}" { depth -= 1; if depth == 0 { return (content, s.index(after: i)) } }
                content.append(s[i]); i = s.index(after: i)
            }
            return (content, i)
        }
        return (String(s[i]), s.index(after: i))
    }

    /// Read [bracket group] — call with index AFTER the opening [.
    private static func readBracket(_ s: String, from start: String.Index) -> (String, String.Index) {
        var i = start; var content = ""
        while i < s.endIndex && s[i] != "]" { content.append(s[i]); i = s.index(after: i) }
        if i < s.endIndex { i = s.index(after: i) }
        return (content, i)
    }
}
