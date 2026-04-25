# Roadmap: Basic formatter

Pretty-print the current SQL/PL-SQL buffer or selection. Native Swift, driven by the tree-sitter AST, no external process. Configurable but opinionated. The goal is "good enough that users reach for `⌘-Shift-I` for everyday cleanup and don't shell out to an external tool."

---

## 1. Goal

```sql
-- Before
select empno,ename,sal from emp where deptno=10 and hiredate>date '2020-01-01' order by sal desc;

-- After (default config)
SELECT empno,
       ename,
       sal
  FROM emp
 WHERE deptno = 10
   AND hiredate > DATE '2020-01-01'
 ORDER BY sal DESC;
```

Same idea for `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `CREATE TABLE`, anonymous PL/SQL blocks, and `CREATE PROCEDURE`/`FUNCTION`/`PACKAGE`/`PACKAGE BODY`/`TRIGGER` headers.

User-facing surface:

- **`⌘-Shift-I`** — format the entire buffer.
- **`⌘-Option-I`** — format the current selection only.
- **Format on save** — opt-in toggle in Settings.
- **Settings → Formatter:** indent width, comma style (leading/trailing), keyword case, max line width, blank lines between statements.

## 2. Non-goals (v1)

- **Aligning equals signs**, comma-aligning column names in DDL, or other column-aware alignment styles. They're popular but require a different approach (alignment columns, not just doc IR). Pushed to the *advanced formatter*.
- **User-defined patterns.** Also pushed to the advanced formatter.
- **Comment reformatting.** Comments are preserved verbatim and re-attached at the closest natural position. Their internal text is never rewritten.
- **Statement reordering.** Never reorder anything; whitespace and breaks only.

## 3. Architecture

A standard Wadler-style pretty-printer. Two phases:

```
parse tree              Doc IR              text
    │                     │                  │
    ▼                     ▼                  ▼
[NodePrinter] ──────► [Doc] ──────► [Layouter] ──► String
```

### 3.1 Doc IR (~100 lines of Swift)

```swift
indirect enum Doc {
    case text(String)
    case line                         // soft break: space if fits, newline if not
    case hardline                     // always newline
    case softline                     // empty if fits, newline if not
    case indent(Int, Doc)             // indent the contained doc by N
    case group(Doc)                   // try as a single line; fall back to multi-line
    case concat([Doc])
    case nest(Int, Doc)               // relative indent
}

extension Doc {
    static func + (lhs: Doc, rhs: Doc) -> Doc { .concat([lhs, rhs]) }
    static func join(_ docs: [Doc], with sep: Doc) -> Doc { … }
}
```

### 3.2 Node printers (the bulk of the work)

One function per major node type:

```swift
struct Printer {
    let config: FormatConfig
    let source: String                // for reading verbatim text of leaves

    func print(_ node: Node) -> Doc {
        switch node.nodeType {
        case "select":              return printSelect(node)
        case "from":                return printFrom(node)
        case "where":               return printWhere(node)
        case "column_definitions":  return printColumnDefinitions(node)
        case "create_procedure":    return printCreateProcedure(node)
        case "plsql_block":         return printPlsqlBlock(node)
        // … 60-80 more
        default:                    return printVerbatim(node)
        }
    }
}
```

`printVerbatim(node)` returns the original buffer text for that node's range — the safety net for anything we haven't taught the printer about. Means a partial implementation never mangles unknown constructs.

### 3.3 Layouter (~150 lines)

Standard "Phil Wadler / Lindig / Prettier" algorithm: greedy fitting with backtracking on `group`. Given a width budget, choose for each `group` whether to flatten (single line) or break (multi-line). Output a `String`.

### 3.4 Comment & hint stitching

Comments and hints live in `extras` — they're siblings of structural nodes, not children. The printer needs to:

1. Index every `comment`/`marginalia`/`hint`/`hint_line` by byte position before walking.
2. While walking, before emitting a node's tokens, look for any extras that fall in the range `(prevEmittedEnd, node.startByte)` and emit them.
3. After the last node, flush any remaining extras.
4. For trailing comments (`SELECT 1 -- inline`), emit them after the last token of the line they were on, not on a new line.

This is the fiddliest part. Get it right or the formatter loses user trust on day one.

## 4. Configuration

```swift
struct FormatConfig {
    var indentWidth: Int = 2
    var maxLineWidth: Int = 100

