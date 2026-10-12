import '../../domain/transport.dart';

/// Fallback for platforms without `dart:io` or `dart:js_interop`.
MqttTransport createPlatformTransport(TransportConfig config) =>
    throw UnsupportedError(
      'aws_iot_core has no MQTT transport for this platform',
    );
