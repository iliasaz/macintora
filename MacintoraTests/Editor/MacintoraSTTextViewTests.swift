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
}
