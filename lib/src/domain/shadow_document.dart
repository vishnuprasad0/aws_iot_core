/// A Device Shadow document, as returned by shadow get and update requests.
class ShadowDocument {
  /// Wraps a decoded JSON shadow document.
  ShadowDocument(this.raw);

  /// The JSON document as received.
  final Map<String, dynamic> raw;

  /// The `state` section.
  Map<String, dynamic>? get state => mapOrNull(raw['state']);

  /// The desired state.
  Map<String, dynamic>? get desired => mapOrNull(state?['desired']);

  /// The reported state.
  Map<String, dynamic>? get reported => mapOrNull(state?['reported']);

  /// Present in get responses when desired and reported differ.
  Map<String, dynamic>? get delta => mapOrNull(state?['delta']);

  /// Per-field timestamps.
  Map<String, dynamic>? get metadata => mapOrNull(raw['metadata']);

  /// The shadow version, used for optimistic locking.
  int? get version => intOrNull(raw['version']);

  /// When AWS produced this document.
  DateTime? get timestamp => timestampOrNull(raw['timestamp']);

  @override
  String toString() => 'ShadowDocument(version: $version, state: $state)';
}

/// A message from a shadow's `update/delta` topic: desired values that
/// differ from reported ones.
class ShadowDelta {
  /// Wraps a decoded delta message.
  ShadowDelta(this.raw);

  /// The JSON message as received.
  final Map<String, dynamic> raw;

  /// Desired values that differ from reported.
  Map<String, dynamic> get state => mapOrNull(raw['state']) ?? const {};

  /// Per-field timestamps.
  Map<String, dynamic>? get metadata => mapOrNull(raw['metadata']);

  /// The shadow version after the update.
  int? get version => intOrNull(raw['version']);

  /// When AWS produced this message.
  DateTime? get timestamp => timestampOrNull(raw['timestamp']);

  @override
  String toString() => 'ShadowDelta(version: $version, state: $state)';
}

/// A message from a shadow's `update/documents` topic: the full document
/// before and after an accepted update.
class ShadowDocumentsEvent {
  /// Wraps a decoded documents message.
  ShadowDocumentsEvent(this.raw);

  /// The JSON message as received.
  final Map<String, dynamic> raw;

  /// The document before the update.
  ShadowDocument? get previous => _document(raw['previous']);

  /// The document after the update.
  ShadowDocument? get current => _document(raw['current']);

  /// When AWS produced this message.
  DateTime? get timestamp => timestampOrNull(raw['timestamp']);

  static ShadowDocument? _document(Object? value) {
    final map = mapOrNull(value);
    return map == null ? null : ShadowDocument(map);
  }

  @override
  String toString() =>
      'ShadowDocumentsEvent(${previous?.version} -> ${current?.version})';
}

/// Returns [value] as a JSON object, or throws [FormatException].
Map<String, dynamic> asJsonObject(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  throw const FormatException('Expected a JSON object');
}

/// Returns [value] as a JSON object, or null.
Map<String, dynamic>? mapOrNull(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

/// Returns [value] as an int, or null.
int? intOrNull(Object? value) => value is num ? value.toInt() : null;

/// Converts an AWS epoch-seconds timestamp to UTC, or null.
DateTime? timestampOrNull(Object? seconds) => seconds is num
    ? DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round(), isUtc: true)
    : null;
