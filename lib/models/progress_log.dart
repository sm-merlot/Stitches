import 'package:flutter/foundation.dart';

/// A single daily entry in the StitchOps progress log.
///
/// Stored at the pattern level (not inside [PatternProgress]) so it is
/// never affected by the progress undo/redo stack.  Each entry represents
/// the high-watermark stitch count reached on a given calendar date — i.e.
/// the value only goes up within a day.  If the user undoes work, the entry
/// for that day still records the peak count, preserving an accurate record
/// of how much they physically stitched.
@immutable
class ProgressLogEntry {
  /// ISO-8601 date, e.g. `'2024-01-15'`.
  final String isoDate;

  /// High-watermark cumulative completed cross-stitch count on [isoDate].
  final int stitchCount;

  /// High-watermark cumulative completed backstitch count on [isoDate].
  final int backstitchCount;

  const ProgressLogEntry({
    required this.isoDate,
    required this.stitchCount,
    required this.backstitchCount,
  });

  ProgressLogEntry copyWith({
    String? isoDate,
    int? stitchCount,
    int? backstitchCount,
  }) =>
      ProgressLogEntry(
        isoDate: isoDate ?? this.isoDate,
        stitchCount: stitchCount ?? this.stitchCount,
        backstitchCount: backstitchCount ?? this.backstitchCount,
      );

  factory ProgressLogEntry.fromYaml(Map yaml) {
    return ProgressLogEntry(
      isoDate: yaml['date'] as String,
      stitchCount: (yaml['stitches'] as num?)?.toInt() ?? 0,
      backstitchCount: (yaml['backstitches'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toYaml() => {
        'date': isoDate,
        'stitches': stitchCount,
        if (backstitchCount > 0) 'backstitches': backstitchCount,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProgressLogEntry &&
          isoDate == other.isoDate &&
          stitchCount == other.stitchCount &&
          backstitchCount == other.backstitchCount;

  @override
  int get hashCode => Object.hash(isoDate, stitchCount, backstitchCount);

  @override
  String toString() =>
      'ProgressLogEntry($isoDate, stitches: $stitchCount, back: $backstitchCount)';
}

/// Returns today's date as an ISO-8601 string, e.g. `'2024-01-15'`.
String todayIsoDate() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

/// Parses an ISO-8601 date string into a [DateTime] at midnight local time.
DateTime parseIsoDate(String iso) {
  final parts = iso.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}
