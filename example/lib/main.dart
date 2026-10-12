import 'dart:async';

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_authenticator/amplify_authenticator.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:aws_iot_core/aws_iot_core.dart';
import 'package:flutter/material.dart';

import 'amplify_credentials.dart';
import 'config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Amplify.addPlugin(AmplifyAuthCognito());
  await Amplify.configure(amplifyConfig);
  runApp(const IotExampleApp());
}

/// Shows connection state, live messages and a Device Shadow.
class IotExampleApp extends StatelessWidget {
  const IotExampleApp({super.key});

  @override
  Widget build(BuildContext context) => Authenticator(
    child: MaterialApp(
      title: 'aws_iot_core example',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      builder: Authenticator.builder(),
      home: const IotHomePage(),
    ),
  );
}

/// The single screen of the example.
class IotHomePage extends StatefulWidget {
  const IotHomePage({super.key});

  @override
  State<IotHomePage> createState() => _IotHomePageState();
}

class _IotHomePageState extends State<IotHomePage> {
  late final AwsIotClient _client;
  late final AwsIotShadow _shadow;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _messages = <String>[];

  AwsIotConnectionState _state = AwsIotConnectionState.disconnected;
  ShadowDocument? _document;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = AwsIotClient(
      endpoint: iotEndpoint,
      region: iotRegion,
      credentialsProvider: AmplifyIotCredentialsProvider(),
      // If authenticated identities need an IoT policy attached, call your
      // backend here; it runs before every connection attempt.
      beforeConnect: (_) async {},
    );
    _shadow = _client.shadow(thingName);

    _subscriptions
      ..add(
        _client.connectionState.listen(
          (state) => setState(() => _state = state),
        ),
      )
      // Subscribing before connecting is fine; it is applied on connect and
      // restored after every reconnect.
      ..add(
        _client
            .subscribe(telemetryTopic)
            .listen(
              (message) => setState(
                () => _messages.insert(
                  0,
                  '${message.topic}: ${message.payloadString}',
                ),
              ),
              onError: _showError,
            ),
      )
      ..add(
        _shadow.delta.listen(
          (delta) => setState(
            () => _messages.insert(0, 'shadow delta: ${delta.state}'),
          ),
          onError: _showError,
        ),
      );
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _client.dispose();
    super.dispose();
  }

  void _showError(Object error) => setState(() => _error = '$error');

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _error = null);
    try {
      await action();
    } on AwsIotShadowRejectedException catch (e) {
      _showError(e.code == 404 ? 'No shadow yet for $thingName' : e);
    } on AwsIotException catch (e) {
      _showError(e);
    }
  }

  Future<void> _readShadow() => _run(() async {
    final document = await _shadow.get();
    setState(() => _document = document);
  });

  Future<void> _toggleLed() => _run(() async {
    final ledOn = _document?.desired?['led'] == 'on';
    final document = await _shadow.update(
      desired: {'led': ledOn ? 'off' : 'on'},
    );
    setState(() => _document = document);
  });

  @override
  Widget build(BuildContext context) {
    final connected = _state == AwsIotConnectionState.connected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AWS IoT Core'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: Amplify.Auth.signOut,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(connected ? Icons.cloud_done : Icons.cloud_off),
              title: Text('Connection: ${_state.name}'),
              subtitle: Text('Client ID: ${_client.clientId}'),
              trailing: connected
                  ? TextButton(
                      onPressed: _client.disconnect,
                      child: const Text('Disconnect'),
                    )
                  : FilledButton(
                      onPressed: () => _run(_client.connect),
                      child: const Text('Connect'),
                    ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Shadow of $thingName',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('Version: ${_document?.version ?? '-'}'),
                  Text('Desired: ${_document?.desired ?? '-'}'),
                  Text('Reported: ${_document?.reported ?? '-'}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: connected ? _readShadow : null,
                        child: const Text('Read'),
                      ),
                      FilledButton(
                        onPressed: connected ? _toggleLed : null,
                        child: const Text('Toggle LED'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(title: Text(_error!)),
            ),
          Text(
            'Messages on $telemetryTopic',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final message in _messages) ListTile(title: Text(message)),
        ],
      ),
    );
  }
}
