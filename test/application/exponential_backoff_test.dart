import 'dart:math';

import 'package:aws_iot_core/aws_iot_core.dart';
import 'package:test/test.dart';

void main() {
  test('without jitter, delays double and are capped', () {
    const policy = ExponentialBackoff(
      initialDelay: Duration(seconds: 1),
      maxDelay: Duration(seconds: 10),
      jitter: 0,
    );
    expect(
      [for (var i = 0; i < 6; i++) policy.delayFor(i)!.inSeconds],
      [1, 2, 4, 8, 10, 10],
    );
  });

  test('jitter stays within the configured fraction', () {
    final policy = ExponentialBackoff(
      initialDelay: const Duration(seconds: 1),
      maxDelay: const Duration(seconds: 10),
      random: Random(1),
    );
    for (var attempt = 0; attempt < 10; attempt++) {
      final base = min(1000 * pow(2, attempt), 10000);
      expect(
        policy.delayFor(attempt)!.inMilliseconds,
        inInclusiveRange(base * 0.8 - 1, base * 1.2 + 1),
        reason: 'attempt $attempt',
      );
    }
  });

  test('the default random source is used when none is given', () {
    const policy = ExponentialBackoff();
    expect(policy.delayFor(0)!.inMilliseconds, inInclusiveRange(799, 1201));
  });

  test('stops after maxAttempts', () {
    const policy = ExponentialBackoff(maxAttempts: 2, jitter: 0);
    expect(policy.delayFor(0), isNotNull);
    expect(policy.delayFor(1), isNotNull);
    expect(policy.delayFor(2), isNull);
  });

  test('very high attempt counts stay finite', () {
    const capped = ExponentialBackoff(jitter: 0);
    expect(capped.delayFor(5000), const Duration(seconds: 60));
    const zero = ExponentialBackoff(initialDelay: Duration.zero, jitter: 0);
    expect(zero.delayFor(5000), Duration.zero);
  });
  test('NoReconnect never retries', () {
    expect(const NoReconnect().delayFor(0), isNull);
  });
}
