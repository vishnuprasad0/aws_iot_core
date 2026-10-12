# aws_iot_core

[![pub package](https://img.shields.io/pub/v/aws_iot_core.svg)](https://pub.dev/packages/aws_iot_core)
[![CI](https://github.com/vishnuprasad0/aws_iot_core/actions/workflows/ci.yaml/badge.svg)](https://github.com/vishnuprasad0/aws_iot_core/actions/workflows/ci.yaml)
[![coverage](https://img.shields.io/badge/coverage-99%25-brightgreen.svg)](#testing)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

AWS IoT Core client for Dart and Flutter: MQTT over SigV4-signed WebSockets,
Cognito-friendly credentials, re-signing on every reconnect, wildcard
subscriptions and Device Shadow support. Built on
[`mqtt_client`](https://pub.dev/packages/mqtt_client).

## Why

Amplify Flutter has no PubSub category, so there is no official way to talk
to AWS IoT Core from Flutter
([aws-amplify/amplify-flutter#1006](https://github.com/aws-amplify/amplify-flutter/issues/1006),
open since 2021). Apps end up hand-writing the same pieces:

- **Signing.** SigV4 query signing for the WebSocket URL, with the session
  token appended after the signature.
- **Reconnecting.** `mqtt_client`'s auto-reconnect reuses the URL signed for
  the first connection. Once temporary Cognito credentials expire, every
  reconnect fails.
- **Subscriptions.** Re-subscribing after each reconnect and routing messages
  to listeners by topic filter.
- **Device Shadow.** Topic layouts, `clientToken` correlation, and
  `/accepted` versus `/rejected` handling.
- **Client IDs.** AWS IoT drops an existing connection when another one uses
  the same client ID.

`aws_iot_core` does these once, with tests.

## Features

- MQTT 3.1.1 over `wss://` on port 443 with SigV4-signed URLs.
- Credentials fetched, and the URL re-signed, on **every** connect and
  reconnect.
- Reconnects with exponential backoff and jitter; configurable or disabled.
- One shared connection per client; concurrent `connect()` calls share one
  attempt.
- `subscribe()` with `+` and `#` wildcards. Broker subscriptions are
  reference-counted and restored after reconnects.
- Device Shadow: `get`, `update`, `delete`, plus `delta` and `documents`
  streams, for classic and named shadows.
- A `beforeConnect` hook, for example to attach an IoT policy to a Cognito
  identity.
- Typed, sealed error hierarchy (`AwsIotException`).
- No Amplify dependency: plug in any credentials source.

## Install

```sh
dart pub add aws_iot_core
```

## Quick start

```dart
import 'package:aws_iot_core/aws_iot_core.dart';

final client = AwsIotClient(
  // aws iot describe-endpoint --endpoint-type iot:Data-ATS
  endpoint: 'xxxxxxxx-ats.iot.us-east-1.amazonaws.com',
  region: 'us-east-1',
  credentialsProvider: myCredentialsProvider, // see below
);

client.subscribe('devices/+/telemetry').listen((message) {
  print('${message.topic}: ${message.json}');
});

await client.connect();
client.publishJson('devices/lamp-1/commands', {'power': 'on'});
```

### Credentials from Amplify (Cognito)

The provider is called before every connect and reconnect.
`fetchAuthSession` refreshes expired credentials, so reconnects keep working.

```dart
class AmplifyIotCredentialsProvider implements AwsIotCredentialsProvider {
  @override
  Future<AwsIotCredentials> getCredentials() async {
    final session = await Amplify.Auth.fetchAuthSession() as CognitoAuthSession;
    final c = session.credentialsResult.value;
    return AwsIotCredentials(
      accessKeyId: c.accessKeyId,
      secretAccessKey: c.secretAccessKey,
      sessionToken: c.sessionToken,
      expiration: c.expiration,
    );
  }
}
```

Other sources work the same way: implement `AwsIotCredentialsProvider`, or
use `CallbackCredentialsProvider` or `StaticCredentialsProvider`.

## AWS setup

1. **IoT endpoint.** Run
   `aws iot describe-endpoint --endpoint-type iot:Data-ATS`.
2. **Cognito identity pool.** Its IAM role, for authenticated and/or guest
   identities, needs `iot:Connect`, `iot:Subscribe`, `iot:Receive` and
   `iot:Publish` on the client IDs and topics you use.
3. **Attach an IoT policy for authenticated identities.** Authenticated
   Cognito identities also need an AWS IoT policy attached to their identity
   ID (`iot:AttachPolicy`). This is usually done by a backend endpoint or a
   Lambda. If your app triggers it, call it from `beforeConnect`:

   ```dart
   AwsIotClient(
     endpoint: endpoint,
     region: region,
     credentialsProvider: AmplifyIotCredentialsProvider(),
     beforeConnect: (credentials) => myBackend.attachIotPolicyOnce(),
   );
   ```

   `beforeConnect` runs before every attempt, so make it cheap or have it
   remember that it already succeeded.

Example IoT policy (replace `REGION` and `ACCOUNT_ID`, and narrow the
resources for production):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": "iot:Connect",
      "Resource": "arn:aws:iot:REGION:ACCOUNT_ID:client/*" },
    { "Effect": "Allow", "Action": ["iot:Publish", "iot:Receive"],
      "Resource": "arn:aws:iot:REGION:ACCOUNT_ID:topic/*" },
    { "Effect": "Allow", "Action": "iot:Subscribe",
      "Resource": "arn:aws:iot:REGION:ACCOUNT_ID:topicfilter/*" }
  ]
}
```

**Client IDs.** The default client ID is random per `AwsIotClient` instance
and stays the same across its reconnects. If your policy limits client IDs
(for example to the Cognito identity ID), pass `clientId`, and keep only one
live connection per ID.

## Device Shadow

```dart
final shadow = client.shadow('lamp-1');                        // classic
final config = client.shadow('lamp-1', shadowName: 'config');  // named

try {
  final doc = await shadow.get();
  print('v${doc.version}: reported ${doc.reported}');
} on AwsIotShadowRejectedException catch (e) {
  if (e.code == 404) print('No shadow yet');
}

await shadow.update(desired: {'brightness': 80}, version: 7); // 409 on conflict
shadow.delta.listen((d) => print('to apply: ${d.state}'));
shadow.documents.listen((e) => print('${e.previous?.version} -> ${e.current?.version}'));
```

The client subscribes to an operation's `/accepted` and `/rejected` topics
before its first request. Requests time out after `requestTimeout` (10 seconds
by default) with an `AwsIotTimeoutException`.

## Reconnect behaviour

- An **unexpected** disconnect (network loss, broker close, missed ping)
  starts the reconnect loop. A `disconnect()` you call does not.
- Each attempt waits for the backoff delay, then fetches credentials, runs
  `beforeConnect`, signs a new URL and connects.
- Subscriptions are restored on the new connection. Callbacks from replaced
  connections are ignored.
- `connectionState` reports `connecting`, `connected`, `reconnecting` and
  `disconnected`, and `lastError` holds the most recent failure.

```dart
AwsIotClient(
  // ...
  reconnectPolicy: const ExponentialBackoff(
    initialDelay: Duration(seconds: 1),
    maxDelay: Duration(seconds: 60),
    maxAttempts: null, // retry forever
  ),
  // or: reconnectPolicy: const NoReconnect(),
);
```

## Error handling

Every error is a subclass of the sealed `AwsIotException`:
`AwsIotConnectException`, `AwsIotNotConnectedException`,
`AwsIotSubscribeException`, `AwsIotTimeoutException` and
`AwsIotShadowRejectedException`.

## Architecture

```
lib/aws_iot_core.dart        public API (exports only)
lib/src/domain/              entities, value objects, errors, interfaces
lib/src/application/         connection manager, subscriptions, shadow, topics
lib/src/infrastructure/      SigV4 signer, system clock, mqtt_client transports
lib/src/aws_iot_client.dart  facade wiring the layers together
```

Dependencies point inward. `AwsIotClient` accepts a `transportFactory`,
`clock` and `random` for tests, or to plug in a different MQTT library through
`MqttTransport`.

## Testing

```sh
dart test                                   # unit tests, no network
dart test --coverage=coverage
dart run coverage:format_coverage --lcov --in=coverage \
  --out=coverage/lcov.info --report-on=lib
```

The integration tests talk to a real AWS IoT endpoint and are skipped unless
these are set:

```sh
export AWS_IOT_ENDPOINT=xxxxxxxx-ats.iot.us-east-1.amazonaws.com
export AWS_REGION=us-east-1
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_SESSION_TOKEN=...
export AWS_IOT_THING=my-thing   # optional, for the shadow test
dart test --tags integration
```

## Example

[`example/`](example) is a minimal Flutter app with an Amplify Cognito
credentials adapter: it connects, shows the connection state, listens to a
topic, and reads and updates a shadow.

## Platform support

Android, iOS, macOS, Windows, Linux and the Dart VM use `MqttServerClient`
over WebSockets. The web uses `MqttBrowserClient`; it compiles, but has not
been tested against AWS IoT yet.

## Limitations and roadmap

- Web support needs testing against AWS IoT.
- Persistent sessions (`cleanSession: false`) and an offline publish queue.
- MQTT 5 (via `mqtt5_client`).
- X.509 (mutual TLS) and custom authorizer authentication.
- Raising the QoS of an existing filter takes effect on the next reconnect.
