import 'dart:convert';
import 'dart:typed_data';

/// MQTT quality of service levels supported by AWS IoT Core.
enum AwsIotQos {
  /// QoS 0: delivered at most once.
  atMostOnce,

  /// QoS 1: delivered at least once.
  atLeastOnce,
}

/// A message received from AWS IoT Core.
class AwsIotMessage {
  /// Creates a message received on [topic].
  AwsIotMessage({
    required this.topic,
    required this.payload,
    this.retained = false,
  });

  /// The concrete topic the message was published to.
  final String topic;

  /// Raw payload bytes.
  final Uint8List payload;

  /// Whether the broker delivered this as a retained message.
  final bool retained;

  /// The payload decoded as UTF-8.
  String get payloadString => utf8.decode(payload, allowMalformed: true);

  /// The payload decoded as JSON. Throws [FormatException] if it is not JSON.
  Object? get json => jsonDecode(payloadString);

  @override
  String toString() => 'AwsIotMessage($topic, ${payload.length} bytes)';
}
