import 'package:aws_iot_core/aws_iot_core.dart';
import 'package:test/test.dart';

void main() {
  const clock = SystemClock();

  test('now() is the current UTC time', () {
    final before = DateTime.now().toUtc();
    final now = clock.now();
    expect(now.isUtc, isTrue);
    expect(now.isBefore(before.subtract(const Duration(seconds: 1))), isFalse);
  });

  test('delay completes after the duration', () async {
    final watch = Stopwatch()..start();
    await clock.delay(const Duration(milliseconds: 20)).done;
    expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(15));
  });

  test('cancel() completes the delay early', () async {
    final delay = clock.delay(const Duration(hours: 1));
    delay.cancel();
    await delay.done.timeout(const Duration(seconds: 1));
    delay.cancel();
  });
}
