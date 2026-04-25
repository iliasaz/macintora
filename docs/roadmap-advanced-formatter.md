# Roadmap: Advanced formatter with user-defined patterns

A second-stage formatter that accepts user-defined formatting rules — match these AST patterns, apply this layout — and ships a curated default rule set on top of the basic formatter. Aims to give Macintora users the customizability of Arbori / Trivadis without inheriting their stack.

This depends on the basic formatter shipping first. Read [`roadmap-basic-formatter.md`](./roadmap-basic-formatter.md) for that prerequisite.

---

## 1. Goal

A user wants their team's house style:

- INSERT VALUES with more than 3 columns: one column per line, equals signs aligned.
- INSERT INTO ... SELECT: the `INSERT` and `SELECT` lines start at the same column.
- Custom `CASE` layout: each `WHEN` indented under the `CASE` keyword.
- A specific application's SELECT statements always have a comment header above them.

The basic formatter (per [`roadmap-basic-formatter.md`](./roadmap-basic-formatter.md)) handles indent / wrap / case / comma — the things every user wants. The advanced formatter adds:

1. **Pattern-based rules** that the user can write, share, version-control.
2. **Alignment** primitives (column-anchored layout) that don't fit the Wadler IR cleanly.
3. **A curated rule set** shipped with Macintora as the equivalent of Trivadis's settings — drop-in best-practice defaults.

## 2. Non-goals

- **AST rewrites** (refactoring). E.g., "convert old comma-join syntax to ANSI JOIN." That's a refactor tool, not a formatter; separate doc when it's wanted.
- **Multi-file formatting.** Operates on one buffer at a time, like the basic formatter.
- **A general-purpose programming language.** The pattern language is a DSL with narrow capabilities; users wanting Turing-complete logic should write a Swift extension, not stretch the DSL.

## 3. UX

- **Settings → Formatter → Rules**: a list of enabled rule files. Drag-and-drop reorder (later rules override earlier ones, last write wins).
- **`.macintora-format/*.scm`** in the workspace root or `~/Library/Application Support/Macintora/format-rules/`: tree-sitter-style query files containing format directives. Workspace files take precedence over user-global.
- **Live preview**: when the user edits a rule file in Macintora, the editor preview updates immediately on a sample buffer.
- **Lint / explain**: right-click a piece of code → "Explain formatting": Macintora highlights the rule(s) that fired on this range.

## 4. Pattern language

Two design options. Both keep the language declarative and AST-rooted.

### Option A — extended tree-sitter queries (recommended)

