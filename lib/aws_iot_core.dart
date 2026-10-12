/// AWS IoT Core client for Dart and Flutter: MQTT over SigV4-signed
/// WebSockets, re-signing on every reconnect, wildcard subscriptions and
/// Device Shadow support.
library;

export 'src/application/exponential_backoff.dart'
    show ExponentialBackoff, NoReconnect;
export 'src/application/shadow_client.dart' show AwsIotShadow;
export 'src/application/topic_matcher.dart' show topicMatches;
export 'src/aws_iot_client.dart' show AwsIotClient;
export 'src/domain/backoff_policy.dart' show BackoffPolicy;
export 'src/domain/clock.dart' show Clock, Delay;
export 'src/domain/connection_state.dart' show AwsIotConnectionState;
export 'src/domain/credentials.dart'
    show AwsIotCredentials, AwsIotCredentialsProvider, BeforeConnectHook;
export 'src/domain/errors.dart'
    show
        AwsIotConnectException,
        AwsIotException,
        AwsIotNotConnectedException,
        AwsIotShadowRejectedException,
        AwsIotSubscribeException,
        AwsIotTimeoutException;
export 'src/domain/message.dart' show AwsIotMessage, AwsIotQos;
export 'src/domain/shadow_document.dart'
    show ShadowDelta, ShadowDocument, ShadowDocumentsEvent;
export 'src/domain/transport.dart'
    show MqttTransport, MqttTransportFactory, TransportConfig;
export 'src/domain/url_signer.dart' show UrlSigner;
export 'src/infrastructure/aws_iot_url_signer.dart' show AwsIotUrlSigner;
export 'src/infrastructure/credentials_providers.dart'
    show CallbackCredentialsProvider, StaticCredentialsProvider;
export 'src/infrastructure/system_clock.dart' show SystemClock;
