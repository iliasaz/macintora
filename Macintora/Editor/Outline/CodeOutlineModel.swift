//
//  CodeOutlineModel.swift
//  Macintora
//
//  Backing model for `CodeOutlineView`: holds the extracted symbols, the
//  filter/scope state, and the caret position, and derives the grouped,
//  filtered sections the view renders. Re-extraction is driven by the view
//  (debounced) so the model stays pure and unit-testable.
//

import Foundation
import STPluginNeon  // re-exports SwiftTreeSitter

@MainActor
@Observable
final class CodeOutlineModel {

    /// Scope chip above the symbol list.
    enum KindFilter: String, CaseIterable, Identifiable, Sendable {
        case all
        case procedures
        case functions
        case state          // variables + constants

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all:        "All"
            case .procedures: "Procs"
            case .functions:  "Funcs"
            case .state:      "Vars"
            }
        }

        func matches(_ kind: CodeSymbol.Kind) -> Bool {
            switch self {
            case .all:        true
            case .procedures: kind == .procedure
            case .functions:  kind == .function
            case .state:      kind == .variable || kind == .constant
            }
        }
    }

    /// One rendered group; `id` is the kind so SwiftUI can diff sections.
    struct OutlineSection: Identifiable {
        let kind: CodeSymbol.Kind
        let symbols: [CodeSymbol]
        var id: CodeSymbol.Kind { kind }
    }

    private(set) var symbols: [CodeSymbol] = []
    var filterText: String = ""
    var kindFilter: KindFilter = .all
    /// UTF-16 offset of the caret in the source, used to mark the symbol the
    /// caret currently sits inside.
    var caretUTF16Offset: Int = 0

    /// Re-extract from `source`. Pass an existing parse tree to skip re-parsing.
    func refresh(from source: String, tree: SwiftTreeSitter.Tree? = nil) {
        symbols = CodeSymbolExtractor.symbols(in: source, tree: tree)
        if !availableFilters.contains(kindFilter) { kindFilter = .all }
    }

    var hasNoSymbols: Bool { symbols.isEmpty }

    /// Scope chips worth showing: `.all`, plus only the kinds that actually
    /// occur in the source. (A "Vars" chip over a package with no globals just
    /// shows an empty list — confusing.)
    var availableFilters: [KindFilter] {
        [.all] + KindFilter.allCases.filter { filter in
            filter != .all && symbols.contains { filter.matches($0.kind) }
        }
    }

    var filteredSymbols: [CodeSymbol] {
        let needle = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        return symbols.filter { symbol in
            kindFilter.matches(symbol.kind)
                && (needle.isEmpty || symbol.name.localizedStandardContains(needle))
        }
    }

    /// Non-empty sections in display order; symbols alphabetised within each.
    var sections: [OutlineSection] {
        let visible = filteredSymbols
        return CodeSymbol.Kind.displayOrder.compactMap { kind in
            let group = visible
                .filter { $0.kind == kind }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return group.isEmpty ? nil : OutlineSection(kind: kind, symbols: group)
        }
    }

    /// Innermost symbol whose full range contains the caret.
    var currentSymbolID: CodeSymbol.ID? {
        symbols
            .filter { $0.fullRange.contains(caretUTF16Offset) }
            .min(by: { $0.fullRange.count < $1.fullRange.count })?
            .id
    }
}
