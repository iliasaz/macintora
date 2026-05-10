import XCTest
@testable import Macintora

/// Unit coverage for `MacintoraSTTextView`'s init-time spell-check defaults.
///
/// Disabling these flags at construction time exists to dodge the
/// priority-inversion runtime warning that fires when AppKit's NSSpellChecker
/// hops to a default-QoS NLP thread while the user-interactive main thread
/// waits on it. Keeping the flags off by default also matters for SQL editing
/// — spell underlines on identifiers would be constant noise, and auto
/// quote / text replacement would mangle SQL syntax.
@MainActor
final class MacintoraSTTextViewTests: XCTestCase {

    func test_init_disablesSpellAndGrammarMachinery() {
        let view = MacintoraSTTextView(frame: .zero)

        XCTAssertFalse(view.isContinuousSpellCheckingEnabled,
                       "Continuous spell check must default off — SQL identifiers would be constantly flagged")
        XCTAssertFalse(view.isGrammarCheckingEnabled,
                       "Grammar check must default off")
        XCTAssertFalse(view.isAutomaticSpellingCorrectionEnabled,
                       "Auto-correction must default off — would mangle SQL keywords")
        XCTAssertFalse(view.isAutomaticTextReplacementEnabled,
                       "Text replacement must default off — would mangle SQL")
        XCTAssertFalse(view.isAutomaticQuoteSubstitutionEnabled,
                       "Quote substitution must default off — SQL string literals must stay ASCII")
    }

    // MARK: - toggleLineComment

    private func makeView(text: String, selection: NSRange) -> MacintoraSTTextView {
        let view = MacintoraSTTextView(frame: .zero)
        view.text = text
        view.textSelection = selection
        return view
    }

    func test_toggleLineComment_singleLine_addsPrefix() {
        let view = makeView(text: "select * from dual", selection: NSRange(location: 0, length: 0))
        view.toggleLineComment(nil)
        XCTAssertEqual(view.text, "-- select * from dual")
    }

    func test_toggleLineComment_singleLine_alreadyCommented_removesPrefix() {
        let view = makeView(text: "-- select 1 from dual", selection: NSRange(location: 0, length: 0))
        view.toggleLineComment(nil)
        XCTAssertEqual(view.text, "select 1 from dual")
    }

    func test_toggleLineComment_singleLine_commentedWithoutSpace_removesMarkerOnly() {
        let view = makeView(text: "--noSpace", selection: NSRange(location: 0, length: 0))
        view.toggleLineComment(nil)
        XCTAssertEqual(view.text, "noSpace")
    }

    func test_toggleLineComment_multiLine_allUncommented_commentsAll() {
        let view = makeView(text: "select 1\nfrom dual\n",
                            selection: NSRange(location: 0, length: 18))
        view.toggleLineComment(nil)
        XCTAssertEqual(view.text, "-- select 1\n-- from dual\n")
    }

    func test_toggleLineComment_multiLine_allCommented_uncommentsAll() {
        let view = makeView(text: "-- select 1\n-- from dual\n",
                            selection: NSRange(location: 0, length: 25))
        view.toggleLineComment(nil)
        XCTAssertEqual(view.text, "select 1\nfrom dual\n")
    }

    func test_toggleLineComment_multiLine_mixed_commentsAll() {
        // Xcode/VS Code semantics: any uncommented line ⇒ comment all.
        let view = makeView(text: "-- select 1\nfrom dual\n",
                            selection: NSRange(location: 0, length: 22))
        view.toggleLineComment(nil)
        XCTAssertEqual(view.text, "-- -- select 1\n-- from dual\n")
    }

    func test_toggleLineComment_preservesIndentation() {
        let view = makeView(text: "  select 1\n\tfrom dual\n",
                            selection: NSRange(location: 0, length: 22))
        view.toggleLineComment(nil)
        XCTAssertEqual(view.text, "  -- select 1\n\t-- from dual\n")
    }

    func test_toggleLineComment_blankLines_areLeftAlone() {
        let view = makeView(text: "select 1\n\nfrom dual\n",
                            selection: NSRange(location: 0, length: 20))
        view.toggleLineComment(nil)
        XCTAssertEqual(view.text, "-- select 1\n\n-- from dual\n",
                       "Blank line in the middle must stay blank — toggling shouldn't dirty empty lines")
    }

    func test_toggleLineComment_caretOnBlankLine_isNoOp() {
        let view = makeView(text: "select 1\n\nfrom dual",
                            selection: NSRange(location: 9, length: 0))
        view.toggleLineComment(nil)
        XCTAssertEqual(view.text, "select 1\n\nfrom dual")
    }

    func test_toggleLineComment_selectionEndsAtNextLineStart_excludesTrailingLine() {
        // Selection covers all of line 1 plus the newline; line 2 is not touched.
        let view = makeView(text: "select 1\nfrom dual\n",
                            selection: NSRange(location: 0, length: 9))
        view.toggleLineComment(nil)
        XCTAssertEqual(view.text, "-- select 1\nfrom dual\n")
    }
}
