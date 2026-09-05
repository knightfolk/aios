import Foundation

/// HybridTests runs in one process with parallel tests; worker children
/// inherit the CURRENT environment at spawn. Tests that drive workers via
/// env knobs take this lock for their duration and scrub shared keys, so
/// no worker ever inherits another test's state.
enum TestEnvGate {
    private static let semaphore = DispatchSemaphore(value: 1)

    /// Blocks only a dispatch thread, never a Swift-concurrency cooperative
    /// thread (blocking the pool deadlocks small-core CI runners).
    static func lock() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                semaphore.wait()
                continuation.resume()
            }
        }
    }

    static func unlock() { semaphore.signal() }

    static func set(_ key: String, _ value: String?) {
        if let value {
            setenv(key, value, 1)
        } else {
            unsetenv(key)
        }
    }
}
