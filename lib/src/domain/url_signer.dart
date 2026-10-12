import 'credentials.dart';

/// Produces the signed WebSocket URL for a connection attempt.
abstract interface class UrlSigner {
  /// Signs a connection URL with [credentials] at [time].
  Uri sign(AwsIotCredentials credentials, DateTime time);
}
