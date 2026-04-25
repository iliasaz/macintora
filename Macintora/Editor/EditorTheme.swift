//
//  EditorTheme.swift
//  Macintora
//
//  Color themes for the syntax-highlighted editor. Each case builds a
//  `STPluginNeonAppKit.Theme` programmatically from a hex palette so we don't
//  have to vendor color assets into the plugin package.
//

import AppKit
import STPluginNeon

enum EditorTheme: String, CaseIterable, Identifiable, Sendable, Hashable {
    case `default`
    case dracula
    case catppuccinMocha
    case catppuccinFrappe
    case catppuccinLatte

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: return "Default"
        case .dracula: return "Dracula"
        case .catppuccinMocha: return "Catppuccin Mocha"
        case .catppuccinFrappe: return "Catppuccin Frappé"
        case .catppuccinLatte: return "Catppuccin Latte"
        }
    }

    @MainActor
    func neonTheme() -> STPluginNeonAppKit.Theme {
        switch self {
        case .default:
            return .default
        case .dracula:
            return Self.makeTheme(palette: Self.draculaPalette)
        case .catppuccinMocha:
            return Self.makeTheme(palette: Self.catppuccinMochaPalette)
        case .catppuccinFrappe:
            return Self.makeTheme(palette: Self.catppuccinFrappePalette)
        case .catppuccinLatte:
            return Self.makeTheme(palette: Self.catppuccinLattePalette)
        }
    }
}

// MARK: - Palette + theme construction

extension EditorTheme {
    /// Token-name → hex string. Hex strings are accepted with or without `#`,
    /// 3/4/6/8 character variants. Tokens use the same dotted convention as
    /// tree-sitter captures so the hierarchical fallback in
    /// `STPluginNeonAppKit.Theme` still resolves children to parents.
    fileprivate struct Palette {
        let plain: String
        let comment: String
        let keyword: String
        let keywordFunction: String
        let keywordReturn: String
        let function: String
        let type: String
        let string: String
        let number: String
        let boolean: String
        let `operator`: String
        let variable: String
        let variableBuiltin: String
        let constructor: String
        let parameter: String
        let include: String
        let punctuation: String
        let textTitle: String
        let textLiteral: String
    }

    fileprivate static func makeTheme(palette: Palette) -> STPluginNeonAppKit.Theme {
        let colors: [String: NSColor] = [
            "plain": .fromHex(palette.plain),
            "comment": .fromHex(palette.comment),
            "keyword": .fromHex(palette.keyword),
            "keyword.function": .fromHex(palette.keywordFunction),
            "keyword.return": .fromHex(palette.keywordReturn),
            "function.call": .fromHex(palette.function),
            "method": .fromHex(palette.function),
            "type": .fromHex(palette.type),
            "string": .fromHex(palette.string),
            "text.literal": .fromHex(palette.textLiteral),
            "text.title": .fromHex(palette.textTitle),
            "number": .fromHex(palette.number),
            "boolean": .fromHex(palette.boolean),
            "operator": .fromHex(palette.operator),
            "variable": .fromHex(palette.variable),
            "variable.builtin": .fromHex(palette.variableBuiltin),
            "constructor": .fromHex(palette.constructor),
            "parameter": .fromHex(palette.parameter),
            "include": .fromHex(palette.include),
            "punctuation.special": .fromHex(palette.punctuation)
        ]

        let regular = NSFont.monospacedSystemFont(ofSize: 0, weight: .regular)
        let medium = NSFont.monospacedSystemFont(ofSize: 0, weight: .medium)
        let fonts: [String: NSFont] = [
            "plain": regular,
            "comment": regular,
            "keyword": medium,
            "keyword.function": medium,
            "keyword.return": medium,
            "function.call": regular,
            "method": regular,
            "type": regular,
            "string": regular,
            "text.literal": regular,
            "text.title": medium,
            "number": regular,
            "boolean": regular,
            "operator": regular,
            "variable": regular,
            "variable.builtin": regular,
            "constructor": medium,
            "parameter": regular,
            "include": regular,
            "punctuation.special": regular
        ]

        return STPluginNeonAppKit.Theme(
            colors: STPluginNeonAppKit.Theme.Colors(colors: colors),
            fonts: STPluginNeonAppKit.Theme.Fonts(fonts: fonts)
        )
    }
}

