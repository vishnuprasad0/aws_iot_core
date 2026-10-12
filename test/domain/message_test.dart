import 'dart:convert';

import 'package:aws_iot_core/aws_iot_core.dart';
import 'package:test/test.dart';

void main() {
  test('decodes the payload as text and JSON', () {
    final message = AwsIotMessage(
      topic: 'a/b',
      payload: utf8.encode('{"on":true}'),
      retained: true,
    );
    expect(message.payloadString, '{"on":true}');
    expect(message.json, {'on': true});
    expect(message.retained, isTrue);
    expect(message.toString(), 'AwsIotMessage(a/b, 11 bytes)');
  });

  test('json throws FormatException for non-JSON payloads', () {
    final message = AwsIotMessage(topic: 'a', payload: utf8.encode('hi'));
    expect(() => message.json, throwsFormatException);
  });

  test('credentials do not print the secret', () {
    const credentials = AwsIotCredentials(
      accessKeyId: 'AKID',
      secretAccessKey: 'top-secret',
      sessionToken: 'token',
    );
    expect(credentials.toString(), isNot(contains('top-secret')));
    expect(credentials.toString(), isNot(contains('token')));
  });
}
