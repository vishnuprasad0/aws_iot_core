/// Whether [topic] matches the MQTT topic [filter].
///
/// Follows MQTT 3.1.1: `#` matches the parent level and everything below it,
/// `+` matches exactly one level, and filters starting with a wildcard do not
/// match topics starting with `$` (such as `$aws/...`).
bool topicMatches(String filter, String topic) {
  if (filter == topic) return true;
  final filterLevels = filter.split('/');
  final topicLevels = topic.split('/');
  if (topic.startsWith(r'$') &&
      (filterLevels.first == '+' || filterLevels.first == '#')) {
    return false;
  }
  for (var i = 0; i < filterLevels.length; i++) {
    final level = filterLevels[i];
    if (level == '#') return true;
    if (i >= topicLevels.length) return false;
    if (level != '+' && level != topicLevels[i]) return false;
  }
  return filterLevels.length == topicLevels.length;
}

/// Throws [ArgumentError] when [filter] is not a valid MQTT topic filter.
void validateTopicFilter(String filter) {
  if (filter.isEmpty) {
    throw ArgumentError.value(filter, 'filter', 'must not be empty');
  }
  final levels = filter.split('/');
  for (var i = 0; i < levels.length; i++) {
    final level = levels[i];
    if (level.contains('#') && (level != '#' || i != levels.length - 1)) {
      throw ArgumentError.value(
        filter,
        'filter',
        '"#" must be the whole last level',
      );
    }
    if (level.contains('+') && level != '+') {
      throw ArgumentError.value(
        filter,
        'filter',
        '"+" must occupy a whole level',
      );
    }
  }
}

/// Throws [ArgumentError] when [topic] is not a valid topic to publish to.
void validatePublishTopic(String topic) {
  if (topic.isEmpty) {
    throw ArgumentError.value(topic, 'topic', 'must not be empty');
  }
  if (topic.contains('+') || topic.contains('#')) {
    throw ArgumentError.value(
      topic,
      'topic',
      'wildcards are not allowed when publishing',
    );
  }
}
