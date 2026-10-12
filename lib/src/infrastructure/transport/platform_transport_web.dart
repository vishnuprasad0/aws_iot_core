import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

import '../../domain/transport.dart';
import 'mqtt_client_transport.dart';

/// Transport for browsers.
MqttTransport createPlatformTransport(TransportConfig config) =>
    MqttClientTransport(
      MqttBrowserClient.withPort(
        config.url.toString(),
        config.clientId,
        443,
        maxConnectionAttempts: 1,
      )..websocketProtocols = MqttClientConstants.protocolsSingleDefault,
      config,
    );
