import 'dart:math';

import '../domain/backoff_policy.dart';

/// Exponential backoff with jitter: the default reconnect policy.
///
/// The delay before attempt `n` (0-based) is
/// `min(maxDelay, initialDelay * multiplier^n)`, moved up or down by up to
/// [jitter] of itself at random.
class ExponentialBackoff implements BackoffPolicy {
  /// Creates the policy. [jitter] is a fraction between 0 and 1.
  const ExponentialBackoff({
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 60),
    this.multiplier = 2.0,
    this.jitter = 0.2,
    this.maxAttempts,
    this.random,
  }) : assert(multiplier >= 1),
       assert(jitter >= 0 && jitter <= 1);

  /// Delay before the first attempt.
  final Duration initialDelay;

  /// Upper bound for any delay, before jitter.
  final Duration maxDelay;

  /// Growth factor between attempts.
  final double multiplier;

  /// Fraction of the delay to randomise, in either direction.
  final double jitter;

  /// Give up after this many failed attempts. Null retries forever.
  final int? maxAttempts;

  /// Source of randomness for jitter; a shared default is used when null.
  final Random? random;

  static final Random _defaultRandom = Random();

  @override
  Duration? delayFor(int attempt) {
    final limit = maxAttempts;
    if (limit != null && attempt >= limit) return null;
    final initial = initialDelay.inMicroseconds;
    // Skipped for a zero delay: after enough attempts the growth factor is
    // infinite, and 0 * infinity is NaN.
    final base = initial == 0 ? 0.0 : initial * pow(multiplier, attempt);
    final capped = min(base.toDouble(), maxDelay.inMicroseconds.toDouble());
    final rng = random ?? _defaultRandom;
    final factor = 1 + jitter * (2 * rng.nextDouble() - 1);
    return Duration(microseconds: max(0, (capped * factor).round()));
  }
}

/// A policy that never reconnects automatically.
class NoReconnect implements BackoffPolicy {
  /// Creates the policy.
  const NoReconnect();

  @override
  Duration? delayFor(int attempt) => null;
}
