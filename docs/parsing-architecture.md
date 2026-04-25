# Tree-sitter SQL/PL-SQL parsing in Macintora

This document explains how Oracle SQL and PL/SQL are parsed inside Macintora, what the grammar produces, and how to use those parse trees to build outline / jump-to-symbol / code completion. It is written for whoever ends up implementing those features.

---

## 1. The integration chain

Three repositories cooperate. All three live as siblings under `~/Developer/`:

```
tree-sitter-sql-orcl/        ← the grammar (JavaScript + generated C)
STTextView-Plugin-Neon/      ← Swift Package wrapping the parser for STTextView
Macintora/                   ← consumer
```

### `tree-sitter-sql-orcl`

A tree-sitter grammar for Oracle SQL **and** PL/SQL in a single parser. Seeded from [`DerekStride/tree-sitter-sql`](https://github.com/DerekStride/tree-sitter-sql) (ANSI baseline) and extended with Oracle dialect. Repo: `https://github.com/iliasaz/tree-sitter-sql-orcl`.

What it produces:

- A C parser exposed as `tree_sitter_sql_orcl()` (returns `const TSLanguage *`).
- `queries/highlights.scm` for syntax highlighting.
- A node-typed parse tree (see Section 5 for the catalogue).

Authoring workflow:

```sh
cd ~/Developer/tree-sitter-sql-orcl
# edit grammar.js / grammar/*.js
tree-sitter generate                        # regenerates src/parser.c
tree-sitter test                            # runs corpus in test/corpus/
tree-sitter parse path/to/sample.sql        # quick sanity parse
tree-sitter highlight path/to/sample.sql    # visual highlight check
```

The generated `src/parser.c`, `src/grammar.json`, `src/node-types.json` are committed so SPM consumers don't need the CLI.

### `STTextView-Plugin-Neon`

A fork of [`krzyzanowskim/STTextView-Plugin-Neon`](https://github.com/krzyzanowskim/STTextView-Plugin-Neon). It vendors a number of tree-sitter grammars as Swift Package targets and wires them into a `NeonPlugin` that drives incremental syntax highlighting on `STTextView`.

For Oracle, two targets:

- `TreeSitterSQLOrcl` — the C parser (`parser.c` + `scanner.c` + `parser.h` + `public.h` declaring `tree_sitter_sql_orcl()`).
- `TreeSitterSQLOrclQueries` — bundles `highlights.scm` as a resource and exposes `Query.highlightsFileURL`.

Both are registered in `Sources/TreeSitterResource/TreeSitterLanguage.swift` as the `.sqlOrcl` enum case.

### `Macintora`

`Macintora/Editor/EditorLanguage.swift` maps the app-level cases `.sql` and `.plsql` to `NeonPlugin(theme:, language: .sqlOrcl)`. The plugin is installed on `STTextView` inside `Macintora/Editor/MacintoraEditor.swift`'s `NSViewRepresentable.makeNSView`.

End-to-end: the editor's text is incrementally parsed by tree-sitter on every keystroke; `highlights.scm` captures are matched against the tree; Neon applies the styles.

---

## 2. Refreshing the grammar

When the grammar changes:

```sh
cd ~/Developer/tree-sitter-sql-orcl
# edit grammar.js / grammar/*.js, add corpus tests in test/corpus/
tree-sitter generate
tree-sitter test    # all should pass
git add -A && git commit && git push

# Re-vendor the four files into the plugin:
cp src/parser.c                 ../STTextView-Plugin-Neon/Sources/TreeSitterSQLOrcl/src/parser.c
cp src/scanner.c                ../STTextView-Plugin-Neon/Sources/TreeSitterSQLOrcl/src/scanner.c
cp src/tree_sitter/parser.h     ../STTextView-Plugin-Neon/Sources/TreeSitterSQLOrcl/src/tree_sitter/parser.h
cp queries/highlights.scm       ../STTextView-Plugin-Neon/Sources/TreeSitterSQLOrclQueries/highlights.scm
cd ../STTextView-Plugin-Neon
swift build         # sanity check
git add -A && git commit && git push

# Rebuild Macintora — Xcode picks up the local SPM dep automatically.
```

If you add or remove a *named* node type (e.g. introduce `cursor_declaration`), update `queries/highlights.scm` accordingly, otherwise tree-sitter will refuse to load the query file with `Invalid node type "..."`. A quick way to find orphan captures:

```sh
python3 -c "
import json, re
types = {n['type'] for n in json.load(open('src/node-types.json'))}
content = re.sub(r';;.*', '', open('queries/highlights.scm').read())
referenced = set(re.findall(r'keyword_[a-z0-9_]+', content))
for o in sorted(referenced - types): print(o)
"
```

---

## 3. Reaching the parse tree from Swift

Today the parse tree lives inside `STTextView-Plugin-Neon`'s `Coordinator`, which is private. To use the tree for outline / jump / completion you have two options:

### Option A — own a second parser in Macintora (recommended)

Cheap. Tree-sitter parsers are reentrant and the Oracle SQL parse is fast (~10 MB/s). Create a small service:

```swift
import SwiftTreeSitter
import TreeSitterSQLOrcl

@MainActor
final class SQLParseService {
    private let parser = Parser()
    private let language: SwiftTreeSitter.Language

    init() throws {
        language = Language(language: tree_sitter_sql_orcl())
        try parser.setLanguage(language)
    }

    /// Parse a buffer fresh. For incremental edits use `TreeSitterClient`
    /// (already a transitive dep via Neon) which keeps a tree across edits.
    func parse(_ text: String) -> Tree? {
        return parser.parse(text)
    }
}
```

`SwiftTreeSitter` and `TreeSitterSQLOrcl` are already on the dependency graph because Macintora depends on `STTextView-Plugin-Neon`, which depends on both. You do **not** need to add new SPM dependencies — you just need to import them.

If you want to share the tree with the editor (avoid double-parsing), expose the existing `TreeSitterClient` from `Coordinator`. That requires editing the plugin. Start with Option A; promote later if profiling shows it matters.

### Option B — incremental tree via TreeSitterClient

```swift
import TreeSitterClient

let client = try TreeSitterClient(language: language) { codePointIndex in
    // Map Tree-sitter UTF-16 offsets back into your buffer.
    return Point(row: ..., column: ...)
}
client.willChangeContent(in: range)
client.didChangeContent(in: range, delta: delta, limit: ..., readHandler: ..., completionHandler: { tree in ... })
```

This is the pattern used by Neon's `Coordinator.swift`. Use it if you need to react to every keystroke without reparsing the whole file.

### Common operations on a `Tree`

```swift
guard let tree = parser.parse(text) else { return }
let root = tree.rootNode!                       // (program ...)

// Walk children
let cursor = root.treeCursor
cursor.gotoFirstChild()
repeat {
    let node = cursor.currentNode!
    let kind = node.nodeType                     // e.g. "create_package_body"
    let nameField = node.childByFieldName("name")
    let text = nameField.flatMap { String(textFromBuffer: text, range: $0.range) }
    // ...
} while cursor.gotoNextSibling()

// Or run a query — preferred for symbol-extraction
let queryString = #"(create_package_body name: (object_reference) @pkg.name)"#
let query = try language.query(source: queryString)
let cursor = query.execute(node: root, in: text)
for match in cursor {
    for capture in match.captures {
        // capture.name == "pkg.name"; capture.node has the range
    }
}
```

Tree-sitter offsets are byte offsets (UTF-8). `String.Index` conversion utilities live in `Macintora/Editor/EditorSelectionBridge.swift` — reuse those for cursor mapping.

---

## 4. Implementation recipes

### 4.1 Outline / symbol navigation

Goal: a sidebar showing all top-level objects in the buffer plus the subprograms inside packages, with click-to-jump.

**Symbols to surface** (named-node types from the grammar):

| Node type | What it is | Name field |
|-----------|------------|------------|
| `create_table` | DDL table | `object_reference` (no field name; first `object_reference` child) |
| `create_view` | DDL view | first `object_reference` child |
| `create_index` | DDL index | `name` |
| `create_sequence` | DDL sequence | first `object_reference` child |
| `create_synonym` | DDL synonym | `name` |
| `create_procedure` | top-level standalone procedure | `name` |
| `create_function` | top-level standalone function | `name` |
| `create_package` | package spec | `name` |
| `create_package_body` | package body | `name` |
| `package_procedure` | procedure inside `create_package_body` | `name` |
| `package_function` | function inside `create_package_body` | `name` |
| `plsql_subprogram_declaration` | forward-decl in package spec | `name` |
| `create_trigger` | trigger | `name` |

**The query** (drop into `queries/tags.scm` later, or pass inline):

```scheme
;; Top-level
(create_table
  (object_reference) @symbol.table)

(create_view
  (object_reference) @symbol.view)

(create_index
  name: (identifier) @symbol.index)

(create_sequence
  (object_reference) @symbol.sequence)

(create_synonym
  name: (object_reference) @symbol.synonym)

(create_procedure
  name: (object_reference) @symbol.procedure)

(create_function
  name: (object_reference) @symbol.function)

(create_package
  name: (object_reference) @symbol.package)

(create_package_body
  name: (object_reference) @symbol.package.body)

(create_trigger
  name: (object_reference) @symbol.trigger)

;; Nested in package spec
(plsql_subprogram_declaration
  name: (identifier) @symbol.member.declaration)

;; Nested in package body — note: structurally these are flat children
;; of create_package_body, no recursion needed.
(package_procedure
  name: (identifier) @symbol.member.procedure)

(package_function
  name: (identifier) @symbol.member.function)
```

**Outline data structure**:

```swift
struct OutlineNode: Identifiable {
    let id = UUID()
    let kind: Kind
    let name: String            // text from the name node
    let qualifiedName: String   // "pkg.member" for nested, "name" for top-level
    let range: Range<String.Index>     // span of the whole construct
    let nameRange: Range<String.Index> // span of the name itself (jump target)
    var children: [OutlineNode] = []
    enum Kind { case table, view, index, sequence, synonym, procedure, function,
                  package, packageBody, trigger, packageMember(MemberKind) }
    enum MemberKind { case procedure, function, declaration }
}
```

**Build it**: run the query above against the root node. Top-level matches become roots in the outline. For each `create_package_body` match, run a sub-query against that node to collect `package_procedure` / `package_function` children — those become its `children`.

`name` is the `name` field's text (use the byte range of the node). `qualifiedName` for a member is `"\(packageName).\(memberName)"`.

For `create_package_body`, group it under its matching `create_package` if both exist in the file (match by `name` text).

**Persistence as the user types**: re-run the query on each parse. Don't try to incrementally update the outline; rebuilding takes microseconds compared to UI cost.

### 4.2 Jump-to-symbol

Two flavours:

- **Local jump** (jump within the current buffer): pick a symbol from the outline → scroll editor to `nameRange`. Implement on top of the outline; nothing extra.

- **Cross-file jump** (jump from a call site to a definition): walk every callable expression and resolve it.

Call-site nodes to recognize:

- `plsql_procedure_call` → its `invocation` child has an `object_reference` which is the (possibly qualified) procedure name.
- `invocation` inside an expression → also a function call; same shape.
- `(field (object_reference) name: (identifier))` — qualified column or qualified function call (`pkg.fn`).

**Procedure**:

1. Build a project-wide symbol table (file path → list of `OutlineNode`s) by parsing every `.sql` / `.pls` / `.pkb` file once and caching.
2. On "jump to definition" gesture (Cmd-click), find the smallest node containing the cursor. If it's an identifier inside an `object_reference` inside an `invocation` or `plsql_procedure_call`, resolve the name.
3. Resolution: if `pkg.fn`, look up the package, then its `package_function` / `package_procedure` named `fn`. If bare `fn`, look up top-level `create_procedure` / `create_function` named `fn`, then fall back to package members named `fn` (Oracle name resolution rules — public synonyms last).

The DB browser already caches package source via `DBCache*`. Reuse that cache for resolution against database objects the user hasn't opened in a buffer.

### 4.3 Code completion

Two pieces: **what** to complete (the candidate list) and **when** to complete (the trigger context).

**Trigger context**: find the smallest node containing or immediately preceding the cursor. From there walk up to find the enclosing rule:

```swift
func contextAt(cursor: Int, in tree: Tree, text: String) -> CompletionContext? {
    guard let leaf = tree.rootNode?.descendant(in: cursor..<cursor) else { return nil }
    var n: Node? = leaf
    while let cur = n {
        switch cur.nodeType {
        case "select_expression":              return .selectColumns(of: enclosingFrom(cur))
        case "from", "relation":               return .tableName
        case "where", "having":                return .columnOrFunction
        case "plsql_assignment":               return .expression(targetType: ...)
        case "plsql_block":                    return .plsqlStatementOrVariable(scope: visibleVarsIn(cur))
        case "create_package_body":            return .packageBodyMember
        case "object_reference":               return .qualifiedAfterDot(prefix: textOf(cur))
        // ...
        default: n = cur.parent
        }
    }
    return nil
}
```

**Candidate sources** (combine):

- **Built-in SQL functions / operators** — static list (parse once from Oracle docs at `~/Downloads/oracle-database_26_20260327/content/sqlrf/About-SQL-Functions.html` if you want to be exhaustive, or hand-curate the common ones).
- **Reserved words / keywords** — list from `~/Downloads/oracle-database_26_20260327/content/sqlrf/Oracle-SQL-Reserved-Words-and-Keywords.html`.
- **Schema-qualified objects** — query the DB via the already-existing `DBCacheVM`. Tables for `FROM`/`UPDATE`, columns for `SELECT`/`WHERE`/`SET`.
- **Package members** — when the user types `pkg.`, parse the package source from cache and offer its `package_procedure` / `package_function` / declared variables.
- **In-scope PL/SQL variables** — walk back from the cursor inside the enclosing `plsql_block` or `create_procedure`/`create_function`/`package_procedure`/`package_function` and collect every `plsql_declaration name: (identifier)` and every `plsql_parameter name: (identifier)` in the parameter list. Their declared types live in the `type:` field.
- **In-scope cursor variables, exception names** — same walk; not yet structurally distinct (deferred grammar work — see Section 6).

**Useful queries**:

```scheme
;; All visible variables in the current procedure / package body subprogram
;; (run this at the cursor's enclosing subprogram node, not at the root).
(plsql_declaration
  name: (identifier) @local.var
  type: (_) @local.var.type)

(plsql_parameter
  name: (identifier) @param.name
  type: (_) @param.type)

;; Package members for `pkg.|` completion (run on the package body / spec node)
(package_procedure name: (identifier) @member.proc)
(package_function name: (identifier) @member.func)
(plsql_subprogram_declaration name: (identifier) @member.decl)

;; Call site context (cursor inside an invocation argument list)
(invocation
  (object_reference name: (identifier) @callee)
  parameter: (term) @arg)
```

For the "after a dot" prefix completion, stop at the first `object_reference` ancestor and look at its preceding `identifier` child. The text up to the cursor is the partial name; filter candidates by it case-insensitively (Oracle-style — bare identifiers are case-insensitive, quoted are case-sensitive).

**Don't auto-complete**: when the cursor is inside a `(string)` literal, a `(comment)`, a `(marginalia)`, or a `(hint)`. The grammar makes that easy — just check the leaf node's type.

---

## 5. Reference: named nodes and fields

This is the practical subset you'll touch. Run `tree-sitter parse` on a sample to see the full shape; this catalogue lists what the recipes above use.

### Top-level DDL

| Node | Fields | Notes |
|------|--------|-------|
| `create_table` | (no `name` field — first `object_reference` is the table) | |
| `create_view` | first `object_reference` is the view | |
| `create_index` | `name: (identifier)` | |
| `create_sequence` | first `object_reference` is the sequence; clauses include `start`/`increment`/`cache`/`nocache`/`nocycle` literals | |
| `create_synonym` | `name: (object_reference)`, `target: (object_reference)` | also handles `PUBLIC` modifier as bare `keyword_public` child |
| `create_procedure` | `name: (object_reference)`, `end_label: (identifier)`, optional `plsql_parameter_list`, `plsql_authid_clause` | body is a flat sequence: `keyword_begin` → statements → optional `plsql_exception_section` → `keyword_end` |
| `create_function` | as above plus `return_type:` | also accepts `keyword_deterministic`, `keyword_pipelined` after the return type |
| `create_package` | `name: (object_reference)`, `end_label: (identifier)`, child `_package_spec_item`s: `plsql_declaration` and `plsql_subprogram_declaration` | |
| `create_package_body` | `name: (object_reference)`, `end_label: (identifier)`, child `_package_body_item`s: `plsql_declaration`, `package_procedure`, `package_function`; optional trailing init `BEGIN ... END` | |
| `create_trigger` | `name: (object_reference)`, `timing:` (`keyword_before`/`keyword_after`/`INSTEAD OF`), one or more `_create_trigger_event` children, target `object_reference`, optional `keyword_referencing` clause, optional `FOR EACH ROW`, optional `WHEN (...)`, body `plsql_block` | |

### PL/SQL bodies

| Node | Fields | Notes |
|------|--------|-------|
| `plsql_block` | optional `plsql_declare_section`, `keyword_begin`, statements, optional `plsql_exception_section`, `keyword_end`, optional `label: (identifier)` | |
| `plsql_declare_section` | `keyword_declare`, repeat `plsql_declaration` | |
| `plsql_declaration` | `name: (identifier)`, optional `keyword_constant`, `type: (_)`, optional `value: (_expression)` | |
| `plsql_parameter_list` | repeat `plsql_parameter` | |
| `plsql_parameter` | `name: (identifier)`, optional `plsql_parameter_mode`, optional `keyword_nocopy`, `type:`, optional `default:` | mode is `IN` / `OUT` / `IN OUT` / `INOUT` |
| `plsql_authid_clause` | `keyword_authid`, then `keyword_current_user` or `keyword_definer` | |
| `plsql_subprogram_declaration` | `name: (identifier)`, optional `plsql_parameter_list`, for functions also `return_type:` | forward-decl in a spec; ends with `;` |
| `package_procedure` | `name: (identifier)`, `plsql_parameter_list`, body, `end_label:` | nested inside `create_package_body` |
| `package_function` | as above plus `return_type:` | |

### PL/SQL statements

| Node | Fields | Notes |
|------|--------|-------|
| `plsql_assignment` | `target:` (identifier or qualified field), `value: (_expression)` | |
| `plsql_if` | `condition:`, then-branch as flat siblings, optional `plsql_elsif`s, optional `plsql_else` | |
| `plsql_basic_loop` | repeat statements | |
| `plsql_for_loop` | `index: (identifier)`, optional `keyword_reverse`, `low:`, `high:` | range uses the `..` token |
| `plsql_while_loop` | `condition:` | |
| `plsql_return` | optional `value:` | |
| `plsql_raise` | optional `exception: (identifier)` | |
| `plsql_null` | just `keyword_null` | |
| `plsql_exit` / `plsql_continue` | optional `label:`, optional `WHEN condition:` | |
| `plsql_procedure_call` | child `invocation` or bare `object_reference` | |
| `plsql_exception_section` | `keyword_exception`, repeat `plsql_exception_handler` | |
| `plsql_exception_handler` | `exception:` (identifier or `keyword_others`), then statements | |

### Expressions and supporting

| Node | Notes |
|------|-------|
| `invocation` | `object_reference` (callee) + zero-or-more `parameter: (term)` children |
| `object_reference` | `database:`, `schema:`, `name:` fields (only `name:` is required) |
| `field` | `name: (identifier)`, optionally preceded by an `object_reference` for `pkg.col` |
| `identifier` | bare, double-quoted (`"My Col"`), backtick (legacy MySQL), `@param` (T-SQL), or `:name` (Oracle bind / trigger pseudorecord — `:new`, `:old`) |
| `literal` | wraps `_integer`, `_decimal_number`, `_literal_string`, `_alternative_quote_string` (`q'[…]'`), keyword booleans / null / SYSDATE-as-default |
| `pseudocolumn` | wraps `keyword_sysdate`, `keyword_systimestamp`, `keyword_rownum`, `keyword_rowid`, `keyword_level` |
| `hint` / `hint_line` | optimizer hints; sit in `extras` (free-floating like comments) |
| `comment` / `marginalia` | line and block comments |

### Highlight capture groups (in `highlights.scm`)

`@keyword`, `@keyword.repeat`, `@keyword.exception`, `@keyword.operator`, `@keyword.conditional`, `@type.builtin`, `@variable`, `@variable.builtin`, `@string`, `@number`, `@float`, `@boolean`, `@function.call`, `@field`, `@parameter`, `@operator`, `@punctuation.bracket`, `@punctuation.delimiter`, `@comment`, `@comment.documentation` (for hints), `@attribute`, `@storageclass`, `@type.qualifier`.

---

## 6. Known limitations and TODOs

These are intentional v1 trade-offs. Track them as follow-ups.

| Limitation | Impact | Workaround / Fix |
|-----------|--------|------------------|
| Top-level `BEGIN ... COMMIT; END;` parses as a `transaction`, not a `plsql_block`. | Anonymous block ending in `COMMIT;` followed immediately by `END;` shows as a transaction. | Add `DECLARE` at the top of the block. The DDL CREATE-PROCEDURE/FUNCTION/PACKAGE/TRIGGER bodies are unaffected. |
| Named-argument call `foo(p_id => 1)` is parsed as a nested `binary_expression` ending in `>`, not as a discrete `named_argument`. | Highlighting is correct (tokens still color); structural queries can't easily extract argument names. | Add a `named_argument` rule in the grammar. ~10-line change. |
| Cursor declarations, `%TYPE` / `%ROWTYPE`, RECORD types, collections (VARRAY, TABLE OF), nested user-defined types are not yet structured. | Auto-complete can't look up cursor row column names; type-aware suggestions limited to scalar declarations. | Extend `plsql_declaration` to include these forms. |
| `EXECUTE IMMEDIATE`, `OPEN ... FOR`, `FETCH`, `CLOSE` are not yet structured PL/SQL statements. | They parse as opaque tokens inside a block (highlighted but not navigable). | Add explicit rules under `_plsql_statement`. |
| `CREATE TYPE` / `CREATE TYPE BODY` for object-oriented PL/SQL is deferred. | Object-typed schemas don't get structural parsing for the type bodies. | Mirror the package body rules. |
| SQL\*Plus directives (`SET`, `SPOOL`, `COLUMN`, `&substitution_var`) are not parsed. | Worksheets that lead with `SET PAGESIZE 100` will see one ERROR node before recovering. | Either add a permissive `sqlplus_directive` rule or pre-strip these lines in the editor before highlighting. |
| `q'X…X'` Oracle alt-quote with arbitrary single-character delimiter (e.g. `q'!hello!'`) is not supported; only the bracket forms (`[]`, `{}`, `()`, `<>`) are. | Rare in practice; the parser produces an ERROR around `q'!`. | Requires an external scanner (RE2 has no back-references). |
| `ORDER SIBLINGS BY` is not yet a separate rule (the keyword is defined but unused). | `siblings` parses as an identifier inside the `order_by` clause. | Trivial grammar addition. |
| `PIVOT` / `UNPIVOT` clauses are not parsed. | `SELECT … FROM t PIVOT (…)` produces ERROR nodes around the PIVOT block. | Add a `pivot_clause` / `unpivot_clause` rule under `relation`. |

---

## 7. Quick start: probe the parse tree

The fastest way to see what a buffer parses into:

```sh
cd ~/Developer/tree-sitter-sql-orcl
echo "CREATE OR REPLACE PACKAGE BODY emp_pkg AS
  PROCEDURE hire(p_id IN NUMBER) IS
  BEGIN INSERT INTO emp (empno) VALUES (p_id); END hire;
END emp_pkg;" | tree-sitter parse -
```

For the highlight view:

```sh
tree-sitter highlight some_oracle.sql
```

For exploring node names interactively:

```sh
tree-sitter playground   # opens a local web playground
```

When implementing outline / jump / completion, this loop is your friend: write the SQL you care about, parse it, eyeball the tree, then write the matching tree-sitter query.
