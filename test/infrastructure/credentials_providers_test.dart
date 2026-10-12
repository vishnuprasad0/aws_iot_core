import 'package:aws_iot_core/aws_iot_core.dart';
import 'package:test/test.dart';

void main() {
  const credentials = AwsIotCredentials(accessKeyId: 'a', secretAccessKey: 's');

  test('StaticCredentialsProvider returns the same credentials', () async {
    const provider = StaticCredentialsProvider(credentials);
    expect(await provider.getCredentials(), same(credentials));
    expect(await provider.getCredentials(), same(credentials));
  });

  test('CallbackCredentialsProvider calls back every time', () async {
    var calls = 0;
    final provider = CallbackCredentialsProvider(() async {
      calls++;
      return credentials;
    });
    await provider.getCredentials();
    await provider.getCredentials();
    expect(calls, 2);
  });
}
