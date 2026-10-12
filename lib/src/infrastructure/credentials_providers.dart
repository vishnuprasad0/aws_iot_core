import '../domain/credentials.dart';

/// A provider that always returns the same credentials.
///
/// Useful for tests and long-lived keys. Prefer temporary credentials in
/// production apps.
class StaticCredentialsProvider implements AwsIotCredentialsProvider {
  /// Creates a provider that returns [credentials].
  const StaticCredentialsProvider(this.credentials);

  /// The credentials returned on every call.
  final AwsIotCredentials credentials;

  @override
  Future<AwsIotCredentials> getCredentials() async => credentials;
}

/// A provider backed by a callback, for wrapping an existing auth library.
class CallbackCredentialsProvider implements AwsIotCredentialsProvider {
  /// Creates a provider that calls [callback] for every connection attempt.
  const CallbackCredentialsProvider(this.callback);

  /// Returns fresh credentials.
  final Future<AwsIotCredentials> Function() callback;

  @override
  Future<AwsIotCredentials> getCredentials() => callback();
}
