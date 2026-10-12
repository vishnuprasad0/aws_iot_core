import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:aws_iot_core/aws_iot_core.dart';
import 'package:aws_iot_core/src/infrastructure/transport/mqtt_client_transport.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:test/test.dart';
import 'package:typed_data/typed_buffers.dart';

void main() {
  late FakeMqttClient client;
  late MqttClientTransport transport;
  late int unsolicitedDrops;

  setUp(() {
    client = FakeMqttClient();
    transport = MqttClientTransport(client, _config);
    unsolicitedDrops = 0;
    transport.onUnsolicitedDisconnect = () => unsolicitedDrops++;
  });

  test('configures mqtt_client for AWS IoT without auto-reconnect', () {
    expect(client.protocolV311, isTrue);
    expect(client.loggingOn, isFalse);
    expect(client.autoReconnect, isFalse);
    expect(client.keepAlivePeriod, 60);
    expect(client.disconnectOnNoResponsePeriod, 30);
    expect(client.connectTimeoutPeriod, 10000);
    expect(client.connectionMessage!.payload.clientIdentifier, 'client-1');
  });

  group('connect', () {
    test('succeeds when the broker accepts', () async {
      await transport.connect();
      expect(transport.isConnected, isTrue);
    });

    test('wraps library errors', () async {
      client.connectError = Exception('socket');
      await expectLater(
        transport.connect(),
        throwsA(
          isA<AwsIotConnectException>().having(
            (e) => e.cause,
            'cause',
            isA<Exception>(),
          ),
        ),
      );
    });

    test('reports a refused connection', () async {
      client.resultState = MqttConnectionState.faulted;
      await expectLater(
        transport.connect(),
        throwsA(isA<AwsIotConnectException>()),
      );
      expect(transport.isConnected, isFalse);
    });

    test('a disconnect() that throws is tolerated', () async {
      client
        ..connectError = Exception('socket')
        ..throwOnDisconnect = true;
      await expectLater(
        transport.connect(),
        throwsA(isA<AwsIotConnectException>()),
      );
    });
  });

  group('disconnects', () {
    test('an unsolicited drop is reported once connected', () async {
      await transport.connect();
      client.dropUnsolicited();
      expect(unsolicitedDrops, 1);
    });

    test('a requested disconnect is not reported', () async {
      await transport.connect();
      transport.disconnect();
      expect(unsolicitedDrops, 0);
      expect(client.disconnectCalls, 1);
    });

    test('a drop before the connection was up is not reported', () {
      client.dropUnsolicited();
      expect(unsolicitedDrops, 0);
    });
  });

  group('subscribe', () {
    test('completes on the broker acknowledgement', () async {
      await transport.connect();
      final ready = transport.subscribe('a/+', AwsIotQos.atLeastOnce);
      expect(client.subscriptions, {'a/+': MqttQos.atLeastOnce});
      client.onSubscribed!('a/+');
      await ready;
    });

    test('fails when the broker refuses', () async {
      await transport.connect();
      final ready = transport.subscribe('a', AwsIotQos.atMostOnce);
      client.onSubscribeFail!('a');
      await expectLater(ready, throwsA(isA<AwsIotSubscribeException>()));
    });

    test('fails when the library rejects the request', () async {
      client.rejectSubscribe = true;
      await expectLater(
        transport.subscribe('a', AwsIotQos.atLeastOnce),
        throwsA(isA<AwsIotSubscribeException>()),
      );
    });

    test('pending acknowledgements fail when the connection closes', () async {
      await transport.connect();
      final ready = transport.subscribe('a', AwsIotQos.atLeastOnce);
      client.dropUnsolicited();
      await expectLater(ready, throwsA(isA<AwsIotNotConnectedException>()));
    });

    test('unsubscribe only reaches the broker while connected', () async {
      transport.unsubscribe('a');
      expect(client.unsubscribed, isEmpty);
      await transport.connect();
      transport.unsubscribe('a');
      expect(client.unsubscribed, ['a']);
    });
  });

  test('publish forwards topic, QoS, bytes and retain', () async {
    await transport.connect();
    transport.publish(
      'a/b',
      Uint8List.fromList([1, 2]),
      AwsIotQos.atMostOnce,
      true,
    );
    final (topic, qos, data, retain) = client.publishedMessages.single;
    expect(topic, 'a/b');
    expect(qos, MqttQos.atMostOnce);
    expect(data, [1, 2]);
    expect(retain, isTrue);
  });

  test('converts received publish messages and skips others', () async {
    await transport.connect();
    final received = <AwsIotMessage>[];
    transport.messages.listen(received.add);

    client.updatesController.add([
      MqttReceivedMessage<MqttMessage>('a/b', _publish('a/b', '{"x":1}')),
      MqttReceivedMessage<MqttMessage>('a/c', MqttMessage()),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(received.single.topic, 'a/b');
    expect(received.single.json, {'x': 1});
    expect(received.single.retained, isFalse);
  });
}

final _config = TransportConfig(
  url: Uri.parse('wss://xxxxxxxx-ats.iot.us-east-1.amazonaws.com/mqtt'),
  clientId: 'client-1',
  keepAlive: const Duration(seconds: 60),
  connectTimeout: const Duration(seconds: 10),
);

MqttPublishMessage _publish(String topic, String text) => MqttPublishMessage()
    .toTopic(topic)
    .publishData(Uint8Buffer()..addAll(utf8.encode(text)));

class FakeMqttClient implements MqttClient {
  @override
  bool autoReconnect = true;
  @override
  int keepAlivePeriod = 0;
  @override
  int disconnectOnNoResponsePeriod = 0;
  @override
  int connectTimeoutPeriod = 0;
  @override
  MqttConnectMessage? connectionMessage;
  @override
  DisconnectCallback? onDisconnected;
  @override
  SubscribeCallback? onSubscribed;
  @override
  SubscribeFailCallback? onSubscribeFail;

  bool protocolV311 = false;
  bool? loggingOn;
  Object? connectError;
  MqttConnectionState resultState = MqttConnectionState.connected;
  bool rejectSubscribe = false;
  bool throwOnDisconnect = false;
  int disconnectCalls = 0;
  final status = MqttClientConnectionStatus();
  final subscriptions = <String, MqttQos>{};
  final unsubscribed = <String>[];
  final publishedMessages = <(String, MqttQos, List<int>, bool)>[];
  final updatesController =
      StreamController<List<MqttReceivedMessage<MqttMessage>>>();

  @override
  void setProtocolV311() => protocolV311 = true;

  @override
  void logging({required bool on, bool logPayloads = true}) => loggingOn = on;

  @override
  MqttClientConnectionStatus? get connectionStatus => status;

  @override
  Stream<List<MqttReceivedMessage<MqttMessage>>>? get updates =>
      updatesController.stream;

  @override
  Future<MqttClientConnectionStatus?> connect([
    String? username,
    String? password,
  ]) async {
    final error = connectError;
    if (error != null) throw error;
    status.state = resultState;
    return status;
  }

  @override
  void disconnect() {
    disconnectCalls++;
    if (throwOnDisconnect) throw StateError('already closed');
    status
      ..state = MqttConnectionState.disconnected
      ..disconnectionOrigin = MqttDisconnectionOrigin.solicited;
    onDisconnected?.call();
  }

  void dropUnsolicited() {
    status
      ..state = MqttConnectionState.disconnected
      ..disconnectionOrigin = MqttDisconnectionOrigin.unsolicited;
    onDisconnected?.call();
  }

  @override
  Subscription? subscribe(String topic, MqttQos qosLevel) {
    if (rejectSubscribe) return null;
    subscriptions[topic] = qosLevel;
    return Subscription();
  }

  @override
  void unsubscribe(String topic, {Object? expectAcknowledge = false}) =>
      unsubscribed.add(topic);

  @override
  int publishMessage(
    String topic,
    MqttQos qualityOfService,
    Uint8Buffer data, {
    bool retain = false,
  }) {
    publishedMessages.add((topic, qualityOfService, data.toList(), retain));
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}
