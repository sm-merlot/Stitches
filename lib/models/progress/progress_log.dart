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

  /// Total minutes spent stitching on [isoDate].
  final int minutesSpent;

  const ProgressLogEntry({
    required this.isoDate,
    required this.stitchCount,
    required this.backstitchCount,
    this.minutesSpent = 0,
  });

  ProgressLogEntry copyWith({
    String? isoDate,
    int? stitchCount,
    int? backstitchCount,
    int? minutesSpent,
  }) =>
      ProgressLogEntry(
        isoDate: isoDate ?? this.isoDate,
        stitchCount: stitchCount ?? this.stitchCount,
        backstitchCount: backstitchCount ?? this.backstitchCount,
        minutesSpent: minutesSpent ?? this.minutesSpent,
      );

  factory ProgressLogEntry.fromYaml(Map yaml) {
    return ProgressLogEntry(
      isoDate: yaml['date'] as String,
      stitchCount: (yaml['stitches'] as num?)?.toInt() ?? 0,
      backstitchCount: (yaml['backstitches'] as num?)?.toInt() ?? 0,
      minutesSpent: (yaml['minutes'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toYaml() => {
        'date': isoDate,
        'stitches': stitchCount,
        if (backstitchCount > 0) 'backstitches': backstitchCount,
        if (minutesSpent > 0) 'minutes': minutesSpent,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProgressLogEntry &&
          isoDate == other.isoDate &&
          stitchCount == other.stitchCount &&
          backstitchCount == other.backstitchCount &&
          minutesSpent == other.minutesSpent;

  @override
  int get hashCode => Object.hash(isoDate, stitchCount, backstitchCount, minutesSpent);

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

/// Returns the high-watermark cumulative stitch count as of [date].
///
/// Uses the most recent log entry whose date is on or before [date].
/// [sortedLog] must be sorted ascending by [ProgressLogEntry.isoDate].
/// Returns 0 if no entry predates [date].
int logCountAsOf(List<ProgressLogEntry> sortedLog, DateTime date) {
  final iso =
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  int count = 0;
  for (final entry in sortedLog) {
    if (entry.isoDate.compareTo(iso) <= 0) {
      count = entry.stitchCount;
    } else {
      break; // ascending order — no earlier entries after this point
    }
  }
  return count;
}
