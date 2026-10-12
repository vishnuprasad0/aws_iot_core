import 'package:aws_common/aws_common.dart';
import 'package:aws_iot_core/aws_iot_core.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';
import 'package:test/test.dart';

void main() {
  const endpoint = 'XXXXXXXX-ats.iot.us-east-1.amazonaws.com';
  const region = 'us-east-1';
  final now = DateTime.utc(2026, 1, 2, 3, 4, 5);
  const credentials = AwsIotCredentials(
    accessKeyId: 'AKIDEXAMPLE',
    secretAccessKey: 'test/secret+key-not-real',
    sessionToken: 'session/token+with=special',
  );
  const signer = AwsIotUrlSigner(endpoint: endpoint, region: region);

  test('builds a wss URL with the SigV4 query parameters', () {
    final url = signer.sign(credentials, now);
    expect(url.scheme, 'wss');
    expect(url.host, endpoint.toLowerCase());
    expect(url.path, '/mqtt');
    final q = url.queryParameters;
    expect(q['X-Amz-Algorithm'], 'AWS4-HMAC-SHA256');
    expect(
      q['X-Amz-Credential'],
      'AKIDEXAMPLE/20260102/us-east-1/iotdevicegateway/aws4_request',
    );
    expect(q['X-Amz-Date'], '20260102T030405Z');
    expect(q['X-Amz-SignedHeaders'], 'host');
    expect(q['X-Amz-Signature'], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(q.containsKey('X-Amz-Expires'), isFalse);
  });

  test('converts local times to UTC', () {
    final local = now.toLocal();
    expect(
      signer.sign(credentials, local).queryParameters['X-Amz-Date'],
      '20260102T030405Z',
    );
  });

  test('appends the encoded session token after the signature', () {
    final query = signer.sign(credentials, now).query;
    expect(
      query,
      endsWith('&X-Amz-Security-Token=session%2Ftoken%2Bwith%3Dspecial'),
    );
    expect(
      query.indexOf('X-Amz-Signature='),
      lessThan(query.indexOf('X-Amz-Security-Token=')),
    );
  });

  test('the session token is not part of the signature', () {
    final withToken = signer
        .sign(credentials, now)
        .queryParameters['X-Amz-Signature'];
    for (final token in [null, '']) {
      final url = signer.sign(
        AwsIotCredentials(
          accessKeyId: credentials.accessKeyId,
          secretAccessKey: credentials.secretAccessKey,
          sessionToken: token,
        ),
        now,
      );
      expect(url.queryParameters['X-Amz-Signature'], withToken);
      expect(url.queryParameters.containsKey('X-Amz-Security-Token'), isFalse);
    }
  });

  test('the signature depends on the secret and the time', () {
    final base = signer
        .sign(credentials, now)
        .queryParameters['X-Amz-Signature'];
    final otherSecret = signer
        .sign(
          const AwsIotCredentials(
            accessKeyId: 'AKIDEXAMPLE',
            secretAccessKey: 'other',
          ),
          now,
        )
        .queryParameters['X-Amz-Signature'];
    final later = signer
        .sign(credentials, now.add(const Duration(seconds: 1)))
        .queryParameters['X-Amz-Signature'];
    expect(otherSecret, isNot(base));
    expect(later, isNot(base));
  });

  test('matches package:aws_signature_v4 for the same request', () async {
    final reference =
        await AWSSigV4Signer(
          credentialsProvider: AWSCredentialsProvider(
            AWSCredentials(
              credentials.accessKeyId,
              credentials.secretAccessKey,
              credentials.sessionToken,
            ),
          ),
        ).presign(
          AWSHttpRequest.get(
            Uri.parse('https://${endpoint.toLowerCase()}/mqtt'),
          ),
          credentialScope: AWSCredentialScope.raw(
            region: region,
            service: 'iotdevicegateway',
            dateTime: AWSDateTime(now),
          ),
          serviceConfiguration: const BaseServiceConfiguration(
            omitSessionToken: true,
          ),
          expiresIn: const Duration(seconds: 300),
        );

    const withExpiry = AwsIotUrlSigner(
      endpoint: endpoint,
      region: region,
      expires: Duration(seconds: 300),
    );
    final ours = withExpiry.sign(credentials, now);
    expect(ours.host, reference.host);
    expect(ours.path, reference.path);
    expect(ours.queryParameters, reference.queryParameters);
  });

  test('uriEncode keeps only unreserved characters', () {
    expect(
      AwsIotUrlSigner.uriEncode('a b/c~d-e_f.g+h=é'),
      'a%20b%2Fc~d-e_f.g%2Bh%3D%C3%A9',
    );
  });

  test('canonicalQueryString sorts keys', () {
    expect(
      AwsIotUrlSigner.canonicalQueryString({'b': '2', 'a': '1 1'}),
      'a=1%201&b=2',
    );
  });
}
