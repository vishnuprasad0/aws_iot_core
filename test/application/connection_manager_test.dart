import 'package:aws_iot_core/aws_iot_core.dart';
import 'package:aws_iot_core/src/application/connection_manager.dart';
import 'package:test/test.dart';

import '../support/fakes.dart';

void main() {
  late FakeTransportFactory factory;
  late CountingCredentialsProvider credentials;
  late FakeClock clock;
  late List<String> events;
  late List<AwsIotConnectionState> states;
  late ConnectionManager manager;

  ConnectionManager build({
    BackoffPolicy backoff = testBackoff,
    BeforeConnectHook? beforeConnect,
  }) {
    final built = ConnectionManager(
      clientId: 'client-1',
      credentialsProvider: credentials,
      signer: const AwsIotUrlSigner(
        endpoint: testEndpoint,
        region: 'us-east-1',
      ),
      transportFactory: factory.call,
      clock: clock,
      backoff: backoff,
      keepAlive: const Duration(seconds: 60),
      connectTimeout: const Duration(seconds: 10),
      beforeConnect: beforeConnect,
      onConnected: (t) => events.add(
        'connected #${factory.created.indexOf(t as FakeTransport)}',
      ),
      onDisconnected: () => events.add('disconnected'),
    );
    built.states.listen(states.add);
    return built;
  }

  setUp(() {
    factory = FakeTransportFactory();
    credentials = CountingCredentialsProvider();
    clock = FakeClock();
    events = [];
    states = [];
    manager = build();
  });

  tearDown(() => manager.close());

  group('connect', () {
    test('signs a URL with the current credentials and time', () async {
      await manager.connect();
      final config = factory.last.config;
      expect(signedKey(config.url), 'AKID1');
      expect(config.url.queryParameters['X-Amz-Date'], '20260102T030405Z');
      expect(config.url.queryParameters['X-Amz-Security-Token'], 'token1');
      expect(config.clientId, 'client-1');
      expect(manager.state, AwsIotConnectionState.connected);
      expect(manager.transport, same(factory.last));
      expect(events, ['connected #0']);
      expect(states, [
        AwsIotConnectionState.connecting,
        AwsIotConnectionState.connected,
      ]);
    });

    test('concurrent calls share one attempt', () async {
      await Future.wait([manager.connect(), manager.connect()]);
      await manager.connect();
      expect(factory.created, hasLength(1));
      expect(credentials.calls, 1);
    });

    test(
      'a failed attempt throws, records the error and stays disconnected',
      () async {
        factory.failNext = 1;
        await expectLater(
          manager.connect(),
          throwsA(isA<AwsIotConnectException>()),
        );
        expect(manager.state, AwsIotConnectionState.disconnected);
        expect(manager.lastError, isA<AwsIotConnectException>());
        expect(factory.last.closedLocally, isTrue);

        await manager.connect();
        expect(manager.lastError, isNull);
      },
    );

    test('credential errors are wrapped with their cause', () async {
      manager = build();
      final failing = ConnectionManager(
        clientId: 'c',
        credentialsProvider: CallbackCredentialsProvider(
          () async => throw StateError('signed out'),
        ),
        signer: const AwsIotUrlSigner(endpoint: testEndpoint, region: 'r'),
        transportFactory: factory.call,
        clock: clock,
        backoff: testBackoff,
        keepAlive: const Duration(seconds: 60),
        connectTimeout: const Duration(seconds: 10),
      );
      await expectLater(
        failing.connect(),
        throwsA(
          isA<AwsIotConnectException>().having(
            (e) => e.cause,
            'cause',
            isA<StateError>(),
          ),
        ),
      );
      expect(factory.created, isEmpty);
      await failing.close();
    });

    test('runs beforeConnect with the attempt credentials', () async {
      final seen = <String>[];
      manager = build(beforeConnect: (c) async => seen.add(c.accessKeyId));
      await manager.connect();
      factory.last.drop();
      clock.elapseNext();
      await settle();
      expect(seen, ['AKID1', 'AKID2']);
    });

    test('disconnect() during an attempt cancels it', () async {
      final pending = expectLater(
        manager.connect(),
        throwsA(isA<AwsIotConnectException>()),
      );
      await manager.disconnect();
      await pending;
      expect(manager.state, AwsIotConnectionState.disconnected);
      expect(manager.transport, isNull);
    });

    test('cannot connect after close()', () async {
      await manager.close();
      expect(manager.connect, throwsStateError);
    });
  });

  group('reconnect', () {
    test(
      'waits for the backoff, then re-signs with fresh credentials',
      () async {
        await manager.connect();
        factory.last.drop();

        expect(manager.state, AwsIotConnectionState.reconnecting);
        expect(events, ['connected #0', 'disconnected']);
        expect(clock.requested, [const Duration(seconds: 1)]);
        expect(factory.created, hasLength(1), reason: 'waits for the delay');

        clock.elapseNext();
        await settle();

        expect(manager.state, AwsIotConnectionState.connected);
        expect(factory.created, hasLength(2));
        final url = factory.last.config.url;
        expect(signedKey(url), 'AKID2');
        expect(url.queryParameters['X-Amz-Security-Token'], 'token2');
        expect(url.queryParameters['X-Amz-Date'], '20260102T030406Z');
        expect(url, isNot(factory.created.first.config.url));
        expect(factory.last.config.clientId, 'client-1');
        expect(events.last, 'connected #1');
      },
    );

    test('backs off exponentially and signs every attempt anew', () async {
      await manager.connect();
      factory.failNext = 2;
      factory.last.drop();

      for (var i = 0; i < 3; i++) {
        clock.elapseNext();
        await settle();
      }

      expect(clock.requested, const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
      ]);
      expect(manager.state, AwsIotConnectionState.connected);
      expect(factory.created.map((t) => signedKey(t.config.url)), [
        'AKID1',
        'AKID2',
        'AKID3',
        'AKID4',
      ]);
      expect(factory.created.map((t) => t.config.url).toSet(), hasLength(4));
    });

    test('a solicited disconnect does not reconnect', () async {
      await manager.connect();
      final transport = factory.last;
      await manager.disconnect();
      expect(transport.closedLocally, isTrue);
      expect(clock.requested, isEmpty);
      expect(manager.state, AwsIotConnectionState.disconnected);
      expect(events, ['connected #0', 'disconnected']);
    });

    test('ignores callbacks from replaced connections', () async {
      await manager.connect();
      final first = factory.last;
      first.drop();
      clock.elapseNext();
      await settle();
      expect(manager.state, AwsIotConnectionState.connected);

      first.drop();
      expect(manager.state, AwsIotConnectionState.connected);
      expect(clock.requested, hasLength(1));
      expect(factory.created, hasLength(2));
    });

    test('disconnect() cancels a pending reconnect', () async {
      await manager.connect();
      factory.last.drop();
      final delay = clock.pending.single;

      await manager.disconnect();
      await settle();

      expect(delay.cancelled, isTrue);
      expect(factory.created, hasLength(1));
      expect(manager.state, AwsIotConnectionState.disconnected);
    });

    test('connect() while reconnecting waits for the result', () async {
      await manager.connect();
      factory.last.drop();
      final waiting = manager.connect();
      clock.elapseNext();
      await waiting;
      expect(manager.state, AwsIotConnectionState.connected);
      expect(factory.created, hasLength(2));
    });

    test('gives up when the policy says so', () async {
      manager = build(
        backoff: const ExponentialBackoff(jitter: 0, maxAttempts: 2),
      );
      await manager.connect();
      factory.failNext = 5;
      factory.last.drop();
      final waiting = expectLater(
        manager.connect(),
        throwsA(isA<AwsIotConnectException>()),
      );

      clock.elapseNext();
      await settle();
      clock.elapseNext();
      await settle();

      expect(manager.state, AwsIotConnectionState.disconnected);
      expect(factory.created, hasLength(3));
      await waiting;
    });

    test('NoReconnect leaves the client disconnected', () async {
      manager = build(backoff: const NoReconnect());
      await manager.connect();
      factory.last.drop();
      await settle();
      expect(manager.state, AwsIotConnectionState.disconnected);
      expect(factory.created, hasLength(1));
    });

    test(
      'a drop after disconnect() was requested does not reconnect',
      () async {
        await manager.connect();
        final transport = factory.last;
        final pending = manager.disconnect();
        transport.drop();
        await pending;
        expect(clock.requested, isEmpty);
      },
    );
  });
}
