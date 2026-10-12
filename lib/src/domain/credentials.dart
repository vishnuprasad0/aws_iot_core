/// AWS credentials used to sign the AWS IoT WebSocket URL.
///
/// For mobile apps these are usually temporary credentials from an Amazon
/// Cognito identity pool, so [sessionToken] and [expiration] are set.
class AwsIotCredentials {
  /// Creates a set of credentials.
  const AwsIotCredentials({
    required this.accessKeyId,
    required this.secretAccessKey,
    this.sessionToken,
    this.expiration,
  });

  /// The AWS access key ID.
  final String accessKeyId;

  /// The AWS secret access key.
  final String secretAccessKey;

  /// Session token for temporary credentials. It is appended to the URL after
  /// signing, as AWS IoT requires.
  final String? sessionToken;

  /// When the credentials stop being valid, if known.
  final DateTime? expiration;

  @override
  String toString() =>
      'AwsIotCredentials(accessKeyId: $accessKeyId, expiration: $expiration)';
}

/// Supplies credentials for each connection attempt.
///
/// [getCredentials] is called before every connect and every reconnect, so an
/// implementation backed by Cognito should return fresh, refreshed
/// credentials rather than a cached copy that may have expired.
abstract interface class AwsIotCredentialsProvider {
  /// Returns credentials that are valid now.
  Future<AwsIotCredentials> getCredentials();
}

/// Runs before each connection attempt with the credentials about to be used,
/// for example to attach an AWS IoT policy to a Cognito identity.
typedef BeforeConnectHook =
    Future<void> Function(AwsIotCredentials credentials);
