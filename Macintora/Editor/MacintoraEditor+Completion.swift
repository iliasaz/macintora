//
//  MacintoraEditor+Completion.swift
//  Macintora
//
//  Connects the STTextView completion-delegate protocol to the host app's
//  `CompletionCoordinator`. Kept in its own file so the completion surface
//  is easy to audit alongside the rest of the editor delegate code.
//
//  AppKit invokes the delegate methods on the main thread even though the
//  protocol declares them `nonisolated`. We use `MainActor.assumeIsolated`
//  (a sync precondition assertion) for synchronous main-actor reads, then
//  await the coordinator's async items() method whose return type is the
//  concrete Sendable `MacintoraCompletionItem` so the result can cross the
//  actor boundary cleanly.
//

import AppKit
@preconcurrency import STTextView
import STPluginNeon  // re-exports SwiftTreeSitter

extension MacintoraEditorRepresentable.Coordinator {

    /// Sync hook — prefer the async variant. Returning nil signals the
    /// textView to fall through to `performAsyncCompletion`.
    @MainActor
    func textView(_ textView: STTextView,
                  completionItemsAtLocation location: any NSTextLocation) -> [any STCompletionItem]? {
        nil
    }

    /// Async completion provider. Marked `@MainActor` (a more-isolated witness
    /// for the nonisolated protocol requirement, allowed in Swift 6.2) so we
    /// can read `STTextView` state and pass non-Sendable AppKit types like
    /// `NSTextLocation` without bridging gymnastics. AppKit always invokes
    /// these delegate methods on the main thread, so this matches reality.
    @MainActor
    func textView(_ textView: STTextView,
                  completionItemsAtLocation location: any NSTextLocation) async -> [any STCompletionItem]? {
        guard let coordinator = completionCoordinator else {
            editorCompletionLog.notice("async completion: no coordinator (config not yet installed)")
            return nil
        }
        let utf16Offset = textView.textContentManager.offset(
            from: textView.textContentManager.documentRange.location,
            to: location)
        let items: [MacintoraCompletionItem] =
            await coordinator.items(for: textView, atUTF16Offset: utf16Offset)
        editorCompletionLog.info("async completion: offset=\(utf16Offset) returned \(items.count) item(s)")
        return items.isEmpty ? nil : items
    }

    @MainActor
    func textView(_ textView: STTextView, insertCompletionItem item: any STCompletionItem) {
        completionCoordinator?.insert(item, into: textView)
    }

    /// Provide our customised view controller (softer material + accent-tinted
    /// selection). STTextView keeps owning the popup window and key handling.
    @MainActor
    func textViewCompletionViewController(_ textView: STTextView) -> any STCompletionViewControllerProtocol {
        MacintoraCompletionViewController()
    }
}
