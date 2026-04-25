# Roadmap: Outline view

A sidebar that lists the top-level objects in the current SQL/PL-SQL buffer (tables, views, indexes, sequences, synonyms, standalone procedures and functions, packages, package bodies, triggers) and, for packages and package bodies, the procedures, functions, and declarations inside them. Each entry is clickable to jump to the definition. Updates as the user types.

This document is a roadmap — it sketches what we'll build and how it sits on top of the existing tree-sitter parser. It does not lock the implementation.

---

## 1. Goal

Make the structure of a worksheet or `.pkb` file legible at a glance and one click away. Specifically:

- A user opens a 2,000-line package body and immediately sees the list of procedures and functions in a left pane. Clicking one scrolls the editor to its declaration and highlights the name.
- A user editing a worksheet with a dozen mixed `CREATE TABLE` and `CREATE OR REPLACE PROCEDURE` statements sees them all in order, with their kind icon (table / proc / fn / pkg).
- The outline tracks edits in real time. As the user adds a new procedure, it appears in the list within one parse cycle (sub-millisecond on typical buffers).

## 2. Non-goals (v1)

- **Cross-file outline** — that's the *project* outline; covered separately by the jump-to-symbol roadmap.
- **DB-side outline** — already exists as the DB browser; this is buffer-local.
- **Refactor / rename via outline** — out of scope; outline is read-only navigation.
- **Symbol filtering by visibility / scope** — every named symbol appears regardless of `PUBLIC` / private status; refining later.

## 3. UX

```
┌────────────────────────────────────────────────────────────┐
│  Outline                          ⌘1 to focus              │
├────────────────────────────────────────────────────────────┤
│  ▼ 📦 emp_pkg          (PACKAGE BODY)                       │
│      ⚙  hire           (procedure)                          │
│      ƒ  get_salary     (function → NUMBER)                  │
│      ƒ  is_manager     (function → BOOLEAN)                 │
│  ▼ 📋 emp_audit_log    (TABLE)                              │
│  ▼ 🪝 emp_before_ins   (TRIGGER on emp)                     │
│  ▼ ⚙  raise_salary     (PROCEDURE)                          │
└────────────────────────────────────────────────────────────┘
```

- Shown as a `NavigationSplitView` sidebar (SwiftUI). Toggle with `⌘1`.
- Each row: kind icon, name, optional one-line decoration (`→ NUMBER` for return type, `on emp` for trigger target).
- Disclosure triangles on packages and package bodies; flat at the top level for everything else.
- Clicking a row scrolls editor to the symbol's `nameRange` and selects the name. Double-click selects the entire construct (`range`).
- Sticky header in the editor showing the enclosing symbol's qualified name as you scroll — falls out of v1 unless cheap to add.

Search box at the top of the outline filters by name (case-insensitive `localizedStandardContains`). Filtering does not collapse the hierarchy — packages stay shown if any of their members matches.

## 4. Architecture

```
              tree-sitter parse tree
                        │
                        ▼
               OutlineExtractor          ← runs queries, walks tree
                        │
                        ▼
                  [OutlineNode]          ← Identifiable, tree-shaped
                        │
                        ▼
                OutlineViewModel         ← @Observable, applies filter
                        │
                        ▼
                  OutlineView            ← SwiftUI NavigationSplitView
                        │
                        ▼
              user click → NotificationCenter
                        │
                        ▼
            MacintoraEditor.Coordinator scrolls + selects
```

The pieces:

- **`SQLParseService`** — owns a `SwiftTreeSitter.Parser`, parses the buffer on each text change. Already sketched in `parsing-architecture.md` §3. The outline is one of several consumers of the resulting tree; the same tree feeds outline, jump-to-symbol, and completion (one parse, many uses).
- **`OutlineExtractor`** — pure function `(Tree, String) -> [OutlineNode]`. Runs the symbol queries listed in `parsing-architecture.md` §4.1 plus the package member sub-walk for `create_package_body`.
- **`OutlineNode`** — exactly the struct sketched in `parsing-architecture.md` §4.1.
- **`OutlineViewModel`** — `@Observable`, holds the current `[OutlineNode]` and the search text. Re-runs extraction whenever the parse completes; debounced if profiling shows it matters (likely not — extraction is microseconds).
- **`OutlineView`** — SwiftUI `List` with `DisclosureGroup` for packages. Selection wired to scroll-to-symbol via a notification or a callback closure.

