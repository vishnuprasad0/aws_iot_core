/// Decides when to retry after the connection drops unexpectedly.
abstract interface class BackoffPolicy {
  /// The delay before reconnect attempt [attempt] (0-based), or null to stop
  /// retrying.
  Duration? delayFor(int attempt);
}
