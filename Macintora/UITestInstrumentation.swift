//
//  UITestInstrumentation.swift
//  Macintora
//
//  Tiny probe used by `MacintoraUITests/EditorShortcutsUITests` to verify
//  that menu items and toolbar shortcuts dispatch the right action. The
//  whole instrument is dormant unless the app was launched with the
//  `-uiTestProbe` argument, so production runs pay no runtime cost beyond
//  one Boolean read per wrapped action.
//
//  Launch arguments (set via `XCUIApplication.launchArguments`):
//  - `-uiTestProbe`           — turn instrumentation on, suppress real
//                               side effects, and force-publish
//                               `worksheetIsConnected = .connected` so
//                               menu items that gate on the connection
//                               state are enabled.
//  - `-uiTestForceExecuting`  — additionally force-publish
//                               `worksheetIsExecuting = true` so the
//                               Stop menu item is enabled.
//
//  A SwiftUI `UITestProbeView` renders `lastCommand` as a hidden `Text`
//  with `accessibilityIdentifier("ui_test_probe.last_command")`. Tests
//  read its `value` to assert the right command name fired.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class UITestProbe {
    static let shared = UITestProbe()

    let isEnabled: Bool
    let suppressActions: Bool
    let forceConnected: Bool
    let forceExecuting: Bool

    /// Name of the most-recently invoked probed action. Empty string until
    /// the first call. SwiftUI's `@Observable` tracking republishes this to
    /// the probe view so XCUITest can poll for the expected value.
    private(set) var lastCommand: String = ""

    private init() {
        let args = ProcessInfo.processInfo.arguments
        let enabled = args.contains("-uiTestProbe")
        isEnabled = enabled
        suppressActions = enabled
        forceConnected = enabled
        forceExecuting = args.contains("-uiTestForceExecuting")
    }

    /// Wrap a menu/toolbar action with the probe. In production
    /// (`isEnabled == false`) the wrapper is a single Boolean read and a
    /// closure call — measurably free. In test mode it records the name
    /// and skips the real side effect.
    func dispatch(_ command: String, _ action: () -> Void) {
        if isEnabled {
            lastCommand = command
            guard !suppressActions else { return }
        }
        action()
    }
}

/// Small visible `Text` chip carrying `UITestProbe.lastCommand`. Embedded
/// as an overlay on `MainDocumentView` so XCUITest can read its
/// accessibility value. The chip is intentionally rendered (not hidden):
/// invisible SwiftUI views drop out of the accessibility tree, and being
/// able to eyeball the recorded command while watching a failing test run
/// is a useful diagnosability bonus. Renders nothing when the probe is
/// dormant, so production runs see no UI change.
struct UITestProbeView: View {
    private let probe = UITestProbe.shared

    var body: some View {
        if probe.isEnabled {
            Text(probe.lastCommand.isEmpty ? "(idle)" : probe.lastCommand)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.regularMaterial, in: .capsule)
                .padding(4)
                .accessibilityIdentifier("ui_test_probe.last_command")
                .accessibilityValue(probe.lastCommand)
                .allowsHitTesting(false)
        }
    }
}
