import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:aws_iot_core/aws_iot_core.dart';

typedef PublishedMessage = ({
  String topic,
  Uint8List payload,
  AwsIotQos qos,
  bool retain,
});

/// Called when a [FakeTransport] publishes JSON.
typedef JsonResponder =
    void Function(
      FakeTransport transport,
      String topic,
      Map<String, dynamic> body,
    );

class FakeTransport implements MqttTransport {
  FakeTransport(this.config, {this.failConnect = false});

  final TransportConfig config;
  final bool failConnect;
  bool connected = false;
  bool closedLocally = false;
  final subscribed = <String>[];
  final unsubscribed = <String>[];
  final published = <PublishedMessage>[];
  final failSubscriptions = <String>{};

  /// Subscriptions on these filters never get an acknowledgement.
  final silentSubscriptions = <String>{};
  JsonResponder? onPublishJson;

  final _messages = StreamController<AwsIotMessage>.broadcast(sync: true);
  void Function()? _onDrop;

  @override
  set onUnsolicitedDisconnect(void Function()? callback) => _onDrop = callback;

  @override
  Future<void> connect() async {
    if (failConnect) throw StateError('connection refused');
    connected = true;
  }

  @override
  void disconnect() {
    connected = false;
    closedLocally = true;
  }

  @override
  bool get isConnected => connected;

  @override
  Future<void> subscribe(String topicFilter, AwsIotQos qos) {
    subscribed.add(topicFilter);
    if (failSubscriptions.contains(topicFilter)) {
      return Future.error(AwsIotSubscribeException(topicFilter));
    }
    if (silentSubscriptions.contains(topicFilter)) {
      return Completer<void>().future;
    }
    return Future.value();
  }

  @override
  void unsubscribe(String topicFilter) => unsubscribed.add(topicFilter);

  @override
  void publish(String topic, Uint8List payload, AwsIotQos qos, bool retain) {
    published.add((topic: topic, payload: payload, qos: qos, retain: retain));
    final responder = onPublishJson;
    if (responder != null) {
      responder(this, topic, asMap(jsonDecode(utf8.decode(payload))));
    }
  }

  @override
  Stream<AwsIotMessage> get messages => _messages.stream;

  void deliver(String topic, Object? json) =>
      deliverRaw(topic, jsonEncode(json));

  void deliverRaw(String topic, String text) =>
      _messages.add(AwsIotMessage(topic: topic, payload: utf8.encode(text)));

  void drop() {
    connected = false;
    _onDrop?.call();
  }
}

class FakeTransportFactory {
  final created = <FakeTransport>[];

  /// Number of upcoming connection attempts that should fail.
  int failNext = 0;

  JsonResponder? onPublishJson;

  FakeTransport get last => created.last;

  MqttTransport call(TransportConfig config) {
    final fail = failNext > 0;
    if (fail) failNext--;
    final transport = FakeTransport(config, failConnect: fail)
      ..onPublishJson = onPublishJson;
    created.add(transport);
    return transport;
  }
}

/// A clock whose delays only finish when the test says so.
class FakeClock implements Clock {
  FakeClock([DateTime? start])
    : current = start ?? DateTime.utc(2026, 1, 2, 3, 4, 5);

  DateTime current;

  final requested = <Duration>[];
  final _pending = <FakeDelay>[];

  List<FakeDelay> get pending => List.unmodifiable(_pending);

  @override
  DateTime now() => current;

  @override
  Delay delay(Duration duration) {
    requested.add(duration);
    final delay = FakeDelay(duration);
    _pending.add(delay);
    return delay;
  }

  /// Finishes the oldest pending delay and advances time by its duration.
  void elapseNext() {
    final delay = _pending.removeAt(0);
    current = current.add(delay.duration);
    delay.finish();
  }
}

class FakeDelay implements Delay {
  FakeDelay(this.duration);

  final Duration duration;
  final _completer = Completer<void>();
  bool cancelled = false;

  @override
  Future<void> get done => _completer.future;

  @override
  void cancel() {
    cancelled = true;
    finish();
  }

  void finish() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// Returns different credentials on each call, like a refreshing Cognito
/// session.
class CountingCredentialsProvider implements AwsIotCredentialsProvider {
  int calls = 0;

  @override
  Future<AwsIotCredentials> getCredentials() async {
    calls++;
    return AwsIotCredentials(
      accessKeyId: 'AKID$calls',
      secretAccessKey: 'secret$calls',
      sessionToken: 'token$calls',
    );
  }
}

/// Backoff without jitter: 1 s, 2 s, 4 s, ... capped at 60 s.
const testBackoff = ExponentialBackoff(jitter: 0);

const testEndpoint = 'xxxxxxxx-ats.iot.us-east-1.amazonaws.com';

AwsIotClient buildClient(
  FakeTransportFactory factory, {
  AwsIotCredentialsProvider? credentials,
  FakeClock? clock,
  BeforeConnectHook? beforeConnect,
  BackoffPolicy reconnectPolicy = testBackoff,
  Duration subscribeTimeout = const Duration(seconds: 10),
}) => AwsIotClient(
  endpoint: testEndpoint,
  region: 'us-east-1',
  credentialsProvider: credentials ?? CountingCredentialsProvider(),
  beforeConnect: beforeConnect,
  reconnectPolicy: reconnectPolicy,
  subscribeTimeout: subscribeTimeout,
  transportFactory: factory.call,
  clock: clock ?? FakeClock(),
);

/// The access key ID a URL was signed with.
String signedKey(Uri url) =>
    url.queryParameters['X-Amz-Credential']!.split('/').first;

Map<String, dynamic> asMap(Object? value) =>
    Map<String, dynamic>.from(value! as Map);

/// Lets pending microtasks and zero-duration timers run.
Future<void> settle() => Future<void>.delayed(Duration.zero);
