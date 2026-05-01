//
//  ScriptError.swift
//  Macintora
//

import Foundation

/// Errors surfaced by the script lexer / runner. `originalRange` references
/// positions in the unparsed script source so callers can navigate back to
/// the offending region in the editor.
enum ScriptError: Error, Equatable, Sendable {
    case unterminatedString(at: String.Index)
    case unterminatedQQuote(at: String.Index)
    case unterminatedBlockComment(at: String.Index)
    case unterminatedQuotedIdentifier(at: String.Index)
    case unterminatedPlsqlBlock(at: String.Index)
    case malformedDirective(at: String.Index, message: String)
}
