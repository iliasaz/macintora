//
//  TextViewCoordinator+Highlighter.swift
//  EditorView
//
//  Created by Ilia Sazonov on 7/13/23.
//

import Foundation
import AppKit
import SwiftTreeSitter

extension TextViewCoordinator {
    /// Configures the `Highlighter` object
    internal func setUpHighlighter() {
        self.highlighter = Highlighter(
            textView: self.textView!,
            highlightProvider: highlightProvider,
            theme: theme,
            attributeProvider: self,
            language: language
        )
    }

    /// Sets the highlight provider and re-highlights all text. This method should be used sparingly.
    internal func setHighlightProvider(_ highlightProvider: HighlightProviding? = nil) {
        var provider: HighlightProviding?

        if let highlightProvider = highlightProvider {
            provider = highlightProvider
        } else {
            let textProvider: ResolvingQueryCursor.TextProvider = { [weak self] range, _ -> String? in
                return self!.textView!.textContentStorage?.textStorage?.mutableString.substring(with: range)
            }

            provider = TreeSitterClient(textProvider: textProvider)
        }

        if let provider = provider {
            self.highlightProvider = provider
            highlighter?.setHighlightProvider(provider)
        }
    }

    /// Gets all attributes for the given capture including the line height, background color, and text color.
    /// - Parameter capture: The capture to use for syntax highlighting.
    /// - Returns: All attributes to be applied.
    public func attributesFor(_ capture: CaptureName?) -> [NSAttributedString.Key: Any] {
        return [
//            .font: parent.font,
            .foregroundColor: theme.colorFor(capture),
//            .baselineOffset: baselineOffset,
//            .paragraphStyle: paragraphStyle,
//            .kern: kern
        ]
    }
}

let sqlTheme = EditorTheme.init(
    text: .textColor.withAlphaComponent(0.7),
    insertionPoint: .controlAccentColor ,
    invisibles: .lightGray,
    background: .textBackgroundColor,
    lineHighlight: .unemphasizedSelectedContentBackgroundColor ,
    selection: .selectedTextBackgroundColor,
    keywords: keywordColor,
    commands: .yellow,
    types: .orange,
    attributes: .brown,
    variables: .textColor.withAlphaComponent(0.7),
    values: .magenta,
    numbers: numberColor,
    strings: stringColor,
    characters: .green,
    comments: .lightGray)

let sourceFont = NSFont(name: "SF Mono", size: 12.0)!

let keywordColor = NSColor(hex: "#b854d4", alpha: 0.5)
let numberColor = NSColor(hex: "#b65611", alpha: 1.0)
let stringColor = NSColor(hex: "#60AC39", alpha: 1.0)
