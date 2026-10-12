# aws_iot_core example

A minimal Flutter app (Android and iOS) that signs in with Amplify Cognito,
connects to AWS IoT Core, shows the connection state, listens to a topic, and
reads and updates a Device Shadow.

## Run it

1. Copy `aws.example.json` to `aws.local.json` and fill in your IoT endpoint,
   region, thing name, topic filter, and the Amplify configuration for your
   Cognito user pool and identity pool (as one JSON string).
   `aws.local.json` is git-ignored, so your values stay on your machine.
2. Make sure the identity pool's authenticated role and the IoT policy allow
   the topics used (see the package README, "AWS setup").
3. Run:

   ```sh
   flutter run --dart-define-from-file=aws.local.json
   ```

4. Create an account or sign in on the Amplify sign-in screen, then tap
   **Connect**.

Without `--dart-define-from-file` the app starts with placeholder values and
cannot connect.

The Amplify credentials adapter lives in `lib/amplify_credentials.dart`; the
package itself has no Amplify dependency.
