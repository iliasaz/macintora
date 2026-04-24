import Foundation
import NIOCore
import NIOPosix

/// Process-wide EventLoopGroup used for all oracle-nio connections and clients.
///
/// We use one `MultiThreadedEventLoopGroup` for the app's lifetime rather than a
/// transient one per connection, which avoids spinning up/tearing down threads for
/// each user action. The group is graceful-shutdown on ``shutdown()``.
nonisolated enum OracleEventLoopGroup {
    /// Shared singleton loop group (lazy).
    static let shared: MultiThreadedEventLoopGroup = {
        MultiThreadedEventLoopGroup(numberOfThreads: 2)
    }()

    /// Request a clean shutdown. Safe to call multiple times; subsequent calls are no-ops.
    static func shutdown() async {
        try? await shared.shutdownGracefully()
    }
}
