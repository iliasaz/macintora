# Roadmap: Jump-to-symbol (and back)

Cmd-click on a procedure call, table reference, or column to scroll the editor to its definition. `Ctrl-` (or `⌘[` like Xcode) returns to the previous location. Works inside the current buffer first; later, across the whole project; later still, into source pulled from `DBCache`.

---

## 1. Goal

When the user is reading PL/SQL and encounters `emp_pkg.hire(123)`, they should be able to:

1. Cmd-click the call (or invoke "Go to Definition" via keyboard) and have the editor jump to `PROCEDURE hire(...)` inside the open package body.
2. If `hire` lives in a different file in the project, open that file and jump.
3. If the file isn't in the project but is in `DBCache` (because the user browsed it via the DB browser at some point), open a read-only buffer with the cached source and jump.
4. Press `⌘[` to return to the call site.

The "back" behavior is essential — without it, deep navigation feels like falling into a hole.

## 2. Non-goals (v1)

- **Cross-schema resolution against the live DB** — if the symbol isn't in the buffer, the project, or the cache, we don't open a connection to look it up. The user can do that explicitly via the DB browser.
- **Resolving overloaded subprograms** — Oracle's overload rules are arity- and type-based; v1 picks the first match by name and warns if multiple exist.
- **Jump from a column reference to its column definition** — interesting but separate; depends on resolving the table first. Stage 5 maybe.
- **Find-all-references** — the inverse problem; out of scope here.

## 3. UX

