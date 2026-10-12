import 'dart:async';

import '../domain/errors.dart';
import '../domain/message.dart';
import '../domain/transport.dart';
import 'topic_matcher.dart';

/// Reference-counted topic subscriptions and message routing.
///
/// A broker subscription is made when the first listener of a filter
/// attaches, removed when the last one cancels, and re-made on every new
/// transport (after a reconnect).
class SubscriptionManager {
  /// Creates a manager that waits [subscribeTimeout] for acknowledgements.
  SubscriptionManager({required this.subscribeTimeout});

  /// How long to wait for the broker to acknowledge a subscription.
  final Duration subscribeTimeout;

  final _entries = <String, _FilterSubscription>{};
  MqttTransport? _transport;

  /// Topic filters that currently have listeners.
  Iterable<String> get activeFilters => _entries.keys;

  /// Messages on topics matching [topicFilter].
  Stream<AwsIotMessage> subscribe(String topicFilter, AwsIotQos qos) {
    validateTopicFilter(topicFilter);
    late final StreamController<AwsIotMessage> controller;
    controller = StreamController<AwsIotMessage>(
      onListen: () => _attach(topicFilter, qos, controller),
      onCancel: () => _detach(topicFilter, controller),
    );
    return controller.stream;
  }

  /// Completes when the broker has acknowledged [topicFilter] on the current
  /// connection. The filter must have at least one listener.
  Future<void> ready(String topicFilter) {
    final entry = _entries[topicFilter];
    if (entry == null) {
      return Future.error(StateError('No listener for "$topicFilter"'));
    }
    return entry.ready ?? Future.error(const AwsIotNotConnectedException());
  }

  /// Uses [transport] from now on and re-applies every active filter.
  void attachTransport(MqttTransport transport) {
    _transport = transport;
    for (final entry in _entries.values) {
      _brokerSubscribe(transport, entry);
    }
  }

  /// Forgets the current transport; broker subscriptions are gone with it.
  void detachTransport() {
    _transport = null;
    for (final entry in _entries.values) {
      entry.ready = null;
    }
  }

  /// Delivers [message] to every listener whose filter matches.
  void dispatch(AwsIotMessage message) {
    for (final entry in _entries.values.toList()) {
      if (!topicMatches(entry.filter, message.topic)) continue;
      for (final controller in entry.controllers.toList()) {
        controller.add(message);
      }
    }
  }

  /// Closes every listener's stream.
  Future<void> close() async {
    final controllers = [
      for (final entry in _entries.values) ...entry.controllers,
    ];
    _entries.clear();
    for (final controller in controllers) {
      await controller.close();
    }
  }

  void _attach(
    String filter,
    AwsIotQos qos,
    StreamController<AwsIotMessage> controller,
  ) {
    final entry = _entries.putIfAbsent(
      filter,
      () => _FilterSubscription(filter, qos),
    );
    if (qos.index > entry.qos.index) entry.qos = qos;
    entry.controllers.add(controller);
    final transport = _transport;
    if (transport != null && entry.ready == null) {
      _brokerSubscribe(transport, entry);
    }
  }

  void _detach(String filter, StreamController<AwsIotMessage> controller) {
    final entry = _entries[filter];
    if (entry == null) return;
    entry.controllers.remove(controller);
    if (entry.controllers.isNotEmpty) return;
    _entries.remove(filter);
    final transport = _transport;
    if (transport != null && entry.ready != null) {
      transport.unsubscribe(filter);
    }
  }

  void _brokerSubscribe(MqttTransport transport, _FilterSubscription entry) {
    final ready = transport
        .subscribe(entry.filter, entry.qos)
        .timeout(
          subscribeTimeout,
          onTimeout: () => throw AwsIotTimeoutException(
            'No acknowledgement for subscription "${entry.filter}"',
          ),
        );
    entry.ready = ready;
    unawaited(
      ready.then<void>(
        (_) {},
        onError: (Object error) {
          if (!identical(entry.ready, ready)) return;
          for (final controller in entry.controllers.toList()) {
            controller.addError(error);
          }
        },
      ),
    );
  }
}

class _FilterSubscription {
  _FilterSubscription(this.filter, this.qos);

  final String filter;
  final Set<StreamController<AwsIotMessage>> controllers = {};

  /// Highest QoS requested when the broker subscription was made. Raising
  /// it later takes effect on the next reconnect.
  AwsIotQos qos;

  /// Broker acknowledgement on the current connection, or null when there is
  /// no broker subscription.
  Future<void>? ready;
}
