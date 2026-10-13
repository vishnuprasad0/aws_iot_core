# Contributing

Thanks for helping improve `aws_iot_core`. Bug reports, fixes, new
features, tests and documentation are all welcome.

## Ways to contribute

- **Report a bug** with the bug report template. Include a minimal
  reproduction.
- **Suggest a feature** with the feature request template. The roadmap in the
  README lists ideas that are open to contributors.
- **Fix a bug or improve the code.** Small fixes can go straight to a pull
  request. For larger changes, open an issue first so we can agree on the
  approach before you spend time on it.

## Workflow

1. Fork the repository and create a branch from `main`.
2. Make your change, with tests that fail without it.
3. Run the checks below.
4. Open a pull request that describes the problem and the fix, and links the
   issue it closes.

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
dart test --platform chrome     # needs Chrome installed
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
