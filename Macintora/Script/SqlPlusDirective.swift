//
//  SqlPlusDirective.swift
//  Macintora
//
//  Typed AST for the SQL*Plus directive subset supported by the script runner.
//  Phase 0 only parses these from text; Phase 6 attaches semantics in
//  SqlPlusInterpreter.
//

import Foundation

enum SqlPlusDirective: Equatable, Sendable {
    case set(SetSetting)
    case define(name: String, value: String)
    case undefine(name: String)
    case prompt(message: String)
    case remark(text: String)
    case showErrors
    case whenever(WheneverCondition, WheneverAction)
    case include(path: String, doubleAt: Bool)
    case unrecognized(text: String)
}

enum SetSetting: Equatable, Sendable {
    case serverOutput(Bool)
    case echo(Bool)
    case feedback(FeedbackMode)
    case define(DefineMode)
    case other(name: String, raw: String)
}

enum FeedbackMode: Equatable, Sendable {
    case on
    case off
    case rows(Int)
}

enum DefineMode: Equatable, Sendable {
    case on
    case off
    case prefix(Character)
}

enum WheneverCondition: Equatable, Sendable {
    case sqlError
    case osError
}

enum WheneverAction: Equatable, Sendable {
    case `continue`(ContinueAction)
    case exit(ExitCode, commitOrRollback: CommitAction?)
}

enum ContinueAction: Equatable, Sendable {
    case commit
    case rollback
    case noAction
}

enum CommitAction: Equatable, Sendable {
    case commit
    case rollback
}

enum ExitCode: Equatable, Sendable {
    case success
    case failure
    case warning
    case sqlCode
    case value(Int)
}
