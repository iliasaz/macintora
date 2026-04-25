# Roadmap: Code completion

Context-aware autocomplete: as the user types, suggest column names where columns make sense, table names where tables make sense, package members after `pkg.`, in-scope PL/SQL variables inside a block, built-in functions almost everywhere, and SQL keywords as a last resort. Driven by the tree-sitter parse tree so the suggestions actually fit the grammar at the cursor.

---

## 1. Goal

The user types `SELECT empno, ` in a worksheet against the HR schema. A suggestion list appears anchored under the cursor showing `ename`, `sal`, `hiredate`, `deptno`, … filtered as they keep typing. They press `Tab` (or `Return`) to accept.

Inside a PL/SQL procedure body, after typing `v_`, the list shows local variables declared above the cursor in the enclosing block, with their declared types as decorations. After `emp_pkg.`, the list shows the public members of `emp_pkg` — extracted from either the open package spec, a project file, or `DBCache`.

The acceptance bar: **suggestions feel relevant rather than alphabetical**. Showing 3 right things beats showing 300 keywords.

## 2. Non-goals (v1)

- **Type inference for expressions.** "What's the type of `x + 1`?" requires a small typer; not yet.
- **Snippet completion** with parameter placeholders (`SELECT ${1:col} FROM ${2:table}`). Useful, deferrable.
- **Auto-import.** N/A for SQL.
- **AI completion.** Different feature, different doc.

## 3. UX

