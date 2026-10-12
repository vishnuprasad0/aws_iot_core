@TestOn('vm')
library;

import 'package:aws_iot_core/aws_iot_core.dart';
import 'package:aws_iot_core/src/infrastructure/transport/platform_transport_io.dart';
import 'package:test/test.dart';

void main() {
  final config = TransportConfig(
    url: Uri.parse(
      'wss://xxxxxxxx-ats.iot.us-east-1.amazonaws.com/mqtt?X-Amz-Signature=x',
    ),
    clientId: 'client-1',
    keepAlive: const Duration(seconds: 60),
    connectTimeout: const Duration(seconds: 10),
  );

  test('uses a WebSocket client on port 443 with the signed URL', () {
    final client = buildServerClient(config);
    expect(client.server, config.url.toString());
    expect(client.port, 443);
    expect(client.useWebSocket, isTrue);
    expect(client.secure, isFalse, reason: 'TLS comes from wss://');
    expect(client.maxConnectionAttempts, 1);
  });

  test('creates a disconnected transport without touching the network', () {
    final transport = createPlatformTransport(config);
    expect(transport.isConnected, isFalse);
  });
}
