import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'application/connection_manager.dart';
import 'application/exponential_backoff.dart';
import 'application/shadow_client.dart';
import 'application/subscription_manager.dart';
import 'application/topic_matcher.dart';
import 'domain/backoff_policy.dart';
import 'domain/clock.dart';
import 'domain/connection_state.dart';
import 'domain/credentials.dart';
import 'domain/errors.dart';
import 'domain/message.dart';
import 'domain/transport.dart';
import 'infrastructure/aws_iot_url_signer.dart';
import 'infrastructure/system_clock.dart';
import 'infrastructure/transport/platform_transport.dart';

/// A client for AWS IoT Core over MQTT on SigV4-signed WebSockets.
///
/// One instance holds one connection. Every connect and reconnect fetches
/// credentials from the credentials provider and signs a new URL, so
/// temporary Cognito credentials keep working across reconnects.
///
/// ```dart
/// final client = AwsIotClient(
///   endpoint: 'xxxxxxxx-ats.iot.us-east-1.amazonaws.com',
///   region: 'us-east-1',
///   credentialsProvider: myProvider,
/// );
/// await client.connect();
/// client.subscribe('devices/+/state').listen(print);
/// ```
class AwsIotClient {
  /// Creates a client. Nothing connects until [connect] is called.
  ///
  /// - [endpoint]: the AWS IoT data endpoint host.
  /// - [credentialsProvider]: called before every connection attempt.
  /// - [clientId]: MQTT client ID; random per instance by default.
  /// - [beforeConnect]: runs before every attempt with the credentials.
  /// - [reconnectPolicy]: backoff after unexpected disconnects. Use
  ///   [NoReconnect] to turn reconnecting off.
  /// - [transportFactory], [clock] and [random]: replace the network, time
  ///   and randomness, mainly for tests or a custom MQTT library.
  AwsIotClient({
    required this.endpoint,
    required this.region,
    required AwsIotCredentialsProvider credentialsProvider,
    String? clientId,
    BeforeConnectHook? beforeConnect,
    BackoffPolicy reconnectPolicy = const ExponentialBackoff(),
    Duration keepAlive = const Duration(seconds: 60),
    Duration connectTimeout = const Duration(seconds: 10),
    Duration subscribeTimeout = const Duration(seconds: 10),
    MqttTransportFactory? transportFactory,
    Clock? clock,
    Random? random,
  }) : _random = random ?? Random.secure() {
    this.clientId = clientId ?? _generateClientId(_random);
    _subscriptions = SubscriptionManager(subscribeTimeout: subscribeTimeout);
    _connection = ConnectionManager(
      clientId: this.clientId,
      credentialsProvider: credentialsProvider,
      signer: AwsIotUrlSigner(endpoint: endpoint, region: region),
      transportFactory: transportFactory ?? createPlatformTransport,
      clock: clock ?? const SystemClock(),
      backoff: reconnectPolicy,
      keepAlive: keepAlive,
      connectTimeout: connectTimeout,
      beforeConnect: beforeConnect,
      onConnected: _handleConnected,
      onDisconnected: _handleDisconnected,
    );
  }

  /// AWS IoT data endpoint host, for example
  /// `xxxxxxxx-ats.iot.us-east-1.amazonaws.com`.
  final String endpoint;

  /// AWS region of the endpoint, for example `us-east-1`.
  final String region;

  /// MQTT client ID. Stays the same across reconnects of this instance.
  ///
  /// AWS IoT disconnects an existing connection when another one uses the
  /// same client ID, so the default is random per instance. If your IoT
  /// policy restricts client IDs, pass one that is unique per device or user
  /// session.
  late final String clientId;

  final Random _random;
  late final SubscriptionManager _subscriptions;
  late final ConnectionManager _connection;
  final _shadows = <String, AwsIotShadow>{};
  StreamSubscription<AwsIotMessage>? _messagesSub;
  bool _disposed = false;

