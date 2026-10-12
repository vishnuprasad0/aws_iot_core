import 'package:aws_iot_core/src/application/topic_matcher.dart';
import 'package:test/test.dart';

void main() {
  group('topicMatches', () {
    const cases = <(String, String, bool)>[
      ('a/b/c', 'a/b/c', true),
      ('a/b/c', 'a/b/d', false),
      ('a/+/c', 'a/b/c', true),
      ('a/+/c', 'a/b/x/c', false),
      ('a/+', 'a', false),
      ('a/+', 'a/', true),
      ('+/+', 'a/b', true),
      ('+', '', true),
      ('a/#', 'a', true),
      ('a/#', 'a/b/c', true),
      ('a/#', 'b/c', false),
      ('#', 'a/b', true),
      ('a/b', 'a/b/c', false),
      ('a/b/c', 'a/b', false),
      ('A/b', 'a/b', false),
      (
        r'$aws/things/t1/shadow/get/+',
        r'$aws/things/t1/shadow/get/accepted',
        true,
      ),
      (
        r'$aws/things/+/shadow/update/delta',
        r'$aws/things/t1/shadow/update/delta',
        true,
      ),
      ('#', r'$aws/things/t1', false),
      ('+/things/t1', r'$aws/things/t1', false),
    ];
    for (final (filter, topic, expected) in cases) {
      test('"$filter" vs "$topic" -> $expected', () {
        expect(topicMatches(filter, topic), expected);
      });
    }
  });

  group('validateTopicFilter', () {
    test('accepts valid filters', () {
      for (final filter in [
        'a',
        'a/b',
        'a/+/c',
        'a/#',
        '#',
        '+',
        r'$aws/things/+/shadow/#',
      ]) {
        expect(
          () => validateTopicFilter(filter),
          returnsNormally,
          reason: filter,
        );
      }
    });

    test('rejects invalid filters', () {
      for (final filter in ['', 'a/#/b', 'a#', 'a/b+', 'a/+b/c']) {
        expect(
          () => validateTopicFilter(filter),
          throwsArgumentError,
          reason: filter,
        );
      }
    });
  });

  test('validatePublishTopic rejects wildcards and empty topics', () {
    expect(() => validatePublishTopic('a/+'), throwsArgumentError);
    expect(() => validatePublishTopic('a/#'), throwsArgumentError);
    expect(() => validatePublishTopic(''), throwsArgumentError);
    expect(() => validatePublishTopic('a/b'), returnsNormally);
  });
}
