import 'dart:typed_data';

import 'package:aws_iot_core/aws_iot_core.dart';
import 'package:aws_iot_core/src/application/subscription_manager.dart';
import 'package:test/test.dart';

import '../support/fakes.dart';

void main() {
  late SubscriptionManager manager;
  late FakeTransport transport;

  setUp(() {
    manager = SubscriptionManager(subscribeTimeout: const Duration(seconds: 1));
    transport = FakeTransport(
      TransportConfig(
        url: Uri.parse('wss://example/mqtt'),
        clientId: 'c',
        keepAlive: const Duration(seconds: 60),
        connectTimeout: const Duration(seconds: 10),
      ),
    );
  });

  tearDown(() => manager.close());

  test(
    'one broker subscription per filter, released by the last listener',
    () async {
      manager.attachTransport(transport);
      final a = manager
          .subscribe('devices/+/state', AwsIotQos.atLeastOnce)
          .listen((_) {});
      final b = manager
          .subscribe('devices/+/state', AwsIotQos.atLeastOnce)
          .listen((_) {});
      await settle();
      expect(transport.subscribed, ['devices/+/state']);

      await a.cancel();
      expect(transport.unsubscribed, isEmpty);
      expect(manager.activeFilters, ['devices/+/state']);

      await b.cancel();
      expect(transport.unsubscribed, ['devices/+/state']);
      expect(manager.activeFilters, isEmpty);
    },
  );

  test('filters registered while disconnected subscribe on attach', () async {
    final sub = manager.subscribe('a/b', AwsIotQos.atMostOnce).listen((_) {});
    expect(transport.subscribed, isEmpty);
    await expectLater(
      manager.ready('a/b'),
      throwsA(isA<AwsIotNotConnectedException>()),
    );

    manager.attachTransport(transport);
    await manager.ready('a/b');
    expect(transport.subscribed, ['a/b']);
    await sub.cancel();
    expect(transport.unsubscribed, ['a/b']);
  });

  test('re-subscribes everything on a new transport', () async {
    final sub = manager.subscribe('a/#', AwsIotQos.atLeastOnce).listen((_) {});
    manager.attachTransport(transport);
    manager.detachTransport();
    final next = FakeTransport(transport.config);
    manager.attachTransport(next);
    await manager.ready('a/#');
    expect(next.subscribed, ['a/#']);
    await sub.cancel();
  });

  test('cancelling while detached does not unsubscribe', () async {
    final sub = manager.subscribe('a', AwsIotQos.atLeastOnce).listen((_) {});
    manager.attachTransport(transport);
    manager.detachTransport();
    await sub.cancel();
    expect(transport.unsubscribed, isEmpty);
  });

  test('routes messages by wildcard filter', () async {
    manager.attachTransport(transport);
    final plus = <String>[];
    final hash = <String>[];
    final other = <String>[];
    final subs = [
      manager
          .subscribe('devices/+/state', AwsIotQos.atLeastOnce)
          .listen((m) => plus.add(m.topic)),
      manager
          .subscribe('devices/#', AwsIotQos.atLeastOnce)
          .listen((m) => hash.add(m.topic)),
      manager
          .subscribe('alerts/#', AwsIotQos.atLeastOnce)
          .listen((m) => other.add(m.topic)),
    ];

    manager
      ..dispatch(_message('devices/d1/state'))
      ..dispatch(_message('devices/d1/config'));
    await settle();

    expect(plus, ['devices/d1/state']);
    expect(hash, ['devices/d1/state', 'devices/d1/config']);
    expect(other, isEmpty);
    for (final sub in subs) {
      await sub.cancel();
    }
  });

  test('a refused subscription is reported on the stream', () async {
    transport.failSubscriptions.add('forbidden');
    manager.attachTransport(transport);
    final errors = <Object>[];
    final sub = manager
        .subscribe('forbidden', AwsIotQos.atLeastOnce)
        .listen((_) {}, onError: errors.add);
    await settle();
    expect(errors.single, isA<AwsIotSubscribeException>());
    await sub.cancel();
  });

  test('a missing acknowledgement times out', () async {
    manager = SubscriptionManager(
      subscribeTimeout: const Duration(milliseconds: 20),
    );
    transport.silentSubscriptions.add('slow');
    manager.attachTransport(transport);
    final sub = manager
        .subscribe('slow', AwsIotQos.atLeastOnce)
        .listen((_) {}, onError: (_) {});
    await expectLater(
      manager.ready('slow'),
      throwsA(isA<AwsIotTimeoutException>()),
    );
    await sub.cancel();
  });

  test('ready() fails for filters without listeners', () {
    expect(manager.ready('nothing'), throwsStateError);
  });

  test('close() ends every stream', () async {
    final done = manager.subscribe('a', AwsIotQos.atLeastOnce).toList();
    await settle();
    await manager.close();
    expect(await done, isEmpty);
  });

  test('rejects invalid filters', () {
    expect(
      () => manager.subscribe('a/#/b', AwsIotQos.atLeastOnce),
      throwsArgumentError,
    );
  });
}

AwsIotMessage _message(String topic) =>
    AwsIotMessage(topic: topic, payload: Uint8List(0));
