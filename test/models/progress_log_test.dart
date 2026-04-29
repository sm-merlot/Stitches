import 'package:flutter_test/flutter_test.dart';
import 'package:stitches/models/progress/progress_log.dart';

void main() {
  // ─── helpers ──────────────────────────────────────────────────────────────

  ProgressLogEntry e(String date, int stitches, [int back = 0]) =>
      ProgressLogEntry(isoDate: date, stitchCount: stitches, backstitchCount: back);

  DateTime d(String iso) => parseIsoDate(iso);

  List<ProgressLogEntry> sorted(List<ProgressLogEntry> log) =>
      [...log]..sort((a, b) => a.isoDate.compareTo(b.isoDate));

  // ─── logCountAsOf ──────────────────────────────────────────────────────────

  group('logCountAsOf', () {
    test('empty log → 0', () {
      expect(logCountAsOf([], d('2026-04-01')), 0);
    });

    test('single entry on queried date → its count', () {
      final log = sorted([e('2026-04-01', 42)]);
      expect(logCountAsOf(log, d('2026-04-01')), 42);
    });

    test('query before any entry → 0', () {
      final log = sorted([e('2026-04-10', 100)]);
      expect(logCountAsOf(log, d('2026-04-05')), 0);
    });

    test('query after last entry → last entry count', () {
      final log = sorted([e('2026-04-01', 10), e('2026-04-05', 50)]);
      expect(logCountAsOf(log, d('2026-04-30')), 50);
    });

    test('query in middle returns most recent on-or-before entry', () {
      final log = sorted([
        e('2026-04-01', 10),
        e('2026-04-05', 30),
        e('2026-04-10', 60),
      ]);
      expect(logCountAsOf(log, d('2026-04-07')), 30);
    });
  });

  // ─── Daily delta (frogging) ────────────────────────────────────────────────

  group('daily delta / frogging', () {
    test('delta goes up → positive delta', () {
      final log = sorted([
        e('2026-04-01', 20),
        e('2026-04-02', 35),
      ]);
      final prev = logCountAsOf(log, d('2026-04-01'));
      final curr = logCountAsOf(log, d('2026-04-02'));
      expect(curr - prev, 15);
    });

    test('frogging: count drops → negative delta', () {
      final log = sorted([
        e('2026-04-01', 40),
        e('2026-04-02', 25),
      ]);
      final prev = logCountAsOf(log, d('2026-04-01'));
      final curr = logCountAsOf(log, d('2026-04-02'));
      expect(curr - prev, -15);
    });

    test('same count day-over-day → zero delta', () {
      final log = sorted([
        e('2026-04-01', 50),
        e('2026-04-02', 50),
      ]);
      final prev = logCountAsOf(log, d('2026-04-01'));
      final curr = logCountAsOf(log, d('2026-04-02'));
      expect(curr - prev, 0);
    });

    test('gap in entries: delta is from last known entry', () {
      final log = sorted([
        e('2026-04-01', 10),
        e('2026-04-05', 25),
      ]);
      // Days 2-4 have no entries; count-as-of them returns day 1's value.
      final atDay4 = logCountAsOf(log, d('2026-04-04'));
      final atDay5 = logCountAsOf(log, d('2026-04-05'));
      expect(atDay4, 10);
      expect(atDay5, 25);
      expect(atDay5 - atDay4, 15);
    });
  });

  // ─── Streak calculation (consecutive active days) ─────────────────────────
  // "streak" = consecutive calendar days with a positive delta ending today.

  group('streak', () {
    int streak(List<ProgressLogEntry> log, String today) {
      final s = sorted(log);
      if (s.isEmpty) return 0;
      int count = 0;
      var current = d(today);
      while (true) {
        final curr = logCountAsOf(s, current);
        final prev = logCountAsOf(s, current.subtract(const Duration(days: 1)));
        if (curr <= prev && count == 0) return 0; // never started
        if (curr <= prev) break; // gap breaks streak
        count++;
        current = current.subtract(const Duration(days: 1));
      }
      return count;
    }

    test('no log → 0', () {
      expect(streak([], '2026-04-10'), 0);
    });

    test('single active day = 1', () {
      expect(streak([e('2026-04-10', 5)], '2026-04-10'), 1);
    });

    test('two consecutive days = 2', () {
      final log = [e('2026-04-09', 5), e('2026-04-10', 12)];
      expect(streak(log, '2026-04-10'), 2);
    });

    test('gap in activity breaks streak', () {
      // Apr 08 had stitches, Apr 09 nothing, Apr 10 stitches → streak = 1
      final log = [e('2026-04-08', 10), e('2026-04-10', 20)];
      expect(streak(log, '2026-04-10'), 1);
    });

    test('frogging on last day counts as no progress → streak resets', () {
      // Apr 09 count 20, Apr 10 count drops to 15 (frogged)
      final log = [e('2026-04-09', 20), e('2026-04-10', 15)];
      expect(streak(log, '2026-04-10'), 0);
    });
  });

  // ─── ProgressLogEntry serialization ───────────────────────────────────────

  group('ProgressLogEntry fromYaml / toYaml', () {
    test('round-trip with backstitches', () {
      const entry = ProgressLogEntry(
          isoDate: '2026-04-01', stitchCount: 42, backstitchCount: 7);
      final reloaded = ProgressLogEntry.fromYaml(entry.toYaml());
      expect(reloaded, equals(entry));
    });

    test('fromYaml: zero backstitches when field absent', () {
      final entry = ProgressLogEntry.fromYaml({'date': '2026-04-01', 'stitches': 10});
      expect(entry.backstitchCount, 0);
    });

    test('toYaml: backstitchCount omitted when 0', () {
      const entry = ProgressLogEntry(isoDate: '2026-04-01', stitchCount: 5, backstitchCount: 0);
      final yaml = entry.toYaml();
      expect(yaml.containsKey('backstitches'), isFalse);
    });
  });
}

