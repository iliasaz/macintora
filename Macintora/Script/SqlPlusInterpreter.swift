//
//  SqlPlusInterpreter.swift
//  Macintora
//
//  Pure mapping `Directive → side effect on SqlPlusEnvironment`. Returns a
//  `DirectiveOutcome` so the runner can decide what to surface in the
//  Script Output pane.
//

import Foundation

enum DirectiveOutcome: Equatable, Sendable {
    /// Directive was applied silently — emit a `directive` entry in output.
    case acknowledged
    /// `PROMPT msg` — emit a `prompt` entry with the given text.
    case prompt(message: String)
    /// `REM …` — silently skip; no output entry.
    case skip
    /// `SHOW ERRORS` — controller dispatches an Oracle query and emits the
    /// resulting compile errors as a structured entry. v1 falls back to a
    /// note when SHOW ERRORS is encountered without a prior CREATE.
    case showErrors
    /// `@file` / `@@file` — flattening should have consumed these. Reaching
    /// the runner means an unresolved include — surface as a warning note.
    case unresolvedInclude(path: String, doubleAt: Bool)
    /// Directive was unrecognised; pass through with raw text.
    case noted(text: String)
}

@MainActor
enum SqlPlusInterpreter {
    /// Apply `directive` to `env`. Returns the outcome the runner should
    /// reflect in its output stream.
    static func apply(_ directive: SqlPlusDirective, env: SqlPlusEnvironment) -> DirectiveOutcome {
        switch directive {
        case .set(let setting):
            applySet(setting, env: env)
            return .acknowledged

        case .define(let name, let value):
            env.defines[name.uppercased()] = value
            return .acknowledged

        case .undefine(let name):
            env.defines.removeValue(forKey: name.uppercased())
            return .acknowledged

        case .prompt(let message):
            return .prompt(message: message)

        case .remark:
            return .skip

        case .showErrors:
            return .showErrors

        case .whenever(_, let action):
            env.whenever = action
            return .acknowledged

        case .include(let path, let doubleAt):
            return .unresolvedInclude(path: path, doubleAt: doubleAt)

        case .unrecognized(let text):
            return .noted(text: text)
        }
    }

    private static func applySet(_ setting: SetSetting, env: SqlPlusEnvironment) {
        switch setting {
        case .serverOutput(let on):
            env.serverOutput = on
        case .echo(let on):
            env.echo = on
        case .feedback(let mode):
            env.feedback = mode
        case .define(let mode):
            switch mode {
            case .on:
                env.defineEnabled = true
            case .off:
                env.defineEnabled = false
            case .prefix(let c):
                env.defineEnabled = true
                env.definePrefix = c
            }
        case .other:
            // Silently ignore unknown SET options; users get a feel for which
            // ones we honor without each one becoming an error.
            break
        }
    }
}
