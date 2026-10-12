import 'package:mqtt_client/mqtt_server_client.dart';

import '../../domain/transport.dart';
import 'mqtt_client_transport.dart';

/// Transport for Android, iOS, desktop and the Dart VM.
MqttTransport createPlatformTransport(TransportConfig config) =>
    MqttClientTransport(buildServerClient(config), config);

/// The `mqtt_client` client used on non-web platforms.
MqttServerClient buildServerClient(TransportConfig config) =>
    MqttServerClient.withPort(
        config.url.toString(),
        config.clientId,
        443,
        maxConnectionAttempts: 1,
      )
      ..useWebSocket = true
      // TLS comes from the wss:// scheme of the signed URL.
      ..secure = false;
