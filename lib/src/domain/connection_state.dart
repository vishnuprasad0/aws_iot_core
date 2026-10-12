/// Connection state of an `AwsIotClient`.
enum AwsIotConnectionState {
  /// Not connected and not trying to connect.
  disconnected,

  /// First connection attempt in progress.
  connecting,

  /// Connected to AWS IoT Core.
  connected,

  /// The connection dropped; waiting to retry, or retrying with fresh
  /// credentials.
  reconnecting,
}
