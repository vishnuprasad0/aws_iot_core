import 'dart:convert';

import 'package:aws_iot_core/aws_iot_core.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

void main() {
  late FakeTransportFactory factory;
  late FakeClock clock;
  late AwsIotClient client;

  setUp(() {
    factory = FakeTransportFactory();
    clock = FakeClock();
    client = buildClient(factory, clock: clock);
  });

  tearDown(() => client.dispose());

  test('exposes connection state and endpoint settings', () async {
    final states = <AwsIotConnectionState>[];
    client.connectionState.listen(states.add);
    expect(client.endpoint, testEndpoint);
    expect(client.region, 'us-east-1');
    expect(client.isConnected, isFalse);

    await client.connect();

    expect(client.isConnected, isTrue);
    expect(client.lastError, isNull);
    expect(states, [
      AwsIotConnectionState.connecting,
      AwsIotConnectionState.connected,
    ]);
    expect(factory.last.config.url.host, testEndpoint);
  });

  test('default client IDs are random per instance and stable', () async {
    final other = buildClient(factory);
    expect(client.clientId, startsWith('aws-iot-core-'));
    expect(other.clientId, isNot(client.clientId));
    await client.connect();
    expect(factory.last.config.clientId, client.clientId);
    await other.dispose();
  });

  test('an explicit client ID is used as given', () async {
    final custom = AwsIotClient(
      endpoint: testEndpoint,
      region: 'us-east-1',
      credentialsProvider: const StaticCredentialsProvider(
        AwsIotCredentials(accessKeyId: 'a', secretAccessKey: 's'),
      ),
      clientId: 'my-device',
      transportFactory: factory.call,
    );
    await custom.connect();
    expect(factory.last.config.clientId, 'my-device');
    await custom.dispose();
  });

  test(
    'routes messages to subscribers and restores them after reconnect',
    () async {
      final received = <String>[];
      final sub = client
          .subscribe('devices/+/state')
          .listen((m) => received.add(m.payloadString));
      await client.connect();
      await settle();
      factory.last.deliver('devices/d1/state', {'n': 1});

      factory.last.drop();
      clock.elapseNext();
      await settle();
      expect(factory.last.subscribed, ['devices/+/state']);
      factory.last.deliver('devices/d1/state', {'n': 2});
      await settle();

      expect(received, ['{"n":1}', '{"n":2}']);
      await sub.cancel();
    },
  );

  test('messages from a replaced connection are not delivered', () async {
    final received = <String>[];
    final sub = client.subscribe('a').listen((m) => received.add(m.topic));
    await client.connect();
    final first = factory.last;
    first.drop();
    clock.elapseNext();
    await settle();
    first.deliver('a', 1);
    await settle();
    expect(received, isEmpty);
    await sub.cancel();
  });

  group('publish', () {
    test('throws when not connected', () {
      expect(
        () => client.publishString('a/b', 'hi'),
        throwsA(isA<AwsIotNotConnectedException>()),
      );
    });

    test('rejects wildcard topics', () async {
      await client.connect();
      expect(() => client.publish('a/+', [1]), throwsArgumentError);
    });

    test('sends bytes, text and JSON with QoS and retain', () async {
      await client.connect();
      client
        ..publish('raw', [1, 2, 3], retain: true)
        ..publishString('text', 'hi', qos: AwsIotQos.atMostOnce)
        ..publishJson('json', {'on': true});

      final published = factory.last.published;
      expect(published.map((m) => m.topic), ['raw', 'text', 'json']);
      expect(published[0].payload, [1, 2, 3]);
      expect(published[0].retain, isTrue);
      expect(published[1].qos, AwsIotQos.atMostOnce);
      expect(utf8.decode(published[2].payload), '{"on":true}');
      expect(published[2].qos, AwsIotQos.atLeastOnce);
    });
  });

  test('shadow() caches one instance per thing and shadow name', () {
    expect(client.shadow('t'), same(client.shadow('t')));
    expect(client.shadow('t', shadowName: 'a'), isNot(client.shadow('t')));
    expect(client.shadow('t').thingName, 't');
  });

  test('disconnect() keeps subscriptions for the next connect', () async {
    final sub = client.subscribe('a').listen((_) {});
    await client.connect();
    await client.disconnect();
    expect(client.state, AwsIotConnectionState.disconnected);
    await client.connect();
    await settle();
    expect(factory.last.subscribed, ['a']);
    await sub.cancel();
  });

  test('dispose() closes streams and blocks further use', () async {
    final done = client.subscribe('a').toList();
    await client.connect();
    await client.dispose();
    await client.dispose();
    expect(await done, isEmpty);
    expect(client.connect, throwsStateError);
    expect(() => client.subscribe('a'), throwsStateError);
    expect(() => client.shadow('t'), throwsStateError);
  });
}
