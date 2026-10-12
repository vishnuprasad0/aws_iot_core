/// Base class for every error thrown by this package.
///
/// The hierarchy is sealed, so a `switch` over an [AwsIotException] can be
/// exhaustive.
sealed class AwsIotException implements Exception {
  /// Creates an exception with a human-readable [message].
  const AwsIotException(this.message);

  /// Human-readable description of what went wrong.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when an operation needs a live connection and there is none.
final class AwsIotNotConnectedException extends AwsIotException {
  /// Creates the exception, optionally with a more specific [message].
  const AwsIotNotConnectedException([super.message = 'Not connected']);
}

/// Thrown when a connection attempt fails or is cancelled.
final class AwsIotConnectException extends AwsIotException {
  /// Creates the exception with the underlying [cause], if any.
  const AwsIotConnectException(super.message, {this.cause});

  /// The underlying error, for example a socket or credentials error.
  final Object? cause;

  @override
  String toString() => cause == null
      ? super.toString()
      : 'AwsIotConnectException: $message (cause: $cause)';
}

/// Thrown when the broker refuses a subscription, usually because the IoT
/// policy does not allow `iot:Subscribe` on the topic filter.
final class AwsIotSubscribeException extends AwsIotException {
  /// Creates the exception for [topicFilter].
  const AwsIotSubscribeException(this.topicFilter)
    : super(
        'Subscription refused for "$topicFilter". '
        'Check the IoT policy allows iot:Subscribe on this topic filter.',
      );

  /// The topic filter that was refused.
  final String topicFilter;
}

/// Thrown when a request or acknowledgement does not arrive in time.
final class AwsIotTimeoutException extends AwsIotException {
  /// Creates the exception with a [message] describing what timed out.
  const AwsIotTimeoutException(super.message);
}

/// Thrown when AWS IoT rejects a Device Shadow request.
final class AwsIotShadowRejectedException extends AwsIotException {
  /// Creates the exception with the AWS error [code] and [message].
  const AwsIotShadowRejectedException({
    required this.code,
    required String message,
  }) : super(message);

  /// The error code AWS returned, for example 404 (no such shadow) or 409
  /// (version conflict).
  final int code;

  @override
  String toString() => 'AwsIotShadowRejectedException($code): $message';
}
