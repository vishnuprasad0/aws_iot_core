/// Source of time and delays, injectable so reconnect timing can be tested.
abstract interface class Clock {
  /// The current time.
  DateTime now();

  /// Starts a delay of [duration].
  Delay delay(Duration duration);
}

/// A running delay that can be cut short.
abstract interface class Delay {
  /// Completes when the delay elapses or is cancelled.
  Future<void> get done;

  /// Ends the delay early; [done] completes.
  void cancel();
}
