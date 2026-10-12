import 'package:aws_iot_core/aws_iot_core.dart';
import 'package:test/test.dart';

void main() {
  test('every error is an AwsIotException with a readable message', () {
    final errors = <AwsIotException>[
      const AwsIotNotConnectedException(),
      const AwsIotConnectException('refused', cause: 'socket closed'),
      const AwsIotConnectException('refused'),
      const AwsIotSubscribeException('a/b'),
      const AwsIotTimeoutException('slow'),
      const AwsIotShadowRejectedException(code: 404, message: 'missing'),
    ];

    final descriptions = [
      for (final error in errors)
        switch (error) {
          AwsIotNotConnectedException() => 'not connected',
          AwsIotConnectException(:final cause) => 'connect $cause',
          AwsIotSubscribeException(:final topicFilter) => 'sub $topicFilter',
          AwsIotTimeoutException() => 'timeout',
          AwsIotShadowRejectedException(:final code) => 'rejected $code',
        },
    ];

    expect(descriptions, [
      'not connected',
      'connect socket closed',
      'connect null',
      'sub a/b',
      'timeout',
      'rejected 404',
    ]);
    expect(errors[0].toString(), contains('Not connected'));
    expect(errors[1].toString(), contains('cause: socket closed'));
    expect(errors[2].toString(), 'AwsIotConnectException: refused');
    expect(errors[3].message, contains('iot:Subscribe'));
    expect(errors[5].toString(), 'AwsIotShadowRejectedException(404): missing');
  });
}