## 5. Tree-sitter pieces we'll use

Direct quotes from `parsing-architecture.md` §4.1 and §5 — see those sections for the full node/field reference. The minimum viable query is reproduced here for self-containment:

```scheme
(create_table          (object_reference)               @symbol.table)
(create_view           (object_reference)               @symbol.view)
(create_index          name: (identifier)               @symbol.index)
(create_sequence       (object_reference)               @symbol.sequence)
(create_synonym        name: (object_reference)         @symbol.synonym)
(create_procedure      name: (object_reference)         @symbol.procedure)
(create_function       name: (object_reference)         @symbol.function)
(create_package        name: (object_reference)         @symbol.package)
(create_package_body   name: (object_reference)         @symbol.package.body)
(create_trigger        name: (object_reference)         @symbol.trigger)
```

Run that against the program node for top-level entries. For each `create_package` and `create_package_body` match, run a sub-query against that node's range:

```scheme
(plsql_subprogram_declaration name: (identifier)        @member.declaration)
(package_procedure            name: (identifier)        @member.procedure)
(package_function             name: (identifier)        @member.function)
```

Optional decorations:

- **Return type for functions** — read the `return_type:` field from `create_function` / `package_function` and `plsql_subprogram_declaration` (it's `(_type)` whose first leaf is the type name).
- **Trigger target** — read the second `object_reference` child of `create_trigger` (the table being triggered on).
- **Parameter count** — count `plsql_parameter` children of the `plsql_parameter_list` field. Useful for overload disambiguation in stage 4 (cross-file).

## 6. Stages

Each stage is independently shippable.

### Stage 1: Flat outline (1 day)

Top-level symbols only. No nesting under packages. No filter box. Click to scroll.

Ships value immediately for tables/views/triggers/standalone procs. Useful for worksheets with many DDL statements.

### Stage 2: Package member nesting (0.5 day)

Disclosure triangles for `create_package` and `create_package_body`. Sub-walk emits `package_procedure`/`package_function`/`plsql_subprogram_declaration` as children. Group spec and body together when both exist (match by name).

### Stage 3: Search/filter box (0.5 day)

`TextField` at the top, `localizedStandardContains` filtering, "no matches" state.

### Stage 4: Decorations + icons (0.5 day)

Kind icons (SF Symbols), return type annotations for functions, trigger target.

### Stage 5: Live cursor tracking (1 day, optional)

As the editor cursor moves, highlight the outline row whose `range` contains it. Implemented via a `selection` binding from the editor and a binary search on the outline list (sorted by start offset).

## 7. Open questions

- **Outline placement.** SwiftUI `NavigationSplitView` sidebar (matches DB browser layout), or a separate floating panel? Macintora's existing layout has a wide DB browser pane — the outline could be a tab next to it, or its own pane on the opposite side, or a popover. Decide once the first stage ships and we feel the ergonomics.
- **Scroll behavior.** Center the symbol in the viewport, or scroll the minimum amount to bring it into view? VS Code does the latter; Xcode does the former. Probably the latter — feels less jarring.
- **Empty buffer.** Show a hint ("Outline appears as you write SQL") or hide the sidebar when empty? Lean toward showing the hint so the panel doesn't flicker.

## 8. Risks

- **Parse error recovery cascades.** If the user is mid-typing in a half-finished `CREATE PROCEDURE`, the parser produces ERROR nodes that may swallow downstream definitions. Mitigation: even ERROR-bearing trees still surface most named children correctly because tree-sitter's recovery is local. Verify on a worst-case sample (mid-typed procedure followed by 20 well-formed packages — outline should show 20 + 1 package).
- **Outline churn while typing.** Adding a character inside an identifier shouldn't reorder the outline. Use stable IDs derived from byte offsets at the *start* of the symbol so SwiftUI's `id`-based diffing keeps row identity.
- **Large files.** A package body with 200 procedures is plausible. Outline rendering uses `LazyVStack` / `List` which only realizes visible rows; extraction itself is O(file size) and remains microseconds. No special handling needed.
- **Unicode names.** Quoted identifiers (`"My Proc"`) must round-trip through display. The grammar already produces them as `identifier` whose text is the literal `"…"` form including the quotes — outline display should strip the wrapping `"`s but preserve any embedded ones. Single function in `OutlineExtractor`.