  /// Current connection state.
  AwsIotConnectionState get state => _connection.state;

  /// Connection state changes.
  Stream<AwsIotConnectionState> get connectionState => _connection.states;

  /// Whether the client is connected right now.
  bool get isConnected => state == AwsIotConnectionState.connected;

  /// The most recent connection error, cleared after a successful connect.
  AwsIotException? get lastError => _connection.lastError;

  /// Connects to AWS IoT Core. Calls made while connecting share one attempt.
  ///
  /// Throws [AwsIotConnectException] if the attempt fails. Once connected,
  /// unexpected drops are retried according to the reconnect policy.
  Future<void> connect() {
    _checkNotDisposed();
    return _connection.connect();
  }

  /// Closes the connection and stops reconnecting. Subscriptions are kept
  /// and re-applied on the next [connect].
  Future<void> disconnect() => _connection.disconnect();

  /// Disconnects and releases all resources. The client cannot be reused.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final shadow in _shadows.values) {
      await shadow.dispose();
    }
    _shadows.clear();
    await _connection.close();
    await _subscriptions.close();
  }

  /// Messages on topics matching [topicFilter] (`+` and `#` allowed).
  ///
  /// The broker subscription is made when the first listener attaches and
  /// removed when the last one cancels, and it is restored after every
  /// reconnect. Subscribing before [connect] is fine. A refused subscription
  /// is delivered as an [AwsIotSubscribeException] error on the stream.
  Stream<AwsIotMessage> subscribe(
    String topicFilter, {
    AwsIotQos qos = AwsIotQos.atLeastOnce,
  }) {
    _checkNotDisposed();
    return _subscriptions.subscribe(topicFilter, qos);
  }

  /// Publishes [payload] to [topic].
  ///
  /// Throws [AwsIotNotConnectedException] when not connected.
  void publish(
    String topic,
    List<int> payload, {
    AwsIotQos qos = AwsIotQos.atLeastOnce,
    bool retain = false,
  }) {
    validatePublishTopic(topic);
    final transport = _connection.transport;
    if (transport == null || !isConnected) {
      throw const AwsIotNotConnectedException();
    }
    final bytes = payload is Uint8List ? payload : Uint8List.fromList(payload);
    transport.publish(topic, bytes, qos, retain);
  }

  /// Publishes [text] encoded as UTF-8.
  void publishString(
    String topic,
    String text, {
    AwsIotQos qos = AwsIotQos.atLeastOnce,
    bool retain = false,
  }) => publish(topic, utf8.encode(text), qos: qos, retain: retain);

  /// Publishes [value] encoded as JSON.
  void publishJson(
    String topic,
    Object? value, {
    AwsIotQos qos = AwsIotQos.atLeastOnce,
    bool retain = false,
  }) => publishString(topic, jsonEncode(value), qos: qos, retain: retain);

  /// The Device Shadow of [thingName]: the classic shadow, or the named
  /// shadow [shadowName]. Instances are cached per thing and shadow name.
  AwsIotShadow shadow(
    String thingName, {
    String? shadowName,
    Duration requestTimeout = const Duration(seconds: 10),
  }) {
    _checkNotDisposed();
    return _shadows.putIfAbsent(
      '$thingName\n${shadowName ?? ''}',
      () => AwsIotShadow(
        _subscriptions,
        publishJson,
        thingName,
        shadowName: shadowName,
        requestTimeout: requestTimeout,
        random: _random,
      ),
    );
  }

  void _handleConnected(MqttTransport transport) {
    _messagesSub = transport.messages.listen(_subscriptions.dispatch);
    _subscriptions.attachTransport(transport);
  }

  void _handleDisconnected() {
    unawaited(_messagesSub?.cancel());
    _messagesSub = null;
    _subscriptions.detachTransport();
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('AwsIotClient has been disposed');
  }

  static String _generateClientId(Random random) {
    final hex = List.generate(
      8,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'aws-iot-core-$hex';
  }
}
