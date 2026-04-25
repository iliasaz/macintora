import SwiftUI

/// Environment plumbing for the app-wide ``ConnectionStore``.
///
/// The store is created once at app launch (`MacOraApp`) and threaded into
/// every Scene via `.environment(\.connectionStore, store)` so any view —
/// document picker, settings, command palette — can read or mutate the
/// shared list with no extra wiring.
///
/// `EnvironmentKey.defaultValue` is required to be safe to read from any
/// isolation; `ConnectionStore` is `@MainActor`-isolated, so we publish an
/// optional default and let consumers force-unwrap or guard. The real store
/// is always installed at App start, so the default is never read in a
/// shipping build — it's the contract a missing `.environment(...)` would
/// produce.
extension EnvironmentValues {
    @Entry var connectionStore: ConnectionStore? = nil
    @Entry var keychainService: KeychainService = KeychainService()
}
