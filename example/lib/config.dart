// Real values come from `--dart-define-from-file=aws.local.json`; see README.

/// AWS IoT data endpoint. Find it with:
/// `aws iot describe-endpoint --endpoint-type iot:Data-ATS`
const iotEndpoint = String.fromEnvironment(
  'IOT_ENDPOINT',
  defaultValue: 'xxxxxxxx-ats.iot.us-east-1.amazonaws.com',
);

/// Region of the endpoint and the Cognito pools.
const iotRegion = String.fromEnvironment(
  'IOT_REGION',
  defaultValue: 'us-east-1',
);

/// A thing whose Device Shadow the example reads and updates.
const thingName = String.fromEnvironment('IOT_THING', defaultValue: 'my-thing');

/// Topic filter the example listens to.
const telemetryTopic = String.fromEnvironment(
  'IOT_TOPIC',
  defaultValue: 'devices/+/telemetry',
);

/// Amplify configuration for your Cognito user pool and identity pool.
const amplifyConfig = String.fromEnvironment(
  'AMPLIFY_CONFIG',
  defaultValue: '''
{
  "UserAgent": "aws-amplify-cli/2.0",
  "Version": "1.0",
  "auth": {
    "plugins": {
      "awsCognitoAuthPlugin": {
        "CredentialsProvider": {
          "CognitoIdentity": {
            "Default": {
              "PoolId": "us-east-1:00000000-0000-0000-0000-000000000000",
              "Region": "us-east-1"
            }
          }
        },
        "CognitoUserPool": {
          "Default": {
            "PoolId": "us-east-1_XXXXXXXXX",
            "AppClientId": "xxxxxxxxxxxxxxxxxxxxxxxxxx",
            "Region": "us-east-1"
          }
        },
        "Auth": {
          "Default": {
            "authenticationFlowType": "USER_SRP_AUTH",
            "socialProviders": [],
            "usernameAttributes": ["EMAIL"],
            "signupAttributes": ["EMAIL"],
            "passwordProtectionSettings": {
              "passwordPolicyMinLength": 8,
              "passwordPolicyCharacters": []
            },
            "mfaConfiguration": "OFF",
            "mfaTypes": ["SMS"],
            "verificationMechanisms": ["EMAIL"]
          }
        }
      }
    }
  }
}
''',
);
