# Macintora
A macOS native IDE tool for Oracle Database developers.

## What's new

Macintora now uses a **pure-Swift** Oracle driver, [oracle-nio](https://github.com/lovetodream/oracle-nio). This means:

- No Oracle Instant Client download or install — Macintora speaks Oracle's native TTC/TNS wire protocol directly.
- Native Apple Silicon builds (no Rosetta).
- Full Swift 6 strict concurrency across the app.
- TLS, SYSDBA, and Cloud-IAM authentication supported via oracle-nio's configuration.

Oracle Database 12.1 or later is supported.

## Building from source

### Requirements
- macOS 14+ (Sonoma)
- Xcode 26 with Swift 6.x toolchain
- Oracle Database reachable at host/port with a valid service name (or SID)

### Dependencies (all pulled automatically via SwiftPM)
- [oracle-nio](https://github.com/lovetodream/oracle-nio) — pure-Swift Oracle driver (pinned to `v1.0.0-rc.4`)
- [CodeEditor](https://github.com/iliasaz/CodeEditor)
- [Highlightr](https://github.com/iliasaz/Highlightr)
- [SF Mono Font](https://devimages-cdn.apple.com/design/resources/download/SF-Mono.dmg) (recommended for the result grid)

Clone the repo and open `Macintora.xcodeproj` in Xcode. Build and run the `MacOra` scheme.

### Optional: SQL formatter
For the built-in *Format&View* action, install the [Trivadis PL/SQL & SQL Formatter](https://github.com/Trivadis/plsql-formatter-settings#plsql--sql-formatter-settings) and point Macintora to it via *Settings → Formatter Path*.

## Connection setup

Macintora reads **tnsnames.ora** for connection aliases. By default it looks at `~/.oracle/tnsnames.ora`; you can change the path in *Settings → TNS Names Path*.

Sample `tnsnames.ora`:

```
ORCL =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = db.example.com)(PORT = 1521))
    (CONNECT_DATA = (SERVICE_NAME = orcl))
  )
```

As an alternative, you can type a manual endpoint in the TNS field in the format `host:port/service` (port defaults to 1521 if omitted). `host/service` and `host:port/service` are both accepted.

## Other projects used
- [oracle-nio](https://github.com/lovetodream/oracle-nio) — pure-Swift Oracle driver (replaces SwiftOracle/OCILIB).
- [CodeEditor](https://github.com/iliasaz/CodeEditor)
- [SwiftUIWindow](https://github.com/mortenjust/SwiftUIWindow) (inspiration)
- [Trivadis PL/SQL & SQL Formatter Settings](https://github.com/Trivadis/plsql-formatter-settings#plsql--sql-formatter-settings)
