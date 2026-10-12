import 'dart:async';

import '../domain/backoff_policy.dart';
import '../domain/clock.dart';
import '../domain/connection_state.dart';
import '../domain/credentials.dart';
import '../domain/errors.dart';
import '../domain/transport.dart';
import '../domain/url_signer.dart';

/// Owns the single MQTT connection: connects, and reconnects after
/// unexpected drops with fresh credentials and a new signed URL each time.
///
/// Reconnecting is done here rather than by the MQTT library because a
/// library-level auto-reconnect reuses the URL signed for the first
/// connection, which stops working once the signature or the temporary
/// credentials expire.
class ConnectionManager {
  /// Creates a manager; nothing happens until [connect].
  ConnectionManager({
    required this.clientId,
    required AwsIotCredentialsProvider credentialsProvider,
    required UrlSigner signer,
    required MqttTransportFactory transportFactory,
    required Clock clock,
    required BackoffPolicy backoff,
    required this.keepAlive,
    required this.connectTimeout,
    BeforeConnectHook? beforeConnect,
    void Function(MqttTransport transport)? onConnected,
    void Function()? onDisconnected,
  }) : _credentialsProvider = credentialsProvider,
       _signer = signer,
       _transportFactory = transportFactory,
       _clock = clock,
       _backoff = backoff,
       _beforeConnect = beforeConnect,
       _onConnected = onConnected,
       _onDisconnected = onDisconnected;

  /// MQTT client ID used for every attempt.
  final String clientId;

  /// MQTT keep-alive interval.
  final Duration keepAlive;

  /// How long to wait for the broker to accept a connection.
  final Duration connectTimeout;

  final AwsIotCredentialsProvider _credentialsProvider;
  final UrlSigner _signer;
  final MqttTransportFactory _transportFactory;
  final Clock _clock;
  final BackoffPolicy _backoff;
  final BeforeConnectHook? _beforeConnect;
  final void Function(MqttTransport transport)? _onConnected;
  final void Function()? _onDisconnected;

  final _states = StreamController<AwsIotConnectionState>.broadcast(sync: true);
  AwsIotConnectionState _state = AwsIotConnectionState.disconnected;
  MqttTransport? _transport;
  Future<void>? _inFlight;
  Delay? _pendingDelay;
  bool _wantConnected = false;
  bool _closed = false;
  AwsIotException? _lastError;

  /// Current connection state.
  AwsIotConnectionState get state => _state;

  /// Connection state changes.
  Stream<AwsIotConnectionState> get states => _states.stream;

  /// The live transport, or null when not connected.
  MqttTransport? get transport => _transport;

  /// The most recent connection error, cleared on success.
  AwsIotException? get lastError => _lastError;

  /// Connects. Calls made while connecting share one attempt; a call made
  /// while reconnecting waits for the reconnect loop.
  Future<void> connect() async {
    if (_closed) throw StateError('ConnectionManager is closed');
    _wantConnected = true;
    switch (_state) {
      case AwsIotConnectionState.connected:
        return;
      case AwsIotConnectionState.reconnecting:
        return _waitForReconnect();
      case AwsIotConnectionState.connecting:
      case AwsIotConnectionState.disconnected:
        try {
          await _connectShared(reconnecting: false);
        } on AwsIotException {
          if (_state == AwsIotConnectionState.connecting) {
            _setState(AwsIotConnectionState.disconnected);
          }
          rethrow;
        }
    }
  }

  /// Closes the connection on request and stops any pending reconnect.
  Future<void> disconnect() async {
    _wantConnected = false;
    _pendingDelay?.cancel();
    final transport = _transport;
    _transport = null;
    if (transport != null) {
      _onDisconnected?.call();
      transport.disconnect();
    }
    _setState(AwsIotConnectionState.disconnected);
  }

  /// Disconnects and releases resources. The manager cannot be reused.
  Future<void> close() async {
    if (_closed) return;
    await disconnect();
    _closed = true;
    await _states.close();
  }

  Future<void> _connectShared({required bool reconnecting}) =>
      _inFlight ??= _connectOnce(
        reconnecting: reconnecting,
      ).whenComplete(() => _inFlight = null);

  Future<void> _connectOnce({required bool reconnecting}) async {
    if (!reconnecting) _setState(AwsIotConnectionState.connecting);
    MqttTransport? transport;
    try {
      final credentials = await _credentialsProvider.getCredentials();
      _abortIfUnwanted();
      await _beforeConnect?.call(credentials);
      _abortIfUnwanted();
      final created = transport = _transportFactory(
        TransportConfig(
          url: _signer.sign(credentials, _clock.now()),
          clientId: clientId,
          keepAlive: keepAlive,
          connectTimeout: connectTimeout,
        ),
      );
      created.onUnsolicitedDisconnect = () => _handleDrop(created);
      await created.connect();
      _abortIfUnwanted();
      _lastError = null;
      _transport = created;
      _setState(AwsIotConnectionState.connected);
      _onConnected?.call(created);
    } catch (e) {
      transport?.disconnect();
      final error = e is AwsIotException
          ? e
          : AwsIotConnectException('Connection attempt failed', cause: e);
      _lastError = error;
      throw error;
    }
  }

  void _abortIfUnwanted() {
    if (!_wantConnected || _closed) {
      throw const AwsIotConnectException('Cancelled by disconnect()');
    }
  }

  void _handleDrop(MqttTransport transport) {
    // Ignore callbacks from connections that have already been replaced.
    if (!identical(transport, _transport)) return;
    _transport = null;
    _onDisconnected?.call();
    if (!_wantConnected || _closed) {
      _setState(AwsIotConnectionState.disconnected);
      return;
    }
    _setState(AwsIotConnectionState.reconnecting);
    unawaited(_reconnectLoop());
  }

  Future<void> _reconnectLoop() async {
    var attempt = 0;
    while (_wantConnected && !_closed) {
      final wait = _backoff.delayFor(attempt);
      if (wait == null) {
        _setState(AwsIotConnectionState.disconnected);
        return;
      }
      final delay = _pendingDelay = _clock.delay(wait);
      await delay.done;
      _pendingDelay = null;
      if (!_wantConnected || _closed) return;
      attempt++;
      try {
        await _connectShared(reconnecting: true);
        return;
      } on AwsIotException {
        // Kept in lastError; the next attempt fetches fresh credentials.
      }
    }
  }

  Future<void> _waitForReconnect() async {
    final state = await states.firstWhere(
      (s) =>
          s == AwsIotConnectionState.connected ||
          s == AwsIotConnectionState.disconnected,
    );
    if (state == AwsIotConnectionState.disconnected) {
      throw _lastError ?? const AwsIotConnectException('Reconnect gave up');
    }
  }

  void _setState(AwsIotConnectionState state) {
    if (_state == state) return;
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }
}
