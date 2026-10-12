import 'package:aws_iot_core/aws_iot_core.dart';
import 'package:aws_iot_core/src/domain/shadow_document.dart' show asJsonObject;
import 'package:test/test.dart';

void main() {
  test('ShadowDocument exposes state sections, version and timestamp', () {
    final doc = ShadowDocument({
      'state': {
        'desired': {'on': true},
        'reported': {'on': false},
        'delta': {'on': true},
      },
      'metadata': {'desired': <String, dynamic>{}},
      'version': 3,
      'timestamp': 1767323045,
    });
    expect(doc.desired, {'on': true});
    expect(doc.reported, {'on': false});
    expect(doc.delta, {'on': true});
    expect(doc.metadata, {'desired': <String, dynamic>{}});
    expect(doc.version, 3);
    expect(doc.timestamp, DateTime.utc(2026, 1, 2, 3, 4, 5));
    expect(doc.toString(), contains('version: 3'));
  });

  test('missing or malformed sections are null', () {
    final doc = ShadowDocument({'state': 'oops', 'version': 'x'});
    expect(doc.state, isNull);
    expect(doc.desired, isNull);
    expect(doc.version, isNull);
    expect(doc.timestamp, isNull);
  });

  test('ShadowDelta defaults state to an empty map', () {
    final delta = ShadowDelta({'version': 4, 'metadata': <String, dynamic>{}});
    expect(delta.state, isEmpty);
    expect(delta.version, 4);
    expect(delta.metadata, isEmpty);
    expect(delta.timestamp, isNull);
    expect(delta.toString(), contains('version: 4'));
  });

  test('ShadowDocumentsEvent wraps previous and current', () {
    final event = ShadowDocumentsEvent({
      'previous': {'version': 1},
      'current': {'version': 2},
      'timestamp': 0,
    });
    expect(event.previous!.version, 1);
    expect(event.current!.version, 2);
    expect(event.timestamp, DateTime.utc(1970));
    expect(event.toString(), contains('1 -> 2'));
    expect(ShadowDocumentsEvent({}).current, isNull);
  });

  test('asJsonObject rejects non-objects', () {
    expect(asJsonObject({'a': 1}), {'a': 1});
    expect(() => asJsonObject([1]), throwsFormatException);
  });
}
