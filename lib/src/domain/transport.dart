import 'dart:async';
import 'dart:typed_data';

import 'message.dart';

/// Settings for one MQTT connection attempt.
class TransportConfig {
  /// Creates the settings for one attempt.
  const TransportConfig({
    required this.url,
    required this.clientId,
    required this.keepAlive,
    required this.connectTimeout,
  });

  /// The signed `wss://` URL.
  final Uri url;

  /// The MQTT client ID.
  final String clientId;

  /// MQTT keep-alive interval.
  final Duration keepAlive;

  /// How long to wait for the broker to accept the connection.
  final Duration connectTimeout;
}

/// The MQTT operations the client needs from a transport.
///
/// One instance represents one connection attempt; a reconnect builds a new
/// instance with a freshly signed URL. Implement this to plug in a different
/// MQTT library, or to fake the network in tests.
abstract interface class MqttTransport {
  /// Connects, or throws if the broker cannot be reached or refuses.
  Future<void> connect();

  /// Closes the connection on request. Must not call
  /// [onUnsolicitedDisconnect].
  void disconnect();

  /// Whether the connection is currently open.
  bool get isConnected;

  /// Subscribes and completes when the broker acknowledges.
  Future<void> subscribe(String topicFilter, AwsIotQos qos);

  /// Removes a broker subscription.
  void unsubscribe(String topicFilter);

  /// Publishes [payload] to [topic].
  void publish(String topic, Uint8List payload, AwsIotQos qos, bool retain);

  /// Messages for all subscriptions on this connection.
  Stream<AwsIotMessage> get messages;

  /// Called when the connection drops without [disconnect] being called.
  set onUnsolicitedDisconnect(void Function()? callback);
}

/// Creates a transport for one connection attempt.
typedef MqttTransportFactory = MqttTransport Function(TransportConfig config);