- **Trigger:** Cmd-click on an identifier inside a call site or `object_reference`. Or `⌘-D` (similar to Xcode's "Jump to Definition") on the cursor's symbol.
- **Result:**
  - Same buffer: scroll, select the name, brief animated highlight.
  - Different buffer in the project: open in a new tab, scroll, select.
  - DBCache only: open a read-only buffer titled `[cached] schema.name`, scroll, select.
  - Not found: floating callout near the call site — "No definition found. Try refreshing the DB cache."
- **Back:** `⌘[`. Forward: `⌘]`. Status bar shows "← from line 142 of emp_pkg_body.pkb".
- **Multiple candidates:** popover list ranked by Oracle's name-resolution order (local → current schema → public synonyms).

## 4. Architecture

```
                user gesture (⌘-click | ⌘-D)
                          │
                          ▼
                  cursor position
                          │
                          ▼
              SymbolUnderCursorResolver   ← finds enclosing call-site / ref
                          │
                          ▼  bare name or pkg.name
                          ▼
                  SymbolIndex             ← project-wide cache of OutlineNodes
                          │
                ┌─────────┼─────────┐
                ▼                   ▼
          buffer hit         project file hit         DBCache hit
                │                   │                   │
                ▼                   ▼                   ▼
            scroll        open tab + scroll       open [cached] tab
                          │
                          ▼
              push current location onto NavigationStack
```

The pieces:

- **`SymbolUnderCursorResolver`** — given a `Tree` and a byte offset, walks up to find the smallest enclosing `invocation`, `object_reference`, or `plsql_procedure_call`, and returns the (qualifier, name) pair. Pure function.
- **`SymbolIndex`** — `@Observable` actor that holds:
  - For each open project file: the latest `[OutlineNode]` from the parse service.
  - For each `DBCache` cached package/procedure/function: the same shape, extracted by parsing the cached source on first request and memoizing.
  - Lookup: `func resolve(qualifier: String?, name: String) -> [SymbolHit]`. Returns hits in Oracle name-resolution order.
- **`NavigationStack`** — capped at ~50 entries. Holds `(URL, NSRange)` pairs. Exposed as commands `⌘[` and `⌘]`. Cleared when a buffer is closed (entries pointing to it are pruned, not crashing).
- **`SymbolHit`** — `(file: URL, nameRange: NSRange, kind: OutlineNode.Kind, qualifiedName: String, source: HitSource)`, `HitSource = .openBuffer | .projectFile | .dbCache`.

## 5. Resolution rules (Oracle name-resolution, simplified)

1. **Local PL/SQL scope.** If the cursor is inside a `create_procedure` / `create_function` / `package_procedure` / `package_function` / `plsql_block`, scan the enclosing scope for matching `plsql_declaration`s, `plsql_parameter`s, and nested subprogram declarations. Local wins over outer.
2. **Same package.** If the cursor is inside a `create_package_body`, also try the matching `create_package` spec for declarations not seen yet (forward references).
3. **Current schema.** Look in the project index for top-level `create_procedure`/`create_function`/`create_package` whose name matches.
4. **Qualified `pkg.name`** — look up the package, then the member.
5. **DBCache.** If steps 1-4 produce zero hits, query the cache.

If multiple hits result, present them in the popover ordered by the chain above (local first, cache last).

## 6. Tree-sitter pieces we'll use

The "what's the symbol under the cursor" walk hits these node shapes (already in `parsing-architecture.md` §5):

```scheme
;; Call expression: foo(arg, ...)
(invocation
  (object_reference
    schema: (identifier)?  @qualifier   ; nil for bare calls
    name:   (identifier)   @name)
  parameter: (term)?)

;; Bare procedure call (statement context):  foo(args);  or  pkg.foo;
(plsql_procedure_call
  (invocation … ))     ; same shape
(plsql_procedure_call
  (object_reference …))

;; Column / qualified-field reference:  pkg.col   or   t.col
(field
  (object_reference
    name: (identifier) @qualifier)
  name: (identifier) @name)
```

The "where is the definition in this file" lookup uses the queries from the **outline** roadmap doc — we walk the same `[OutlineNode]` list and match by name.

## 7. Stages

### Stage 1: In-buffer jump only (1-2 days)

Cmd-click resolves against the same buffer's outline. No project index, no DBCache. Press `⌘[` to go back. Perfectly useful for navigating a single package body — which is the highest-value case.

### Stage 2: Project index (3-4 days)

`ProjectIndexService` scans every `.sql`/`.pls`/`.pkb`/`.pks` under the project root, parses each on first read, builds a `[String: [OutlineNode]]` map keyed by qualified name. Watches the file system (`DispatchSource.makeFileSystemObjectSource`) for changes and invalidates entries.

Cross-file jumps now work. Multiple-hit popover lands here.

### Stage 3: DBCache integration (1-2 days)

When project lookup fails, query `DBCacheVM` for any cached package / procedure / function with matching name. Parse the cached source lazily, cache the resulting `[OutlineNode]` keyed by `schema.name`. Open a read-only `[cached]` buffer when the user picks a hit.

### Stage 4: Local PL/SQL scope (1-2 days)

Walk the enclosing subprogram for `plsql_declaration` and `plsql_parameter`. Local hits go to the popover above schema and cache hits.

### Stage 5: Forward navigation + history pane (0.5 day)

`⌘]` for forward. Optional history pane (`⌘-Y`?) showing the last N navigations.

### Stage 6: Column → definition (open-ended)

Resolve `t.col` to the table's `column_definition` named `col`. Requires alias resolution (`SELECT t.col FROM emp t`) — track `relation` aliases in the local SELECT scope. Worth it but not soon.

## 8. Open questions

- **What counts as "the project"?** Macintora is document-based, not folder-based. Options: (a) the directory containing the open file, (b) a user-configured project root in Settings, (c) the union of every file the user has opened in this app session. Lean toward (c) initially — zero config — and add (b) as an opt-in for users with a clear codebase root.
- **Live indexing vs. background scan.** Watching the FS adds complexity but keeps the index fresh. Alternative: re-scan on `applicationDidBecomeActive`. Probably good enough; revisit if it bites.
- **DBCache freshness.** Cache entries can be older than the live DB. Show "(cached)" in the title so the user isn't confused.
- **Keyboard shortcuts.** `⌘-D` is normally "duplicate" in Xcode-style apps; reuse `⌘-Click` and `⌃⌘-J`? Survey the user — match their muscle memory.

## 9. Risks

- **Name shadowing.** Package member named the same as a column named the same as a local variable. Resolution must walk the chain top-down and explain its choice when ambiguous (one-line annotation in the popover).
- **Misparses cascade.** A broken `CREATE PROCEDURE` mid-buffer can cause downstream symbols to disappear from the outline. Jump fails silently for those, which is confusing. Mitigation: on miss, always fall through to the next layer (project, cache) before giving up.
- **DBCache schema drift.** A cached package body parsed today may use grammar features added tomorrow. Re-parse on cache version bump; treat parse failure as "no hit, fall through."
- **Path-mapping for `[cached]` buffers.** Read-only window vs. real file. Make sure the user can't accidentally save it to disk; mark the document as "no file URL."
