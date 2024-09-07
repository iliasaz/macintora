//
//  TextViewCoordinator.swift
//  EditorView
//
//  Created by Ilia Sazonov on 7/13/23.
//

import Foundation
import STTextView
import AppKit
import Combine
import CodeEditLanguages

class TextViewCoordinator: STTextViewDelegate, ThemeAttributesProviding {
    var parent: TextViewRepresentable
    var textView: STTextView?
    var isUpdating: Bool = false
    var isDidChangeText: Bool = false
    var enqueuedValue: AttributedString?

    // MARK: - Highlighting
    internal var highlighter: Highlighter?

    /// The associated `CodeLanguage`
    public var language: CodeLanguage { didSet {
        // TODO: Decide how to handle errors thrown here
        highlighter?.setLanguage(language: language)
    }}

    /// The associated `Theme` used for highlighting.
    public var theme: EditorTheme { didSet {
        highlighter?.invalidate()
    }}

    /// Whether the code editor should use the theme background color or be transparent
    public var useThemeBackground: Bool

    public var systemAppearance: NSAppearance.Name?

    var cancellables = Set<AnyCancellable>()

    /// The provided highlight provider.
    internal var highlightProvider: HighlightProviding?

    init(parent: TextViewRepresentable) {
        self.parent = parent
        self.theme = sqlTheme
        self.language = .sql
        self.useThemeBackground = true
    }

    func textViewDidChangeText(_ notification: Notification) {
        guard let textView = notification.object as? STTextView else {
            return
        }

        if !isUpdating {
            let newTextValue = AttributedString(textView.attributedString())
            DispatchQueue.main.async {
                self.isDidChangeText = true
                self.parent.text = newTextValue
            }
        }
    }
}
