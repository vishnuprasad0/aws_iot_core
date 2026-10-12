import 'dart:async';
import 'dart:typed_data';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:typed_data/typed_buffers.dart';

import '../../domain/errors.dart';
import '../../domain/message.dart';
import '../../domain/transport.dart';

/// [MqttTransport] backed by a `package:mqtt_client` client.
///
/// The library's own auto-reconnect is turned off; reconnecting is handled
/// by the connection manager so that every attempt uses a newly signed URL.
class MqttClientTransport implements MqttTransport {
  /// Configures the given `mqtt_client` client for AWS IoT using [config].
  MqttClientTransport(this._client, TransportConfig config) {
    _client
      ..setProtocolV311()
      ..logging(on: false)
      ..autoReconnect = false
      ..keepAlivePeriod = config.keepAlive.inSeconds
      ..disconnectOnNoResponsePeriod = (config.keepAlive.inSeconds ~/ 2).clamp(
        10,
        1200,
      )
      ..connectTimeoutPeriod = config.connectTimeout.inMilliseconds
      ..connectionMessage = MqttConnectMessage()
          .withClientIdentifier(config.clientId)
          .startClean()
      ..onDisconnected = _handleDisconnected
      ..onSubscribed = _handleSubscribed
      ..onSubscribeFail = _handleSubscribeFail;
  }

  final MqttClient _client;
  final _messages = StreamController<AwsIotMessage>.broadcast();
  final _pendingSubscriptions = <String, Completer<void>>{};
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updates;
  void Function()? _onUnsolicitedDisconnect;
  bool _wasConnected = false;
  bool _closedLocally = false;

  @override
  set onUnsolicitedDisconnect(void Function()? callback) =>
      _onUnsolicitedDisconnect = callback;

  @override
  bool get isConnected =>
      _client.connectionStatus?.state == MqttConnectionState.connected;

  @override
  Stream<AwsIotMessage> get messages => _messages.stream;

  @override
  Future<void> connect() async {
    MqttClientConnectionStatus? status;
    try {
      status = await _client.connect();
    } catch (e) {
      _safeDisconnect();
      throw AwsIotConnectException(
        'Could not connect to AWS IoT Core',
        cause: e,
      );
    }
    if (status?.state != MqttConnectionState.connected) {
      _safeDisconnect();
      throw AwsIotConnectException(
        'AWS IoT Core refused the connection (${status?.returnCode})',
      );
    }
    _wasConnected = true;
    _updates = _client.updates?.listen(_handleUpdates);
  }

  @override
  void disconnect() {
    _closedLocally = true;
    _safeDisconnect();
    _cleanUp();
  }

  @override
  Future<void> subscribe(String topicFilter, AwsIotQos qos) {
    final completer = _pendingSubscriptions.putIfAbsent(
      topicFilter,
      Completer<void>.new,
    );
    final subscription = _client.subscribe(topicFilter, _mqttQos(qos));
    if (subscription == null) {
      _pendingSubscriptions.remove(topicFilter);
      return Future.error(AwsIotSubscribeException(topicFilter));
    }
    return completer.future;
  }

  @override
  void unsubscribe(String topicFilter) {
    if (isConnected) _client.unsubscribe(topicFilter);
  }

  @override
  void publish(String topic, Uint8List payload, AwsIotQos qos, bool retain) {
    final buffer = Uint8Buffer()..addAll(payload);
    _client.publishMessage(topic, _mqttQos(qos), buffer, retain: retain);
  }

  void _handleUpdates(List<MqttReceivedMessage<MqttMessage>> batch) {
    for (final received in batch) {
      final message = received.payload;
      if (message is! MqttPublishMessage) continue;
      _messages.add(
        AwsIotMessage(
          topic: received.topic,
          payload: Uint8List.fromList(message.payload.message),
          retained: message.header?.retain ?? false,
        ),
      );
    }
  }

  void _handleSubscribed(String topic) =>
      _pendingSubscriptions.remove(topic)?.complete();

  void _handleSubscribeFail(String topic) => _pendingSubscriptions
      .remove(topic)
      ?.completeError(AwsIotSubscribeException(topic));

  void _handleDisconnected() {
    final unsolicited =
        _client.connectionStatus?.disconnectionOrigin ==
        MqttDisconnectionOrigin.unsolicited;
    _cleanUp();
    if (_wasConnected && !_closedLocally && unsolicited) {
      _onUnsolicitedDisconnect?.call();
    }
  }

  void _cleanUp() {
    unawaited(_updates?.cancel());
    _updates = null;
    for (final completer in _pendingSubscriptions.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const AwsIotNotConnectedException(
            'Connection closed before the subscription was acknowledged',
          ),
        );
      }
    }
    _pendingSubscriptions.clear();
  }

  void _safeDisconnect() {
    try {
      _client.disconnect();
    } catch (_) {
      // Already closed.
    }
  }

  static MqttQos _mqttQos(AwsIotQos qos) => switch (qos) {
    AwsIotQos.atMostOnce => MqttQos.atMostOnce,
    AwsIotQos.atLeastOnce => MqttQos.atLeastOnce,
  };
}
