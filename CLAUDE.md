# Macintora — Agent Guide

Macintora is a macOS SQL IDE for Oracle databases. Main areas:
- **SQL Editor** — write/execute SQL, data grid, DBMS_OUTPUT.
- **Database Browser** — browse and cache DB objects (tables, packages, …).
- **Connections Manager** — choose, connect, disconnect.

## Targets

- macOS 26.0+, Swift 6.2+, modern Swift concurrency.
- SwiftUI + AppKit + TextKit 2; `@Observable` classes for shared state.
- Do not add third-party frameworks without asking.

## Dependencies (iliasaz forks)

All consumed as remote SPM packages on branch `macintora`. Macintora pins each via `Package.resolved`, so after pushing upstream you must bump the pinned SHA.

- **oracle-nio** — fork of `lovetodream/oracle-nio`. Local: `/Users/ilia/Developer/oracle-nio`. Pure-Swift Oracle TTC/TNS driver.
- **STTextView** — fork of `krzyzanowskim/STTextView`. Local: `/Users/ilia/Developer/STTextView`. TextKit 2 source editor.
- **STTextView-Plugin-Neon** — fork of `krzyzanowskim/STTextView-Plugin-Neon`. Local: `/Users/ilia/Developer/STTextView-Plugin-Neon`. Tree-sitter highlighting; vendors `tree-sitter-sql-orcl` as `TreeSitterSQLOrcl`.
- **STTextKitPlus** — fork of `krzyzanowskim/STTextKitPlus`. Local: `/Users/ilia/Developer/STTextKitPlus`. TextKit 2 range/location helpers.
- **tree-sitter-sql-orcl** — owned, no upstream, branch `main`. Local: `/Users/ilia/Developer/tree-sitter-sql-orcl`. Oracle SQL & PL/SQL grammar; powers highlighting, completion, and Quick View resolver.

### Editing a fork
1. Edit in `/Users/ilia/Developer/<repo>` on branch `macintora`.
2. Commit and `git push origin macintora`.
3. Bump the pin in `Macintora.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

## Skills & MCP

Use these skills when relevant: `swiftui-expert-skill`, `swift-concurrency`, `swift-testing-pro`. Use `sosumi` MCP for Apple docs; use Xcode MCP when available.

## Swift 6.2 approachable concurrency

- Code is main-actor by default. Don't add `@MainActor` unless isolating *away* from default.
- Nonisolated async runs on caller's actor; use `@concurrent` for true parallelism.
- Trust automatic `@Sendable` inference.
- Resolve compiler concurrency/memory-safety warnings; consult `swift-concurrency` skill.

## Swift idioms

- Prefer Swift-native string APIs (`replacing(_:with:)`, not `replacingOccurrences`).
- Modern Foundation: `URL.documentsDirectory`, `appending(path:)`.
- Format numbers with `.formatted(...)`, never `String(format:)`.
- Static member lookup (`.circle`, `.borderedProminent`) over initializers.
- Never use GCD (`DispatchQueue.main.async`) — use Swift concurrency.
- `Task.sleep(for:)`, never `Task.sleep(nanoseconds:)`.
- User-input filtering: `localizedStandardContains`, not `contains`.
- Avoid force-unwrap / force-`try` unless truly unrecoverable.

## SwiftUI

- `foregroundStyle`, not `foregroundColor`.
- `clipShape(.rect(cornerRadius:))`, not `cornerRadius()`.
- `Tab` API, not `tabItem()`.
- `@Observable`, never `ObservableObject`.
- `onChange` — only the 0- or 2-parameter variants.
- `Button` for taps; `onTapGesture` only for location/count.
- `NavigationStack` + `navigationDestination(for:)`, never `NavigationView`.
- `Button("Label", systemImage: "plus", action:)` — always pair text with image.
- `bold()`, not `fontWeight(.bold)`; avoid `fontWeight` without reason.
- Skip `GeometryReader` if `containerRelativeFrame`/`visualEffect` works.
- `ForEach(x.enumerated(), id: \.element.id)` — don't wrap in `Array(...)`.
- `.scrollIndicators(.hidden)`, not `showsIndicators: false`.
- New `View` structs for subviews, not computed properties.
- Avoid `AnyView`, hard-coded padding/spacing, UIKit colors, fixed font sizes (use Dynamic Type).
- Put view logic in a model/observable for testability.

## Logging

- `OSLog` + `Logger(subsystem:category:)` with appropriate levels (`.debug`/`.info`/`.notice`/`.error`/`.fault`).
- Never `print()` in production. Don't log secrets.

## Testing

- Logic changes (services, view models, algorithms, models) require unit tests; UI-only behavior gets UI tests. Run them and confirm green before declaring done.
- `XCTest` only (no third-party test frameworks without asking).
- Test pure logic in isolation — no live Oracle connection or network.
- Local persistence uses **Core Data** (backed by SQLite, but treat the store as Core Data — don't reach for raw SQL). For tests, spin up an in-memory `NSPersistentContainer` rather than touching the on-disk store.

## Git / PRs

- Use `gh release list` for the latest version (not `git tag` — dep tags pollute results).
- SwiftLint must be clean before committing (if installed).
