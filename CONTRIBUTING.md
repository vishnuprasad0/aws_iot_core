# Contributing

Thanks for helping improve `aws_iot_core`.

## Setup

```sh
dart pub get
```

## Before opening a pull request

Run the same checks as CI:

```sh
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test --coverage=coverage
dart run coverage:format_coverage --lcov --in=coverage \
  --out=coverage/lcov.info --report-on=lib
dart doc
```

For changes to the example app:

```sh
cd example
flutter pub get
flutter analyze
```

## Guidelines

- Keep the layers separate. `domain/` has no package imports beyond the Dart
  SDK, `application/` depends only on `domain/`, and adapters live in
  `infrastructure/`. `AwsIotClient` wires them together.
- Unit tests must not touch the network. Use the fakes in
  `test/support/fakes.dart`; tests mirror the layout of `lib/src`.
- Every public member needs a doc comment.
- Add a `CHANGELOG.md` entry for user-visible changes.
- Never commit real endpoints, account IDs or credentials. Use placeholders
  such as `xxxxxxxx-ats.iot.us-east-1.amazonaws.com`.

## Integration tests

`test/integration/` runs against a real AWS IoT endpoint and is skipped
unless the environment variables listed in the README are set. Run it with
`dart test --tags integration`.

## Reporting bugs

Open an issue with the package version, platform, a minimal reproduction, and
the `lastError` or exception you see. Remove credentials and endpoint IDs
first.
