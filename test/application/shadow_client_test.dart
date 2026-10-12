import 'package:aws_iot_core/aws_iot_core.dart';
import 'package:test/test.dart';

import '../support/fakes.dart';

void main() {
  late FakeTransportFactory factory;
  late AwsIotClient client;
  const prefix = r'$aws/things/thing-1/shadow';

  setUp(() {
    factory = FakeTransportFactory();
    client = buildClient(factory);
  });

  tearDown(() => client.dispose());

  /// Answers every shadow request with [outcome] and the body from [reply].
  void respond(
    String outcome,
    Map<String, Object?> Function(Map<String, dynamic> request) reply,
  ) {
    factory.onPublishJson = (transport, topic, request) {
      transport.deliver('$topic/$outcome', {
        ...reply(request),
        'clientToken': request['clientToken'],
      });
    };
  }

  group('get', () {
    test('subscribes first, then resolves the accepted document', () async {
      respond(
        'accepted',
        (_) => {
          'state': {
            'desired': {'on': true},
            'reported': {'on': false},
          },
          'version': 7,
        },
      );
      await client.connect();

      final doc = await client.shadow('thing-1').get();

      expect(doc.version, 7);
      expect(doc.desired, {'on': true});
      expect(factory.last.subscribed, ['$prefix/get/+']);
      expect(factory.last.published.single.topic, '$prefix/get');
    });

    test('rejected requests throw with the AWS error code', () async {
      respond('rejected', (_) => {'code': 404, 'message': 'No shadow exists'});
      await client.connect();

      await expectLater(
        client.shadow('thing-1').get(),
        throwsA(
          isA<AwsIotShadowRejectedException>()
              .having((e) => e.code, 'code', 404)
              .having((e) => e.message, 'message', 'No shadow exists'),
        ),
      );
    });

    test('rejections without details still fail', () async {
      respond('rejected', (_) => {});
      await client.connect();
      await expectLater(
        client.shadow('thing-1').get(),
        throwsA(
          isA<AwsIotShadowRejectedException>().having((e) => e.code, 'code', 0),
        ),
      );
    });

    test('responses are matched by clientToken', () async {
      factory.onPublishJson = (transport, topic, request) {
        transport
          ..deliver('$topic/accepted', {'version': 1, 'clientToken': 'other'})
          ..deliverRaw('$topic/accepted', 'not json')
          ..deliver('$topic/accepted', ['not', 'an', 'object'])
          ..deliver('$topic/delta', {'clientToken': request['clientToken']})
          ..deliver('$topic/accepted', {
            'version': 2,
            'clientToken': request['clientToken'],
          });
      };
      await client.connect();

      final doc = await client.shadow('thing-1').get();
      expect(doc.version, 2);
    });

    test('times out when no response arrives', () async {
      await client.connect();
      final shadow = client.shadow(
        'thing-2',
        requestTimeout: const Duration(milliseconds: 20),
      );
      await expectLater(shadow.get(), throwsA(isA<AwsIotTimeoutException>()));
    });

    test('fails fast when not connected, and works once connected', () async {
      respond('accepted', (_) => {'version': 1});
      final shadow = client.shadow('thing-1');
      await expectLater(
        shadow.get(),
        throwsA(isA<AwsIotNotConnectedException>()),
      );

      await client.connect();
      expect((await shadow.get()).version, 1);
    });
  });

  group('update', () {
    test('sends state, version and clientToken', () async {
      Map<String, dynamic>? sent;
      respond('accepted', (request) {
        sent = request;
        return {'state': request['state'], 'version': 8};
      });
      await client.connect();

      final doc = await client
          .shadow('thing-1')
          .update(desired: {'brightness': 80}, version: 7);

      expect(sent!['state'], {
        'desired': {'brightness': 80},
      });
      expect(sent!['version'], 7);
      expect(sent!['clientToken'], isA<String>());
      expect(doc.version, 8);
      expect(factory.last.published.single.topic, '$prefix/update');
    });

    test('reported-only updates omit desired and version', () async {
      Map<String, dynamic>? sent;
      respond('accepted', (request) {
        sent = request;
        return {};
      });
      await client.connect();
      await client.shadow('thing-1').update(reported: {'on': true});
      expect(sent!['state'], {
        'reported': {'on': true},
      });
      expect(sent!.containsKey('version'), isFalse);
    });

    test('version conflicts surface as 409', () async {
      respond('rejected', (_) => {'code': 409, 'message': 'Version conflict'});
      await client.connect();
      await expectLater(
        client.shadow('thing-1').update(desired: {'a': 1}, version: 1),
        throwsA(
          isA<AwsIotShadowRejectedException>().having(
            (e) => e.code,
            'code',
            409,
          ),
        ),
      );
    });

    test('requires desired or reported state', () {
      expect(() => client.shadow('thing-1').update(), throwsArgumentError);
    });
  });

  group('delete', () {
    test('resolves on accepted', () async {
      respond('accepted', (_) => {'version': 3});
      await client.connect();
      await client.shadow('thing-1').delete();
      expect(factory.last.published.single.topic, '$prefix/delete');
    });

    test('throws on rejected', () async {
      respond('rejected', (_) => {'code': 404, 'message': 'missing'});
      await client.connect();
      await expectLater(
        client.shadow('thing-1').delete(),
        throwsA(isA<AwsIotShadowRejectedException>()),
      );
    });
  });

  test('named shadows use the /name/ topic layout', () async {
    respond('accepted', (_) => {'version': 1});
    await client.connect();

    final shadow = client.shadow('thing-1', shadowName: 'config');
    expect(shadow.topicPrefix, '$prefix/name/config');
    expect(shadow.shadowName, 'config');
    await shadow.get();
    expect(factory.last.published.single.topic, '$prefix/name/config/get');
  });

  test('delta and documents streams decode messages', () async {
    await client.connect();
    final shadow = client.shadow('thing-1');
    final deltaFuture = shadow.delta.first;
    final docsFuture = shadow.documents.first;
    await settle();

    factory.last
      ..deliver('$prefix/update/delta', {
        'state': {'on': true},
        'version': 9,
      })
      ..deliver('$prefix/update/documents', {
        'previous': {
          'state': {
            'desired': {'on': false},
          },
          'version': 8,
        },
        'current': {
          'state': {
            'desired': {'on': true},
          },
          'version': 9,
        },
        'timestamp': 1767323045,
      });

    final delta = await deltaFuture;
    expect(delta.state, {'on': true});
    expect(delta.version, 9);
    final docs = await docsFuture;
    expect(docs.previous!.version, 8);
    expect(docs.current!.desired, {'on': true});
  });

  test('dispose() fails pending requests', () async {
    await client.connect();
    final shadow = client.shadow('thing-1');
    final pending = shadow.get();
    await settle();
    await shadow.dispose();
    await expectLater(pending, throwsA(isA<AwsIotNotConnectedException>()));
  });
}
