# Macintora
A macOS native IDE tool for Oracle Database developers.

## What's new

- **DB Object Quick View in the editor.** ⌘-click or press ⌘I on any
  table, view, package, procedure, function, type, or column reference
  to pop up a compact details popover — columns with types and flags,
  indexes, triggers, package members with argument signatures, view
  SQL. Configurable hotkey in *Settings → Editor*; works against the
  per-connection cache, no live DB round-trip.
- **Code completion** for tables, views, and columns (alias-resolved),
  driven by the tree-sitter parse tree and the cached DB objects.
- **Oracle SQL and PL/SQL syntax highlighting** via my tree-sitter
  grammar [tree-sitter-sql-orcl](https://github.com/iliasaz/tree-sitter-sql-orcl).
  Incremental highlighting via STTextView's Neon plugin.
- **Connection Manager** in *Settings → Connections* — import
  connections from your existing `tnsnames.ora` once, then manage
  everything in-app. Macintora no longer requires a maintained
  `tnsnames.ora` on disk.
- **Trivadis SQL & PL/SQL formatter** wired into the editor. Format the
  current statement or the whole document; settings ship with sensible
  defaults and can be customised by pointing at your own Trivadis
  config (see *Settings → Formatter Path*).
- **Pure-Swift Oracle driver** ([oracle-nio](https://github.com/lovetodream/oracle-nio)):
  - No Oracle Instant Client download or install — Macintora speaks
    Oracle's native TTC/TNS wire protocol directly.
  - Native Apple Silicon builds (no Rosetta).
  - Full Swift 6 strict concurrency across the app.
  - TLS, SYSDBA, and Cloud-IAM authentication supported via
    oracle-nio's configuration.

Oracle Database 12.1 or later is supported.

## Building from source

### Requirements
- macOS 14+ (Sonoma)
- Xcode 26 with Swift 6.x toolchain
- Oracle Database reachable at host/port with a valid service name (or SID)

### Dependencies (all pulled automatically via SwiftPM)
- [oracle-nio](https://github.com/lovetodream/oracle-nio) — pure-Swift Oracle driver (pinned to `v1.0.0-rc.4`)
- [STTextView](https://github.com/krzyzanowskim/STTextView) — TextKit 2 code editor (local SPM at `../STTextView`)
- [STTextView-Plugin-Neon](https://github.com/krzyzanowskim/STTextView-Plugin-Neon) — tree-sitter syntax highlighting plugin (local SPM at `../STTextView-Plugin-Neon`)
- [STTextKitPlus](https://github.com/krzyzanowskim/STTextKitPlus) — TextKit 2 range/location helpers (local SPM at `../STTextKitPlus`)
- [SF Mono Font](https://devimages-cdn.apple.com/design/resources/download/SF-Mono.dmg) (recommended for the result grid)

Clone the repo and open `Macintora.xcodeproj` in Xcode. Build and run the `MacOra` scheme.

### SQL & PL/SQL formatter

Install the [Trivadis PL/SQL & SQL Formatter](https://github.com/Trivadis/plsql-formatter-settings#plsql--sql-formatter-settings) and point Macintora to it via *Settings → Formatter Path*. After that, the editor's Format action runs the formatter on the current statement or the entire document. Trivadis configuration files (`format.xml`, `arbori-program.txt`) are picked up from the same directory if present, so you can tune output to your team's standards.

## Connection setup

Macintora's **Connection Manager** lives in *Settings → Connections*. The first time you open it you can import your existing `tnsnames.ora` in one click; after that, all connection metadata is stored inside Macintora and you don't need to maintain the `tnsnames.ora` file anymore.

You can also add connections by hand via the form, or paste a JDBC-style URL:

```
host:port/service
host/service                 # port defaults to 1521
jdbc:oracle:thin:@host:port/service
jdbc:oracle:thin:@(DESCRIPTION = ...)
```

Passwords are stored in the macOS Keychain. Per-connection details (TLS, SYSDBA, edition, etc.) are exposed in the editor form.

## Documentation

Architecture and roadmap docs live under [`docs/`](./docs).

- [Tree-sitter SQL/PL-SQL parsing architecture](./docs/parsing-architecture.md) — how the three-repo grammar/plugin/app integration is wired, how to reach the parse tree from Swift, and a node/field reference for everything the grammar produces.

Future-feature roadmaps (designed, not yet implemented):

- [Outline view](./docs/roadmap-outline.md) — sidebar listing top-level symbols and package members; click to jump.
- [Jump-to-symbol (and back)](./docs/roadmap-jump-to-symbol.md) — Cmd-click navigation, in-buffer first, then cross-file, then DBCache; with a back/forward stack.
- [Basic formatter](./docs/roadmap-basic-formatter.md) — native Swift Wadler-style pretty-printer for SQL and PL/SQL (a lighter alternative to the Trivadis integration).
- [Advanced formatter with user-defined patterns](./docs/roadmap-advanced-formatter.md) — second-stage formatter that accepts `.scm` rule files, ships a curated default rule set, and adds column-anchored alignment.

Implemented (originally listed here):

- [Code completion](./docs/roadmap-code-completion.md) — tables, views, alias-resolved columns, and package members are live; PL/SQL in-scope variables remain on the roadmap.

## Other projects used
- [oracle-nio](https://github.com/lovetodream/oracle-nio) — pure-Swift Oracle driver (replaces SwiftOracle/OCILIB).
- [STTextView](https://github.com/krzyzanowskim/STTextView) — TextKit 2 source editor (replaces CodeEditor).
- [STTextView-Plugin-Neon](https://github.com/krzyzanowskim/STTextView-Plugin-Neon) — tree-sitter highlighting plugin.
- [tree-sitter-sql-orcl](https://github.com/iliasaz/tree-sitter-sql-orcl) — my Oracle SQL & PL/SQL grammar; powers the highlighter, completion, and Quick View.
- [SwiftUIWindow](https://github.com/mortenjust/SwiftUIWindow) (inspiration)
- [Trivadis PL/SQL & SQL Formatter Settings](https://github.com/Trivadis/plsql-formatter-settings#plsql--sql-formatter-settings)