- **Trigger:** typing `.` after an `object_reference` always opens the popover. Typing 2+ identifier characters opens it after a brief debounce. `⌃-Space` forces it open.
- **Popover:** anchored under the typed prefix, list of candidates with kind icon (column, table, function, variable, keyword), one-line decoration (column type, function signature, variable's declared type).
- **Acceptance:** `Tab` or `Return` inserts the match. `Esc` dismisses. Arrow keys navigate.
- **Sorting:** strict relevance order — local scope first, then current-schema, then DBCache, then built-ins, then keywords. Within a tier, exact-prefix matches before substring matches; ties broken alphabetically.
- **Filtering:** case-insensitive `localizedStandardContains` on the typed prefix (Oracle bare-identifier semantics). Quoted-identifier completions only show when the prefix starts with `"`.
- **No auto-trigger** inside string literals, comments, marginalia, or hints. The leaf node tells us — see §5.

## 4. Architecture

```
   keystroke           cursor offset
        │                  │
        └──────┬───────────┘
               ▼
    CompletionContext       ← what is allowed here?
               │   (computed from the parse tree)
               ▼
    [CandidateSource]       ← built-ins, schema, package, locals, keywords
               │   (sources are independent and parallel)
               ▼
       merge + rank
               │
               ▼
    CompletionPopover       ← SwiftUI overlay on STTextView
```

The pieces:

- **`CompletionContext`** — a value enum (`selectColumns(of:)`, `tableName`, `qualifiedAfter(prefix:)`, `plsqlExpression(scope:)`, `plsqlStatement(scope:)`, `noCompletion`) computed from the parse tree at the cursor. See `parsing-architecture.md` §4.3 for the switch logic.
- **`CandidateSource`** — protocol: `func candidates(for: CompletionContext, prefix: String) async -> [Candidate]`. Sources:
  - `KeywordSource` (static list, instant)
  - `BuiltinFunctionSource` (static list, instant)
  - `BufferSymbolsSource` (uses the current buffer's outline + visible PL/SQL scope)
  - `ProjectSymbolsSource` (uses `SymbolIndex` from jump-to-symbol)
  - `DBCacheSchemaSource` (queries `DBCacheVM` for table & column names of the connection)
  - `DBCachePackageSource` (queries cache for package members)
- **`Candidate`** — `(text: String, kind: Kind, decoration: String?, sortKey: Int)`. Kind drives the icon.
- **`CompletionEngine`** — `@MainActor` actor that computes the context, fans out to sources, debounces by ~80 ms, and republishes the merged list to the popover.
- **`CompletionPopover`** — SwiftUI view in an `NSPanel` anchored under the cursor; existing Macintora code already places `NSPanel`s for the DB browser overlay, reuse that.

## 5. Tree-sitter pieces we'll use

### Cursor context detection

Walk from the leaf at the cursor up the ancestor chain. The first matching ancestor wins:

| Ancestor node | Context |
|---------------|---------|
| `string`, `_literal_string`, `comment`, `marginalia`, `hint`, `hint_line` | `noCompletion` |
| `object_reference` whose preceding char is `.` | `qualifiedAfter(prefix: textBefore)` |
| `select_expression`, `term` | `selectColumns(of: enclosingFromTables(node))` |
| `from`, `relation` (in the table position) | `tableName` |
| `where`, `having`, `group_by`, `order_by` | `selectColumnsAndFunctions` |
| `plsql_assignment`, `plsql_return`, `plsql_if condition`, `plsql_for_loop` | `plsqlExpression(scope: enclosingSubprogram(node))` |
| `plsql_block`, `plsql_block.declare_section` | `plsqlStatement(scope: …)` |
| `column_definitions` | `dataType` |
| Default | `topLevelStatement` |

For `qualifiedAfter`, the prefix is the text of the qualifier identifier; the source is `pkg.` so the engine fetches package members for `pkg`.

### Source queries

**In-scope PL/SQL variables** (run on the smallest enclosing `create_procedure` / `package_procedure` / `plsql_block` that contains the cursor — *not* the whole tree):

```scheme
(plsql_declaration
  name: (identifier) @local.var
  type: (_)         @local.var.type)

(plsql_parameter
  name: (identifier) @param.name
  type: (_)         @param.type)
```

Then filter to declarations whose `range.upperBound <= cursorOffset` (only "above the cursor" wins; PL/SQL is sequential).

**Package members** (run on a `create_package` or `create_package_body` node — possibly from another file or `DBCache`):

```scheme
(package_procedure                  name: (identifier) @member.proc)
(package_function                   name: (identifier) @member.func)
(plsql_subprogram_declaration       name: (identifier) @member.decl)
(plsql_declaration                  name: (identifier) @member.var)
```

**Visible tables in the current SELECT** (used for column completion). Walk the enclosing `from` clause's `relation` children:

```scheme
(from
  (relation
    (object_reference name: (identifier) @table)))
```

For aliased relations the alias matters — we'll track it later (stage 4).

## 6. Stages

### Stage 1: Keywords + built-ins (1 day)

Static lists. Trigger after 2 chars. No context awareness — same list everywhere except inside strings/comments. Even this beats nothing because keyword case completion alone helps users typing `varc` → `VARCHAR2`.

### Stage 2: Buffer-local PL/SQL completion (2 days)

Add `BufferSymbolsSource`. Inside a procedure body, suggest in-scope variables and parameters. Use the parse tree's `plsql_declaration` / `plsql_parameter` walk above.

Self-contained — no DB connection, no project index needed. Highest signal-to-noise improvement after stage 1.

### Stage 3: Schema-object completion (3-4 days)

Wire `DBCacheSchemaSource` and `DBCachePackageSource` to `DBCacheVM`. After `FROM `, suggest tables. After `pkg.`, suggest package members. Type-aware columns after `SELECT`/`WHERE`/`SET`/`ON`.

This is where the feature graduates from "nice to have" to "I can't work without it."

### Stage 4: Alias-aware column completion (1-2 days)

`SELECT t.| FROM emp t` should suggest `emp`'s columns. Track aliases declared in the enclosing `from` clause and rewrite the qualifier before lookup.

### Stage 5: Snippets (1-2 days, optional)

A small library of canned templates (`csel` → `SELECT … FROM … WHERE …` with placeholders). Tab-step through placeholders. Stored in `Settings/Snippets.json`.

### Stage 6: Project symbol completion (0.5 day, builds on jump-to-symbol §7.2)

Once `SymbolIndex` exists (from jump-to-symbol stage 2), `ProjectSymbolsSource` is a thin wrapper — call `index.resolve(prefix: …)` and emit candidates.

## 7. Open questions

- **Should typing inside a quoted identifier change behavior?** In Oracle, `"My Col"` is case-sensitive. If the user opens `"`, switch to a quoted-identifier completion that matches case-sensitively against quoted versions of the candidates. Edge case but easy.
- **Async sources and stale results.** `DBCacheSchemaSource` may take 10-50 ms; the user is still typing. Use a generation counter; results from an older generation are dropped. Standard pattern, no surprise.
- **Default for SELECT *.** Should `SELECT *` ever get column completion? Probably no — `*` means "everything," nothing to complete. But `SELECT t.*` ✓.
- **Trigger latency.** 80 ms debounce was the gut estimate. Re-tune after profiling. Anything <120 ms feels instant.
- **Where does the popover live?** SwiftUI overlay on `STTextView` works, but `NSPanel` gives better keyboard handling. Pick whichever the existing DB browser uses.

## 8. Risks

- **Wrong context = wrong list = user disables completion.** The single biggest risk. Mitigation: an explicit "don't show completion here" list (`noCompletion` in §5) and a default that errs on the side of *not* triggering. Better silent than wrong.
- **Performance under typing.** Each keystroke runs context detection + filtering. Filtering must be O(candidates × prefix) on the merged list — no per-source rescans. Cache merged candidates; filter incrementally.
- **DBCache thrashing.** First completion against a large schema will warm the cache. Subsequent should be instant. Profile and add a "fetching schema…" state if the first hit takes >200 ms.
- **Name shadowing.** Same name appears in local scope and as a package member. Show both, with their source label, ordered local-first (Oracle's resolution order).
- **Quoted identifier edge cases.** `"select"` is a valid quoted identifier in Oracle. Make sure the candidate list never strips the quotes from a quoted-identifier candidate.
