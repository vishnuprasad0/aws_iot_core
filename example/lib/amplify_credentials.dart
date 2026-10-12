import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:aws_iot_core/aws_iot_core.dart';

/// Supplies Cognito identity pool credentials from Amplify.
///
/// `AwsIotClient` calls this before every connect and reconnect.
/// `fetchAuthSession` refreshes expired credentials, so each reconnect is
/// signed with valid ones.
class AmplifyIotCredentialsProvider implements AwsIotCredentialsProvider {
  @override
  Future<AwsIotCredentials> getCredentials() async {
    final session = await Amplify.Auth.fetchAuthSession() as CognitoAuthSession;
    final credentials = session.credentialsResult.value;
    return AwsIotCredentials(
      accessKeyId: credentials.accessKeyId,
      secretAccessKey: credentials.secretAccessKey,
      sessionToken: credentials.sessionToken,
      expiration: credentials.expiration,
    );
  }
}