Tree-sitter already has a query language we use for highlights. Extend it with format-directive captures, similar to [Topiary](https://github.com/tweag/topiary):

```scheme
;; One column per line in INSERT VALUES with more than 3 columns
(insert
  (list (column) @col)
  (#count? @col 4 ..))         ; predicate: count of @col captures >= 4
@_insert
(#append_hardline! @col)        ; directive: hardline after each captured node
(#indent! @_insert 2)

;; Align equals signs in UPDATE SET assignments
(update
  (assignment
    left:  (_) @lhs
    right: (_) @rhs))
(#align_to_column! @lhs @rhs)

;; Always force CASE/WHEN onto separate lines
(case
  (keyword_when) @when)
(#prepend_hardline! @when)
```

The directives are `#append_hardline!`, `#prepend_hardline!`, `#delete!`, `#indent! NODE N`, `#dedent! NODE N`, `#align_to_column! ANCHOR FOLLOWERS`, `#singleline! NODE`, `#multiline! NODE`. Each is interpreted by the formatter at the Doc-construction stage — the user's directives lift, lower, or replace the basic formatter's emitted Doc.

**Pros:**
- Reuses tree-sitter's existing query parser; no new parser to write.
- Matches user mental model — they already write highlight queries.
- Files version-control cleanly.
- Topiary has proven the model.

**Cons:**
- Tree-sitter's query language is not ergonomic for "do X then Y in this order."
- Aliasing limitations (can't easily refer to ancestor nodes).

### Option B — Swift DSL

```swift
FormatRule("insert-values-one-per-line") {
    match { (insert) in
        guard insert.values.columns.count >= 4 else { return .skip }
        return .apply
    }
    layout {
        insert.values.columns.forEach { col in
            col.append(.hardline)
        }
        insert.values.indent(2)
    }
}
```

**Pros:**
- Full Swift power, type-safe, debuggable.
- Easy to share rules as a Swift package.

**Cons:**
- Users have to write Swift.
- Distribution / sandboxing — can a user-supplied Swift DSL run safely?
- Live-preview of rule edits requires hot reload, which Swift doesn't support natively.

**Recommendation:** Option A. Lower barrier to entry, safer (declarative, no arbitrary code), matches Topiary's model, files are easy to share. Power users wanting Option B can drop to Swift via a plugin protocol — separate concern.

## 5. Alignment subsystem

The Wadler Doc IR doesn't natively express column-anchored layout. Add a small extension:

```swift
indirect enum Doc {
    // … existing cases …
    case alignToColumn(anchor: Doc, follower: Doc)
}
```

The layouter, when fitting `alignToColumn`, records the column at which `anchor`'s last char emits, then ensures `follower` starts at that column on its line (padding with spaces).

Use cases:

- Equals signs in UPDATE SET, INSERT VALUES with named columns.
- Column-name vertical alignment in CREATE TABLE.
- Operator-aligned binary expressions (`a +` / `b -` / `c *` style).

A guard: alignment only kicks in when the anchor and follower are in a `multiline` context. In single-line layout, alignment is a no-op (just emit the spaces in the natural place).

## 6. Curated rule set ("Macintora style")

Ship a default set of `.scm` files in the app bundle as the equivalent of Trivadis's curated XML. Categories:

- **Spacing & punctuation** — single space around operators, no space inside parens, blank line between top-level statements.
- **Keyword conventions** — `OR REPLACE` always on its own line in `CREATE`, `IS`/`AS` always at end of line.
- **List wrapping** — column lists with >3 entries break, function arguments with >5 entries break, IN-clause lists always break if any element is itself a function call.
- **PL/SQL** — `EXCEPTION` handler indented to `BEGIN`, `END label` always present (warn if missing).
- **DDL** — column-name alignment in `CREATE TABLE`, constraint clauses on separate lines.

Each category as one `.scm` file. Users disable categories individually via Settings.

## 7. Architecture

```
parse tree            basic formatter Doc           rule engine                 final Doc            text
    │                       │                           │                          │                  │
    ▼                       ▼                           ▼                          ▼                  ▼
[NodePrinter]   ─►   [Doc] (default)   ─►   apply user/curated rules   ─►   [Doc] (final)   ─►   layout
                                              ↑
                                              │
                                       parsed *.scm rules
                                       (cached per file)
```

The pieces:

- **`RuleParser`** — reads `.scm` files and builds an AST of `(Query, [Directive])` pairs. Cached, invalidated on file change.
- **`RuleEngine`** — given a parse tree and the basic formatter's emitted Doc, runs each query against the tree, walks the matched captures, and applies directives to the Doc.
- **`AlignmentLayouter`** — the existing layouter, extended for `alignToColumn`.
- **`RulePreviewService`** — for the Settings UI; reformats a sample buffer with the candidate rule set and shows the diff.

## 8. Stages

### Stage 1: directive plumbing (1 week)

Extend Doc IR with `alignToColumn`, `forceMultiline`, `forceSingleline`, `appendHardline`, `prependHardline`. No user-facing rules yet; verify the basic formatter still works after the additions.

### Stage 2: hardcoded curated rules (1-2 weeks)

Ship the Macintora-style rules as Swift code first — they exercise the directive plumbing without depending on the rule parser. Settings UI exposes per-category toggles.

### Stage 3: rule parser + engine (2-3 weeks)

Parse `.scm` files via the existing tree-sitter query parser (we already use it for highlights). Map our directives onto its predicate/directive system. Apply at format time.

### Stage 4: workspace & user-global rule files (3-4 days)

`.macintora-format/*.scm` discovery, precedence (workspace > user > bundled), enable/disable via Settings.

### Stage 5: live preview UI (1 week)

Side-by-side diff in Settings as the user edits rules.

### Stage 6: rule sharing (1 week, optional)

`Export Rules…` / `Import Rules…` buttons. A simple Macintora rule pack as a JSON manifest pointing to one or more `.scm` files. Eventually a small online registry; not committing to that yet.

### Total

~6-8 weeks on top of the basic formatter. Mostly independent of the basic formatter once stage 1 lands.

## 9. Open questions

- **Predicate library.** Tree-sitter queries support `#eq?`, `#match?`, `#not-eq?`. We'll need `#count?`, `#starts-with?`, `#has-ancestor?`. Define the full set up front so users have a stable target.
- **Rule conflict resolution.** Two rules touch the same node — what happens? Last wins, or merge, or error? Decide once and document.
- **Sandboxing.** `.scm` files are declarative — no code execution risk. But predicate functions (if we allow user-defined ones) would be. Stage 6 (rule sharing) raises this question; punt until then.
- **Performance.** Running N user queries on every format is O(N × tree size). At reasonable N (10-50) and tree size (a few thousand nodes) this is microseconds. If users start writing hundreds of rules, we cache compiled queries and only re-run on relevant nodes. Profile first.
- **Discoverability.** Curated rules shipped on; user rules opt-in. If a user is hitting unwanted formatting, they need to know which rule did it. The "explain formatting" right-click action in §3 covers this — make sure it lands by stage 5.

## 10. Risks

- **Pattern-language scope creep.** Users will ask for conditionals, loops, variables. Resist. The DSL is for matching and emitting, not computing. Hard cases get a Swift extension point (separate proposal).
- **Round-trip parse.** Same as basic formatter: any rule that produces output that doesn't reparse to an equivalent tree is a bug. Enforce in CI.
- **Comment / hint preservation.** Even more critical than in the basic formatter, because user rules can move things around. The comment-stitching subsystem from `roadmap-basic-formatter.md` §3.4 needs to carry through; user directives apply *after* comments are placed.
- **Curated rule churn.** If we change a Macintora-style default in a minor release, users' files change. Treat it as a breaking change — major version bump, opt-in for new defaults via Settings.
- **Trivadis import.** Inevitably someone will ask for an importer that takes a `format.xml` from Trivadis and produces equivalent `.scm`. Worthwhile but distinctly more work than v1; flag for later.