    enum CommaStyle { case leading, trailing }
    var commaStyle: CommaStyle = .leading

    enum KeywordCase { case upper, lower, asWritten }
    var keywordCase: KeywordCase = .upper
    var dataTypeCase: KeywordCase = .upper

    var blankLinesBetweenStatements: Int = 1
    var alignFromInSelect: Bool = true        // "  FROM" vs "FROM"

    /// Statements whose body is too short to be worth splitting.
    /// e.g. SELECT 1 FROM dual stays on one line.
    var inlineThresholdChars: Int = 60

    enum CommentPosition { case preserveColumn, normalize }
    var commentPosition: CommentPosition = .preserveColumn
}
```

Loaded from `Settings → Formatter`. Persisted in `UserDefaults`. Per-project override via `.macintora-format` JSON in the workspace root (stage 4).

## 5. Tree-sitter pieces we'll use

Every named node type listed in `parsing-architecture.md` §5 needs an opinion. The minimum set for v1:

- **DML:** `select`, `from`, `relation`, `join`, `lateral_join`, `where`, `group_by`, `having`, `order_by`, `limit`, `select_expression`, `term`, `field`, `binary_expression`, `unary_expression`, `case`, `invocation`, `subquery`, `parenthesized_expression`, `literal`.
- **DML write:** `insert`, `update`, `delete`, `merge`, `assignment`, `values`, `list`.
- **DDL:** `create_table`, `column_definitions`, `column_definition`, `_column_constraint`, `create_view`, `create_index`, `create_sequence`, `create_synonym`, `drop_*`, `alter_table`.
- **PL/SQL:** `plsql_block`, `plsql_declare_section`, `plsql_declaration`, `plsql_assignment`, `plsql_if`, `plsql_elsif`, `plsql_else`, `plsql_basic_loop`, `plsql_for_loop`, `plsql_while_loop`, `plsql_return`, `plsql_raise`, `plsql_null`, `plsql_exit`, `plsql_continue`, `plsql_procedure_call`, `plsql_exception_section`, `plsql_exception_handler`.
- **PL/SQL CREATE:** `create_procedure`, `create_function`, `create_package`, `create_package_body`, `create_trigger`, `package_procedure`, `package_function`, `plsql_subprogram_declaration`, `plsql_parameter_list`, `plsql_parameter`, `plsql_authid_clause`.

That's ~70 node types. Each printer is 5-30 lines. Estimated ~2,000 lines of printer code.

Each printer follows the same shape — visit children, intersperse `Doc.line` / `Doc.hardline`, wrap in `Doc.group` for "fit on one line if possible." Example:

```swift
func printFrom(_ node: Node) -> Doc {
    let kw = keyword("FROM")
    let relations = node.children(named: "relation").map(print)
    let joins = node.children(named: "join").map(print)

    let body = Doc.join(relations, with: .text(",") + .line)
              + (joins.isEmpty ? .text("") : .hardline + Doc.join(joins, with: .hardline))

    return .group(kw + .indent(2, .line + body))
}
```

## 6. Stages

### Stage 1: Selection-only smart indent (1 week)

The minimum useful thing: take a selected range, walk the tree to find the smallest enclosing structural node, re-indent its content based on AST depth. No reformatting of any other dimension. Solves "ugh, paste from email made this misaligned." Fast to ship; lets us validate Doc IR + comment stitching on a small surface.

### Stage 2: DML pretty-printer (2 weeks)

Full Wadler treatment for `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `MERGE`. ~30 node types. Stops at "PL/SQL is unchanged" — anything inside a `plsql_block` falls through to verbatim. Already covers most worksheet content.