// MARK: - Palettes

extension EditorTheme {
    /// Dracula — https://draculatheme.com/oracle-sql-developer
    fileprivate static let draculaPalette = Palette(
        plain: "#F8F8F2",
        comment: "#6272A4",
        keyword: "#FF79C6",
        keywordFunction: "#FF79C6",
        keywordReturn: "#FF79C6",
        function: "#50FA7B",
        type: "#8BE9FD",
        string: "#F1FA8C",
        number: "#BD93F9",
        boolean: "#BD93F9",
        operator: "#FF79C6",
        variable: "#F8F8F2",
        variableBuiltin: "#BD93F9",
        constructor: "#8BE9FD",
        parameter: "#FFB86C",
        include: "#FF79C6",
        punctuation: "#F8F8F2",
        textTitle: "#F8F8F2",
        textLiteral: "#F1FA8C"
    )

    /// Catppuccin Mocha — https://github.com/catppuccin/catppuccin
    fileprivate static let catppuccinMochaPalette = Palette(
        plain: "#CDD6F4",
        comment: "#7F849C",
        keyword: "#CBA6F7",
        keywordFunction: "#CBA6F7",
        keywordReturn: "#CBA6F7",
        function: "#89B4FA",
        type: "#F9E2AF",
        string: "#A6E3A1",
        number: "#FAB387",
        boolean: "#FAB387",
        operator: "#89DCEB",
        variable: "#CDD6F4",
        variableBuiltin: "#F38BA8",
        constructor: "#F9E2AF",
        parameter: "#EBA0AC",
        include: "#CBA6F7",
        punctuation: "#94E2D5",
        textTitle: "#CDD6F4",
        textLiteral: "#A6E3A1"
    )

    /// Catppuccin Frappé
    fileprivate static let catppuccinFrappePalette = Palette(
        plain: "#C6D0F5",
        comment: "#838BA7",
        keyword: "#CA9EE6",
        keywordFunction: "#CA9EE6",
        keywordReturn: "#CA9EE6",
        function: "#8CAAEE",
        type: "#E5C890",
        string: "#A6D189",
        number: "#EF9F76",
        boolean: "#EF9F76",
        operator: "#99D1DB",
        variable: "#C6D0F5",
        variableBuiltin: "#E78284",
        constructor: "#E5C890",
        parameter: "#EA999C",
        include: "#CA9EE6",
        punctuation: "#81C8BE",
        textTitle: "#C6D0F5",
        textLiteral: "#A6D189"
    )

    /// Catppuccin Latte (light)
    fileprivate static let catppuccinLattePalette = Palette(
        plain: "#4C4F69",
        comment: "#8C8FA1",
        keyword: "#8839EF",
        keywordFunction: "#8839EF",
        keywordReturn: "#8839EF",
        function: "#1E66F5",
        type: "#DF8E1D",
        string: "#40A02B",
        number: "#FE640B",
        boolean: "#FE640B",
        operator: "#04A5E5",
        variable: "#4C4F69",
        variableBuiltin: "#D20F39",
        constructor: "#DF8E1D",
        parameter: "#E64553",
        include: "#8839EF",
        punctuation: "#179299",
        textTitle: "#4C4F69",
        textLiteral: "#40A02B"
    )
}

// MARK: - NSColor hex helper

private extension NSColor {
    static func fromHex(_ hex: String) -> NSColor {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else {
            return .labelColor
        }
        let r = CGFloat((value & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((value & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(value & 0x0000FF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}
