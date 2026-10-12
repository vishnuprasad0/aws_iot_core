import 'dart:async';

import '../domain/clock.dart';

/// [Clock] backed by the system time and [Timer].
class SystemClock implements Clock {
  /// Creates the clock.
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();

  @override
  Delay delay(Duration duration) => _TimerDelay(duration);
}

class _TimerDelay implements Delay {
  _TimerDelay(Duration duration) {
    _timer = Timer(duration, _finish);
  }

  final _completer = Completer<void>();
  late final Timer _timer;

  @override
  Future<void> get done => _completer.future;

  @override
  void cancel() {
    _timer.cancel();
    _finish();
  }

  void _finish() {
    if (!_completer.isCompleted) _completer.complete();
  }
}
