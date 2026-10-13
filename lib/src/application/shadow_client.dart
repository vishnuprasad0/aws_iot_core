import 'dart:async';
import 'dart:math';

import '../domain/errors.dart';
import '../domain/message.dart';
import '../domain/shadow_document.dart';
import 'subscription_manager.dart';

/// Publishes [value] as JSON to [topic].
typedef JsonPublisher = void Function(String topic, Object? value);

/// An AWS IoT Device Shadow, classic or named.
///
/// Requests are correlated with their responses by `clientToken`. The
/// `/accepted` and `/rejected` topics of an operation are subscribed before
/// its first request and kept until [dispose].
class AwsIotShadow {
  /// Creates a shadow handle. Use `AwsIotClient.shadow` instead.
  AwsIotShadow(
    this._subscriptions,
    this._publishJson,
    this.thingName, {
    this.shadowName,
    this.requestTimeout = const Duration(seconds: 10),
    Random? random,
  }) : _random = random ?? Random.secure();

  final SubscriptionManager _subscriptions;
  final JsonPublisher _publishJson;
  final Random _random;

  /// The thing this shadow belongs to.
  final String thingName;

  /// Name of the shadow, or null for the classic (unnamed) shadow.
  final String? shadowName;

  /// How long to wait for `/accepted` or `/rejected`.
  final Duration requestTimeout;

  final _pending = <String, Completer<Map<String, dynamic>>>{};
  final _responseSubs = <String, StreamSubscription<AwsIotMessage>>{};
  int _counter = 0;

  /// Topic prefix, for example `$aws/things/my-thing/shadow` or
  /// `$aws/things/my-thing/shadow/name/config`.
  String get topicPrefix => shadowName == null
      ? '\$aws/things/$thingName/shadow'
      : '\$aws/things/$thingName/shadow/name/$shadowName';

  /// Reads the shadow document. Throws [AwsIotShadowRejectedException] with
  /// code 404 when the shadow does not exist.
  Future<ShadowDocument> get() async =>
      ShadowDocument(await _request('get', const {}));

  /// Updates the desired and/or reported state.
  ///
  /// Pass [version] for optimistic locking; AWS rejects the update with code
  /// 409 when the shadow has changed since.
  Future<ShadowDocument> update({
    Map<String, Object?>? desired,
    Map<String, Object?>? reported,
    int? version,
  }) async {
    if (desired == null && reported == null) {
      throw ArgumentError('Provide desired and/or reported state');
    }
    return ShadowDocument(
      await _request('update', {
        'state': {'desired': ?desired, 'reported': ?reported},
        'version': ?version,
      }),
    );
  }

  /// Deletes the shadow.
  Future<void> delete() async {
    await _request('delete', const {});
  }

  /// Differences between desired and reported state, published by AWS on
  /// `update/delta`.
  Stream<ShadowDelta> get delta => _subscriptions
      .subscribe('$topicPrefix/update/delta', AwsIotQos.atLeastOnce)
      .map((m) => ShadowDelta(asJsonObject(m.json)));

  /// Full before and after documents for every accepted update, from
  /// `update/documents`.
  Stream<ShadowDocumentsEvent> get documents => _subscriptions
      .subscribe('$topicPrefix/update/documents', AwsIotQos.atLeastOnce)
      .map((m) => ShadowDocumentsEvent(asJsonObject(m.json)));

  /// Cancels the response subscriptions and fails pending requests.
  Future<void> dispose() async {
    final subs = _responseSubs.values.toList();
    _responseSubs.clear();
    for (final sub in subs) {
      await sub.cancel();
    }
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const AwsIotNotConnectedException(
            'Shadow disposed before a response arrived',
          ),
        );
      }
    }
    _pending.clear();
  }

  Future<Map<String, dynamic>> _request(
    String operation,
    Map<String, Object?> body,
  ) async {
    await _ensureResponseSubscription(operation);
    final token = _nextToken();
    final completer = Completer<Map<String, dynamic>>();
    _pending[token] = completer;
    try {
      _publishJson('$topicPrefix/$operation', {...body, 'clientToken': token});
      return await completer.future.timeout(
        requestTimeout,
        onTimeout: () => throw AwsIotTimeoutException(
          'No response to shadow $operation for "$thingName" '
          'within ${requestTimeout.inMilliseconds} ms',
        ),
      );
    } finally {
      _pending.remove(token);
    }
  }

  // Exact topics rather than `$operation/+`: that filter would also match
  // `update/delta` and `update/documents`, and AWS IoT sends one copy of a
  // message per matching subscription, so `delta` listeners would get
  // duplicates.
  Future<void> _ensureResponseSubscription(String operation) async {
    final filters = [
      for (final outcome in const ['accepted', 'rejected'])
        '$topicPrefix/$operation/$outcome',
    ];
    for (final filter in filters) {
      _responseSubs[filter] ??= _subscriptions
          .subscribe(filter, AwsIotQos.atLeastOnce)
          .listen(_onResponse, onError: (Object _) {});
    }
    try {
      await Future.wait(filters.map(_subscriptions.ready));
    } catch (_) {
      // Drop them so the next request subscribes again.
      for (final filter in filters) {
        await _responseSubs.remove(filter)?.cancel();
      }
      rethrow;
    }
  }

  void _onResponse(AwsIotMessage message) {
    final topic = message.topic;
    final outcome = topic.substring(topic.lastIndexOf('/') + 1);
    if (outcome != 'accepted' && outcome != 'rejected') return;
    final Map<String, dynamic> json;
    try {
      json = asJsonObject(message.json);
    } on FormatException {
      return;
    }
    final completer = _pending[json['clientToken']];
    if (completer == null || completer.isCompleted) return;
    if (outcome == 'accepted') {
      completer.complete(json);
    } else {
      completer.completeError(
        AwsIotShadowRejectedException(
          code: intOrNull(json['code']) ?? 0,
          message: json['message'] as String? ?? 'Shadow request rejected',
        ),
      );
    }
  }

  // A literal, not `1 << 32`: on the web shifts are 32-bit, so that is 0.
  String _nextToken() =>
      '${++_counter}-${_random.nextInt(0xFFFFFFFF).toRadixString(16)}';
}
