// Runs against a real AWS IoT Core endpoint. Skipped unless these environment
// variables are set:
//
//   AWS_IOT_ENDPOINT   e.g. xxxxxxxx-ats.iot.us-east-1.amazonaws.com
//   AWS_REGION         e.g. us-east-1
//   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, optional AWS_SESSION_TOKEN
//   AWS_IOT_THING      optional; a thing whose shadow the test may update
//
// Run with:  dart test --tags integration
@Tags(['integration'])
library;

import 'dart:io';

import 'package:aws_iot_core/aws_iot_core.dart';
import 'package:test/test.dart';

void main() {
  final env = Platform.environment;
  final endpoint = env['AWS_IOT_ENDPOINT'];
  final region = env['AWS_REGION'];
  final accessKey = env['AWS_ACCESS_KEY_ID'];
  final secretKey = env['AWS_SECRET_ACCESS_KEY'];
  final configured = [
    endpoint,
    region,
    accessKey,
    secretKey,
  ].every((v) => v != null && v.isNotEmpty);

  group('AWS IoT Core', skip: configured ? false : 'AWS env vars not set', () {
    late AwsIotClient client;
    late AwsIotCredentialsProvider credentials;

    setUp(() {
      credentials = StaticCredentialsProvider(
        AwsIotCredentials(
          accessKeyId: accessKey!,
          secretAccessKey: secretKey!,
          sessionToken: env['AWS_SESSION_TOKEN'],
        ),
      );
      client = AwsIotClient(
        endpoint: endpoint!,
        region: region!,
        credentialsProvider: credentials,
      );
    });

    tearDown(() => client.dispose());

    test('publishes and receives its own message', () async {
      await client.connect();
      final topic = 'aws_iot_core/test/${client.clientId}';
      final received = client.subscribe(topic).first;
      // Give the broker a moment to register the subscription.
      await Future<void>.delayed(const Duration(seconds: 1));
      client.publishJson(topic, {'hello': 'world'});
      final message = await received.timeout(const Duration(seconds: 10));
      expect(message.json, {'hello': 'world'});
    });

    test('reconnects and resubscribes after AWS IoT drops it', () async {
      await client.connect();
      final topic = 'aws_iot_core/test/${client.clientId}/reconnect';
      final received = client.subscribe(topic).first;
      await Future<void>.delayed(const Duration(seconds: 1));

      // AWS IoT drops a connection when another one uses the same client ID.
      final dropped = client.connectionState.firstWhere(
        (s) => s != AwsIotConnectionState.connected,
      );
      final intruder = AwsIotClient(
        endpoint: endpoint!,
        region: region!,
        credentialsProvider: credentials,
        clientId: client.clientId,
        reconnectPolicy: const NoReconnect(),
      );
      addTearDown(intruder.dispose);
      await intruder.connect();
      await dropped.timeout(const Duration(seconds: 10));

      await client.connectionState
          .firstWhere((s) => s == AwsIotConnectionState.connected)
          .timeout(const Duration(seconds: 30));
      await Future<void>.delayed(const Duration(seconds: 1));
      client.publishJson(topic, {'after': 'reconnect'});
      final message = await received.timeout(const Duration(seconds: 10));
      expect(message.json, {'after': 'reconnect'});
    });

    test('updates and reads a shadow', () async {
      final thing = env['AWS_IOT_THING'];
      if (thing == null) {
        markTestSkipped('AWS_IOT_THING not set');
        return;
      }
      await client.connect();
      final shadow = client.shadow(thing);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await shadow.update(reported: {'aws_iot_core_test': stamp});
      final doc = await shadow.get();
      expect(doc.reported?['aws_iot_core_test'], stamp);
    });
  });
}