### Stage 3: DDL pretty-printer (1 week)

`CREATE TABLE`, `CREATE VIEW`, `CREATE INDEX`, `CREATE SEQUENCE`, `CREATE SYNONYM`, `DROP *`, `ALTER TABLE`. Adds ~20 node types.

### Stage 4: PL/SQL block printer (2 weeks)

`plsql_block` and all its statement children. Adds ~15 node types. After this stage we cover anonymous blocks and worksheet-style PL/SQL.

### Stage 5: PL/SQL CREATE printer (1 week)

`CREATE PROCEDURE`, `CREATE FUNCTION`, `CREATE PACKAGE`, `CREATE PACKAGE BODY`, `CREATE TRIGGER`. Adds ~10 node types. After this stage we're competitive with Trivadis output for >90% of code.

### Stage 6: Format on save + project config (3 days)

`.macintora-format` JSON loading, "format on save" toggle, golden-output corpus tests in `MacintoraTests`.

### Total

~7-8 weeks of focused work, broken into shippable units. Each stage moves the needle independently.

## 7. Testing strategy

**Golden corpus.** A directory of `.before.sql` / `.after.sql` pairs covering every node type. CI runs the formatter on each `.before` and `git diff`s against `.after`. New constructs land their own pair.

**Idempotence.** `format(format(text)) == format(text)`. Required, asserted in CI.

**Round-trip parse.** Every formatter output must reparse to a tree with the same node sequence as the input. Means we never lose or alter semantics — only whitespace and casing change.

**Verbatim fallback.** Any node the formatter doesn't know about emits its source range unchanged. Tested by deliberately removing a printer and checking nothing else regresses.

## 8. Open questions

- **Which keyword-case default?** Oracle community is split: PL/SQL Developer defaults to upper; SQL Developer to mixed; Trivadis to upper. Probably upper for keywords + types, lower for built-in functions, identifiers preserved. Survey users.
- **Where does `WITH cte AS (…)` go?** Some style guides put `WITH` at column 0, some indent it to align with `SELECT`. v1 picks one; expose as config later.
- **Joins.** `JOIN` on its own line or trailing the previous line? Default to its own line, indented to `FROM`.
- **Subqueries.** Parenthesized subqueries: opening `(` at the end of the previous line, body indented, closing `)` at column of the parent? That's the SQL Developer style. Opinion welcomed.
- **Inline-or-break threshold.** Configured as `inlineThresholdChars`; default 60. May need per-construct tuning (a SELECT list of 3 short columns can stay inline; one with subqueries can't).

## 9. Risks

- **Comment loss.** The single most damaging bug. Addressed by the comment-stitching subsystem (§3.4) and a CI guard: every formatter test compares the *set* of comment node texts pre- and post-format and fails if any go missing.
- **Hint loss.** Same risk for `/*+ … */`. Same guard.
- **Reformat changes meaning.** Theoretically impossible if the round-trip parse check passes; in practice, hint placement matters semantically (`SELECT /*+ FULL(e) */ * FROM emp e` vs `SELECT * FROM emp /*+ FULL(e) */ e`). Hints stay anchored to the syntactic position they had in the input.
- **Tree-sitter ERROR nodes mid-buffer.** Don't reformat through them — emit the original text for the broken range, format the well-formed surrounding regions. Users get partial relief instead of a broken file.
- **Multibyte characters in identifiers / strings.** The Doc IR's "fit width" check must use display-width, not byte count. Practically: use `String.unicodeScalars.count` or `String.count` for the fit check; CJK width is wrong but acceptable for v1.
- **Performance on large files.** A 100K-line PL/SQL package body takes <100 ms to parse; formatting should be <500 ms. If profiling says otherwise, parallelize at the statement level — each top-level statement is independent.
