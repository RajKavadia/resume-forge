/// Split [raw] on newlines, commas, and semicolons; trim, drop empties, dedupe
/// (first occurrence wins).
List<String> parseKeys(String raw) {
  final parts = raw.split(RegExp(r'[\n,;]+'));
  final seen = <String>{};
  final out = <String>[];
  for (final part in parts) {
    final key = part.trim();
    if (key.isEmpty) continue;
    if (seen.add(key)) out.add(key);
  }
  return out;
}

/// True when [error] looks like auth, forbidden, rate-limit, or quota exhaustion.
bool isRotatableNvidiaKeyFailure(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('401') ||
      msg.contains('403') ||
      msg.contains('429') ||
      msg.contains('quota') ||
      msg.contains('rate') ||
      msg.contains('exhausted') ||
      msg.contains('resource');
}

/// Round-robin / failover helper over a list of API keys.
class NvidiaApiKeyRotator {
  NvidiaApiKeyRotator(
    List<String> keys, {
    int startingIndex = 0,
  })  : keys = List<String>.unmodifiable(keys),
        _index = keys.isEmpty
            ? 0
            : startingIndex.clamp(0, keys.length - 1);

  final List<String> keys;
  final Set<String> _failed = {};
  int _index;

  /// Key at the current rotation index (ignores failed-set until [advance]).
  String get currentKey {
    if (keys.isEmpty) {
      throw StateError('NvidiaApiKeyRotator has no keys.');
    }
    return keys[_index];
  }

  /// Move to the next key (wraps). Skips keys previously [markFailed].
  void advance() {
    if (keys.isEmpty) return;
    if (_failed.length >= keys.length) return;
    for (var i = 0; i < keys.length; i++) {
      _index = (_index + 1) % keys.length;
      if (!_failed.contains(keys[_index])) return;
    }
  }

  /// Permanently skip [key] for subsequent [advance] / [runWithRotation] picks.
  void markFailed(String key) {
    _failed.add(key);
  }

  /// Run [action] with the current key; on rotatable failures, try each remaining
  /// key at most once. A single key is a passthrough (one attempt, rethrow).
  Future<T> runWithRotation<T>(
    Future<T> Function(String apiKey) action,
  ) async {
    if (keys.isEmpty) {
      throw Exception('No API keys available.');
    }
    if (keys.length == 1) {
      return action(keys.first);
    }

    Object? lastError;
    final tried = <String>{};

    for (var attempt = 0; attempt < keys.length; attempt++) {
      final key = keys[_index];
      if (_failed.contains(key) || tried.contains(key)) {
        advance();
        continue;
      }
      tried.add(key);
      try {
        return await action(key);
      } catch (e) {
        lastError = e;
        if (!isRotatableNvidiaKeyFailure(e)) rethrow;
        markFailed(key);
        advance();
      }
    }

    throw lastError ?? Exception('All API keys exhausted.');
  }
}
