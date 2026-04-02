import 'dart:io';
import '../models/pattern.dart';

/// In-memory LRU cache of parsed patterns, keyed by absolute file path.
///
/// Used in workspace mode so switching between recently-opened files is
/// instant rather than re-reading and re-parsing the file each time.
///
/// Cache validity is checked by comparing the file's [FileStat.modified]
/// timestamp against the time the entry was cached.  A mtime change (e.g.
/// after an external edit or an in-app save) evicts the entry and forces a
/// fresh parse.  Call [put] after saving to update the entry without an
/// eviction/re-read cycle.
///
/// Capacity is capped at [maxEntries] (default 6).  The least-recently-used
/// entry is dropped when the cap is reached.
class PatternCache {
  static const int maxEntries = 6;

  static final Map<String, _CacheEntry> _cache = {};

  /// Returns the cached pattern and its wasCompressed flag if the file at
  /// [path] is still unmodified since it was cached, or null otherwise.
  ///
  /// On a cache miss the stale entry (if any) is evicted so the next
  /// [openFileFromPath] call will re-parse.
  static Future<(CrossStitchPattern, bool)?> get(String path) async {
    final entry = _cache[path];
    if (entry == null) return null;
    try {
      final stat = await File(path).stat();
      if (stat.type == FileSystemEntityType.notFound ||
          stat.modified != entry.fileModifiedAt) {
        _cache.remove(path);
        return null;
      }
    } catch (_) {
      _cache.remove(path);
      return null;
    }
    // Promote to MRU position.
    _cache.remove(path);
    _cache[path] = entry.._lastAccessed = DateTime.now();
    return (entry.pattern, entry.wasCompressed);
  }

  /// Store or update [pattern] for [path].
  ///
  /// [fileModifiedAt] should be the file's mtime immediately after writing
  /// (from [FileStat.modified]) so the entry stays valid on the next [get].
  static void put(
    String path,
    CrossStitchPattern pattern,
    bool wasCompressed,
    DateTime fileModifiedAt,
  ) {
    _cache.remove(path); // re-insert at tail (MRU position in insertion order)
    _cache[path] = _CacheEntry(
      pattern: pattern,
      wasCompressed: wasCompressed,
      fileModifiedAt: fileModifiedAt,
    );
    _evict();
  }

  /// Explicitly remove [path] from the cache (e.g. on file deletion).
  static void invalidate(String path) => _cache.remove(path);

  /// Discard all cached entries (e.g. when the workspace is closed).
  static void clear() => _cache.clear();

  static void _evict() {
    while (_cache.length > maxEntries) {
      // Remove the least-recently-used entry.
      String? lruKey;
      DateTime? lruTime;
      for (final e in _cache.entries) {
        if (lruTime == null || e.value._lastAccessed.isBefore(lruTime)) {
          lruKey = e.key;
          lruTime = e.value._lastAccessed;
        }
      }
      if (lruKey != null) _cache.remove(lruKey);
    }
  }
}

class _CacheEntry {
  final CrossStitchPattern pattern;
  final bool wasCompressed;
  final DateTime fileModifiedAt;
  DateTime _lastAccessed;

  _CacheEntry({
    required this.pattern,
    required this.wasCompressed,
    required this.fileModifiedAt,
  }) : _lastAccessed = DateTime.now();
}
