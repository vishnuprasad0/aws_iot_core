## 0.1.0

- Initial release.
- `AwsIotClient`: MQTT 3.1.1 over SigV4-signed WebSockets. Credentials are
  fetched and the URL re-signed on every connect and reconnect. Includes
  exponential backoff with jitter, one shared connection per client, and a
  `beforeConnect` hook.
- Wildcard (`+`, `#`) subscriptions with reference-counted broker
  subscriptions, restored after reconnects.
- Device Shadow: `get`, `update`, `delete`, plus `delta` and `documents`
  streams, for classic and named shadows.
- Sealed `AwsIotException` error hierarchy.
- `AwsIotUrlSigner` for building signed AWS IoT WebSocket URLs.
