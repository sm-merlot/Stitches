import 'dart:math';
import 'package:flutter/material.dart';
import '../models/page_layout.dart';
import '../models/pattern.dart';
import '../models/progress_log.dart';
import '../models/stitch.dart';
import '../models/thread.dart';

// ─── Public entry point ───────────────────────────────────────────────────────

void showStitchOps(
  BuildContext context,
  CrossStitchPattern pattern, {
  VoidCallback? onClearProgress,
}) {
  final isWide = MediaQuery.of(context).size.shortestSide >= 600;
  if (isWide) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: MediaQuery.of(ctx).size.height - 48,
          ),
          child: StitchOpsScreen(
            pattern: pattern,
            onClearProgress: onClearProgress,
            isDialog: true,
          ),
        ),
      ),
    );
  } else {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => StitchOpsScreen(
            pattern: pattern, onClearProgress: onClearProgress),
      ),
    );
  }
}

// ─── Stats computation ────────────────────────────────────────────────────────

class _ThreadStats {
  final Thread thread;
  final int total;
  final int done;

  const _ThreadStats({
    required this.thread,
    required this.total,
    required this.done,
  });

  double get pct => total == 0 ? 0 : done / total;
}

class _StitchOpsStats {
  // ── Overall ────────────────────────────────────────────────────────────────
  final int totalStitches;
  final int totalBackstitches;
  final int completedStitches;
  final int completedBackstitches;

  // ── Colours & pages ────────────────────────────────────────────────────────
  final int doneColours;
  final int totalColours;
  final int donePages;
  final int totalPages;

  // ── Temporal ──────────────────────────────────────────────────────────────
  final int todayDelta;
  final int weekDelta;
  final int monthDelta;
  final int yearDelta;
  final DateTime? startDate;
  final DateTime? lastActiveDate;
  final DateTime? estimatedCompletion;
  final double avgPerActiveDay;
  final double recentDailyRate;
  final int currentStreak;
  final int longestStreak;

  // ── Time tracking ─────────────────────────────────────────────────────────
  final int totalMinutes;
  final int todayMinutes;
  final int weekMinutes;
  final double stitchesPerHour;

  // ── Per-thread ─────────────────────────────────────────────────────────────
  final List<_ThreadStats> threadStats;

  // ── Chart data ─────────────────────────────────────────────────────────────
  /// date-string → stitches added that day (high-watermark deltas, always ≥ 0)
  final Map<String, int> dailyMap;

  /// Last 60 days of daily stitch counts (0 if no activity).
  final List<(DateTime, int)> dailyData;

  /// Cumulative progress over entire log history (adjusted for frogging).
  final List<(DateTime, int)> cumulativeData;

  const _StitchOpsStats({
    required this.totalStitches,
    required this.totalBackstitches,
    required this.completedStitches,
    required this.completedBackstitches,
    required this.doneColours,
    required this.totalColours,
    required this.donePages,
    required this.totalPages,
    required this.todayDelta,
    required this.weekDelta,
    required this.monthDelta,
    required this.yearDelta,
    required this.startDate,
    required this.lastActiveDate,
    required this.estimatedCompletion,
    required this.avgPerActiveDay,
    required this.recentDailyRate,
    required this.currentStreak,
    required this.longestStreak,
    required this.threadStats,
    required this.dailyMap,
    required this.dailyData,
    required this.cumulativeData,
    required this.totalMinutes,
    required this.todayMinutes,
    required this.weekMinutes,
    required this.stitchesPerHour,
  });

  double get overallPct =>
      totalStitches == 0 ? 0 : completedStitches / totalStitches;
}

_StitchOpsStats _computeStats(CrossStitchPattern pattern) {
  final progress = pattern.progress;
  final log = [...pattern.progressLog]
    ..sort((a, b) => a.isoDate.compareTo(b.isoDate));

  // ── Total stitch counts ──────────────────────────────────────────────────
  final cellSet = <(int, int)>{};
  int totalBackstitches = 0;
  for (final s in pattern.stitches) {
    if (s is BackStitch) {
      totalBackstitches++;
    } else {
      final xy = _stitchXY(s);
      if (xy != null) cellSet.add(xy);
    }
  }
  final totalStitches = cellSet.length;
  final totalDone = progress.completedStitches.length;

  // ── Per-thread stats ─────────────────────────────────────────────────────
  // For FullStitches, deduplicate across layers so the counts match the
  // thread panel (first layer claiming a cell wins, same as composite fallback).
  final threadCounts = <String, int>{};
  final threadDoneCounts = <String, int>{};
  {
    final seen = <(int, int)>{};
    for (final layer in pattern.layers) {
      for (final s in layer.stitches) {
        if (s is! FullStitch) continue;
        final cell = (s.x, s.y);
        if (!seen.add(cell)) continue;
        threadCounts[s.threadId] = (threadCounts[s.threadId] ?? 0) + 1;
        if (progress.completedStitches.contains(cell)) {
          threadDoneCounts[s.threadId] =
              (threadDoneCounts[s.threadId] ?? 0) + 1;
        }
      }
    }
  }
  // Non-FullStitch, non-BackStitch counted individually per stitch object.
  for (final s in pattern.stitches) {
    if (s is FullStitch || s is BackStitch) continue;
    final xy = _stitchXY(s);
    if (xy == null) continue;
    threadCounts[s.threadId] = (threadCounts[s.threadId] ?? 0) + 1;
    if (progress.completedStitches.contains(xy)) {
      threadDoneCounts[s.threadId] = (threadDoneCounts[s.threadId] ?? 0) + 1;
    }
  }
  final threadStats = pattern.threads.map((t) {
    final total = threadCounts[t.dmcCode] ?? 0;
    final done = threadDoneCounts[t.dmcCode] ?? 0;
    return _ThreadStats(thread: t, total: total, done: done);
  }).where((ts) => ts.total > 0).toList()
    ..sort((a, b) => b.total.compareTo(a.total));

  // ── Log-derived delta stats ──────────────────────────────────────────────
  final today = DateTime.now();

  // High-watermark daily deltas — used for bar chart, heatmap, streaks.
  int prevCount = 0;
  final dailyMap = <String, int>{};
  for (final entry in log) {
    final delta = max(0, entry.stitchCount - prevCount);
    dailyMap[entry.isoDate] = delta;
    prevCount = entry.stitchCount;
  }

  // Net period changes (can be negative if frogged).
  final todayDelta =
      totalDone - logCountAsOf(log, today.subtract(const Duration(days: 1)));
  final weekDelta =
      totalDone - logCountAsOf(log, today.subtract(const Duration(days: 7)));
  final monthDelta =
      totalDone - logCountAsOf(log, today.subtract(const Duration(days: 30)));
  final yearDelta =
      totalDone - logCountAsOf(log, today.subtract(const Duration(days: 365)));

  // ── Start / last active ──────────────────────────────────────────────────
  final startDate = log.isNotEmpty ? parseIsoDate(log.first.isoDate) : null;
  final lastActiveDate =
      log.isNotEmpty ? parseIsoDate(log.last.isoDate) : null;

  // ── Rates ────────────────────────────────────────────────────────────────
  final activeDays = dailyMap.values.where((v) => v > 0).length;
  final avgPerActiveDay =
      activeDays == 0 ? 0.0 : totalDone / activeDays;

  final daysLogging =
      startDate == null ? 0 : today.difference(startDate).inDays + 1;
  final recentWindowDays = min(14, max(1, daysLogging));
  final countAtWindowStart =
      logCountAsOf(log, today.subtract(Duration(days: recentWindowDays)));
  final recentNetTotal = totalDone - countAtWindowStart;
  final recentDailyRate =
      recentNetTotal <= 0 ? 0.0 : recentNetTotal / recentWindowDays;

  // ── Estimated completion ─────────────────────────────────────────────────
  DateTime? estimatedCompletion;
  final remaining = totalStitches - totalDone;
  if (recentDailyRate > 0 && remaining > 0) {
    estimatedCompletion =
        today.add(Duration(days: (remaining / recentDailyRate).ceil()));
  }

  // ── Streaks ──────────────────────────────────────────────────────────────
  int currentStreak = 0;
  {
    var d = DateTime(today.year, today.month, today.day);
    while (true) {
      final iso =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      if ((dailyMap[iso] ?? 0) > 0) {
        currentStreak++;
        d = d.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
  }
  int longestStreak = 0;
  {
    int streak = 0;
    final activeDates = dailyMap.entries
        .where((e) => e.value > 0)
        .map((e) => e.key)
        .toList()
      ..sort();
    for (int i = 0; i < activeDates.length; i++) {
      if (i == 0) {
        streak = 1;
      } else {
        final prev = parseIsoDate(activeDates[i - 1]);
        final curr = parseIsoDate(activeDates[i]);
        streak = curr.difference(prev).inDays == 1 ? streak + 1 : 1;
      }
      if (streak > longestStreak) longestStreak = streak;
    }
  }

  // ── Colours & pages ──────────────────────────────────────────────────────
  final allStitches = pattern.stitches;
  final doneColours = pattern.threads
      .where((t) => progress.isColourDone(t.dmcCode, allStitches))
      .length;
  final totalColours = pattern.threads.length;

  PageLayout? pageLayout;
  if (pattern.pageConfig.enabled) {
    pageLayout = PageLayout.compute(pattern.pageConfig, pattern);
  }
  final donePages = progress.completedPages.length;
  final totalPages = pageLayout?.totalPages ?? 0;

  // ── Chart: last 60 days ──────────────────────────────────────────────────
  final dailyData = <(DateTime, int)>[];
  for (int i = 59; i >= 0; i--) {
    final d = today.subtract(Duration(days: i));
    final iso =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    dailyData.add((DateTime(d.year, d.month, d.day), dailyMap[iso] ?? 0));
  }

  // ── Chart: cumulative ────────────────────────────────────────────────────
  final cumulativeData = <(DateTime, int)>[];
  for (final entry in log) {
    cumulativeData.add((parseIsoDate(entry.isoDate), entry.stitchCount));
  }
  if (cumulativeData.isNotEmpty && cumulativeData.last.$2 != totalDone) {
    final todayDate = DateTime(today.year, today.month, today.day);
    if (cumulativeData.last.$1 == todayDate) {
      cumulativeData[cumulativeData.length - 1] = (todayDate, totalDone);
    } else {
      cumulativeData.add((todayDate, totalDone));
    }
  }

  return _StitchOpsStats(
    totalStitches: totalStitches,
    totalBackstitches: totalBackstitches,
    completedStitches: totalDone,
    completedBackstitches: progress.completedBackstitches.length,
    doneColours: doneColours,
    totalColours: totalColours,
    donePages: donePages,
    totalPages: totalPages,
    todayDelta: todayDelta,
    weekDelta: weekDelta,
    monthDelta: monthDelta,
    yearDelta: yearDelta,
    startDate: startDate,
    lastActiveDate: lastActiveDate,
    estimatedCompletion: estimatedCompletion,
    avgPerActiveDay: avgPerActiveDay,
    recentDailyRate: recentDailyRate,
    currentStreak: currentStreak,
    longestStreak: longestStreak,
    threadStats: threadStats,
    dailyMap: dailyMap,
    dailyData: dailyData,
    cumulativeData: cumulativeData,
    totalMinutes: _computeTotalMinutes(log),
    todayMinutes: _computeMinutesInRange(log, today, const Duration(days: 1)),
    weekMinutes: _computeMinutesInRange(log, today, const Duration(days: 7)),
    stitchesPerHour: _computeStitchesPerHour(log, totalDone),
  );
}

// ─── Time helpers ──────────────────────────────────────────────────────────────

int _computeTotalMinutes(List<ProgressLogEntry> log) =>
    log.fold(0, (sum, e) => sum + e.minutesSpent);

/// Sum of [minutesSpent] for entries within the last [window] before [now].
int _computeMinutesInRange(
    List<ProgressLogEntry> log, DateTime now, Duration window) {
  final cutoff = now.subtract(window);
  final cutoffIso =
      '${cutoff.year}-${cutoff.month.toString().padLeft(2, '0')}-${cutoff.day.toString().padLeft(2, '0')}';
  return log
      .where((e) => e.isoDate.compareTo(cutoffIso) > 0)
      .fold(0, (sum, e) => sum + e.minutesSpent);
}

/// Overall stitches-per-hour based on total recorded time.
double _computeStitchesPerHour(List<ProgressLogEntry> log, int totalDone) {
  final total = _computeTotalMinutes(log);
  if (total == 0) return 0;
  return totalDone / (total / 60.0);
}

(int, int)? _stitchXY(Stitch s) => switch (s) {      FullStitch(:final x, :final y) => (x, y),
      HalfStitch(:final x, :final y) => (x, y),
      HalfCrossStitch(:final x, :final y) => (x, y),
      QuarterStitch(:final x, :final y) => (x, y),
      QuarterCrossStitch(:final x, :final y) => (x, y),
      BackStitch() => null,
    };

// ─── Screen ───────────────────────────────────────────────────────────────────

class StitchOpsScreen extends StatelessWidget {
  final CrossStitchPattern pattern;
  final VoidCallback? onClearProgress;
  /// When true the screen renders without a Scaffold so the dialog can
  /// shrink-wrap to its content.  Set automatically by [showStitchOps].
  final bool isDialog;

  const StitchOpsScreen({
    super.key,
    required this.pattern,
    this.onClearProgress,
    this.isDialog = false,
  });

  @override
  Widget build(BuildContext context) {
    final stats = _computeStats(pattern);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final titleWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('StitchOps',
            style: TextStyle(fontWeight: FontWeight.bold)),
        Text(
          pattern.name,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: colorScheme.onSurfaceVariant),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    // Builds the list items. shrinkWrap: true when inside a dialog so the
    // ListView sizes to its content; the outer Flexible handles overflow.
    Widget buildBody(bool shrinkWrap) => LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 460;
            const gap = SizedBox(height: 12);
            const hgap = SizedBox(width: 12);

            Widget pair(Widget a, Widget b) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: a),
                    hgap,
                    Expanded(child: b),
                  ],
                );

            final hasDaily = stats.dailyData.any((d) => d.$2 > 0);
            final hasCumulative = stats.cumulativeData.length >= 2;
            final hasHeatmap = stats.dailyMap.values.any((v) => v > 0);

            final overviewCard =
                _OverviewSection(stats: stats, colorScheme: colorScheme);
            final velocityCard =
                _RateSection(stats: stats, colorScheme: colorScheme);
            final timeCard = stats.totalMinutes > 0
                ? _TimeSection(stats: stats, colorScheme: colorScheme)
                : null;
            final dailyCard = hasDaily
                ? StitchOpsDailyChart(
                    dailyData: stats.dailyData, colorScheme: colorScheme)
                : null;
            final cumulativeCard = hasCumulative
                ? StitchOpsCumulativeChart(
                    cumulativeData: stats.cumulativeData,
                    total: stats.totalStitches,
                    estimatedCompletion: stats.estimatedCompletion,
                    colorScheme: colorScheme,
                  )
                : null;
            final heatmapCard = hasHeatmap
                ? StitchOpsHeatmap(
                    dailyMap: stats.dailyMap,
                    today: DateTime.now(),
                    colorScheme: colorScheme,
                  )
                : null;
            final threadCard = stats.threadStats.isNotEmpty
                ? _ThreadBreakdownSection(
                    stats: stats, colorScheme: colorScheme)
                : null;

            return ListView(
              shrinkWrap: shrinkWrap,
              physics: shrinkWrap
                  ? const ClampingScrollPhysics()
                  : null,
              padding: const EdgeInsets.all(16),
              children: [
                _ControlsSection(colorScheme: colorScheme),
                gap,

                if (isWide)
                  pair(overviewCard, velocityCard)
                else ...[
                  overviewCard,
                  gap,
                  velocityCard,
                ],
                gap,

                if (timeCard != null) ...[timeCard, gap],

                if (isWide) ...[
                  if (dailyCard != null && cumulativeCard != null)
                    pair(dailyCard, cumulativeCard)
                  else if (dailyCard != null)
                    dailyCard
                  else
                    ?cumulativeCard,
                ] else ...[
                  if (dailyCard != null) ...[dailyCard, gap],
                  if (cumulativeCard != null) ...[cumulativeCard, gap],
                ],
                if (isWide && (dailyCard != null || cumulativeCard != null))
                  gap,

                if (isWide) ...[
                  if (heatmapCard != null && threadCard != null)
                    pair(heatmapCard, threadCard)
                  else if (heatmapCard != null)
                    heatmapCard
                  else
                    ?threadCard,
                  if (heatmapCard != null || threadCard != null) gap,
                ] else ...[
                  if (heatmapCard != null) ...[heatmapCard, gap],
                  if (threadCard != null) ...[threadCard, gap],
                ],

                if (stats.startDate == null) ...[
                  _NoDataCard(colorScheme: colorScheme),
                  gap,
                ],
                if (onClearProgress != null && stats.completedStitches > 0)
                  _ClearProgressButton(
                    onClearProgress: onClearProgress!,
                    colorScheme: colorScheme,
                  ),
              ],
            );
          },
        );

    if (isDialog) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // AppBar substitute — matches the theme's AppBar background.
          Material(
            color: colorScheme.surface,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  CloseButton(
                      onPressed: () => Navigator.of(context).pop()),
                  const SizedBox(width: 8),
                  Expanded(child: titleWidget),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          Flexible(child: buildBody(true)),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: titleWidget,
        leading: Navigator.canPop(context) ? const CloseButton() : null,
      ),
      body: buildBody(false),
    );
  }
}

// ─── Overview section ─────────────────────────────────────────────────────────

class _OverviewSection extends StatelessWidget {
  final _StitchOpsStats stats;
  final ColorScheme colorScheme;
  const _OverviewSection({required this.stats, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final pct = stats.overallPct;
    final pctStr = '${(pct * 100).toStringAsFixed(1)}%';

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader('Overview'),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatTile(
                label: 'Done',
                value: _fmt(stats.completedStitches),
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              _StatTile(
                label: 'Total',
                value: _fmt(stats.totalStitches),
                color: colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              _StatTile(
                label: 'Left',
                value: _fmt(stats.totalStitches - stats.completedStitches),
                color: colorScheme.outline,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 10,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(colorScheme.primary),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                pctStr,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: colorScheme.primary),
              ),
            ],
          ),
          if (stats.totalBackstitches > 0 ||
              stats.totalColours > 0 ||
              stats.totalPages > 0) ...[
            const SizedBox(height: 8),
            if (stats.totalBackstitches > 0)
              _MiniRow(
                  'Backstitches',
                  '${_fmt(stats.completedBackstitches)} / ${_fmt(stats.totalBackstitches)}',
                  colorScheme),
            if (stats.totalColours > 0)
              _MiniRow('Colours',
                  '${stats.doneColours} / ${stats.totalColours}', colorScheme),
            if (stats.totalPages > 0)
              _MiniRow('Pages', '${stats.donePages} / ${stats.totalPages}',
                  colorScheme),
          ],
          if (stats.startDate != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _dateChip(context, 'Started', stats.startDate!),
                if (stats.lastActiveDate != null)
                  _dateChip(context, 'Last active', stats.lastActiveDate!),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _dateChip(BuildContext context, String label, DateTime date) {
    return Chip(
      label: Text('$label: ${_shortDate(date)}',
          style: const TextStyle(fontSize: 11)),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _MiniRow extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme colorScheme;
  const _MiniRow(this.label, this.value, this.colorScheme);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Text('$label: ',
              style: TextStyle(
                  fontSize: 11, color: colorScheme.onSurfaceVariant)),
          Text(value,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─── Rate / ETA section ───────────────────────────────────────────────────────

class _RateSection extends StatelessWidget {
  final _StitchOpsStats stats;
  final ColorScheme colorScheme;
  const _RateSection({required this.stats, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader('Velocity'),
          const SizedBox(height: 12),
          // Period deltas — 2×2 grid to stay readable at narrow widths.
          Row(
            children: [
              _StatTile(
                  label: 'Today',
                  value: _fmt(stats.todayDelta),
                  color: colorScheme.primary),
              const SizedBox(width: 8),
              _StatTile(
                  label: 'Week',
                  value: _fmt(stats.weekDelta),
                  color: colorScheme.secondary),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _StatTile(
                  label: 'Month',
                  value: _fmt(stats.monthDelta),
                  color: colorScheme.tertiary),
              const SizedBox(width: 8),
              _StatTile(
                  label: 'Year',
                  value: _fmt(stats.yearDelta),
                  color: colorScheme.outline),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: colorScheme.outlineVariant),
          const SizedBox(height: 6),
          // Rate + streaks
          Row(
            children: [
              Expanded(
                child: _RateRow(
                  label: 'Avg / active day',
                  value: stats.avgPerActiveDay.toStringAsFixed(1),
                ),
              ),
              Expanded(
                child: _RateRow(
                  label: 'Recent (14d)',
                  value: '${stats.recentDailyRate.toStringAsFixed(1)}/day',
                ),
              ),
            ],
          ),
          if (stats.currentStreak > 0 || stats.longestStreak > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (stats.currentStreak > 0)
                  Expanded(
                    child: _RateRow(
                      label: 'Current streak',
                      value:
                          '${stats.currentStreak} ${stats.currentStreak == 1 ? 'day' : 'days'} 🔥',
                    ),
                  ),
                if (stats.longestStreak > 0)
                  Expanded(
                    child: _RateRow(
                      label: 'Longest streak',
                      value:
                          '${stats.longestStreak} ${stats.longestStreak == 1 ? 'day' : 'days'}',
                    ),
                  ),
              ],
            ),
          ],
          if (stats.estimatedCompletion != null) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.flag_outlined,
                      size: 16, color: colorScheme.onPrimaryContainer),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Est. completion: ${_longDate(stats.estimatedCompletion!)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (stats.completedStitches >= stats.totalStitches &&
              stats.totalStitches > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 16, color: colorScheme.onPrimaryContainer),
                  const SizedBox(width: 6),
                  Text(
                    'Pattern complete!',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RateRow extends StatelessWidget {
  final String label;
  final String value;
  const _RateRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 10),
            overflow: TextOverflow.ellipsis),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      ],
    );
  }
}

// ─── Time tracking section ────────────────────────────────────────────────────

class _TimeSection extends StatelessWidget {
  final _StitchOpsStats stats;
  final ColorScheme colorScheme;
  const _TimeSection({required this.stats, required this.colorScheme});

  /// Format minutes as "Xh Ym" or just "Ym" when < 1 hour.
  static String _fmtMins(int mins) {
    if (mins <= 0) return '0m';
    final h = mins ~/ 60;
    final m = mins.remainder(60);
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader('Time'),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatTile(
                label: 'Total',
                value: _fmtMins(stats.totalMinutes),
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              _StatTile(
                label: 'Today',
                value: _fmtMins(stats.todayMinutes),
                color: colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              _StatTile(
                label: 'Week',
                value: _fmtMins(stats.weekMinutes),
                color: colorScheme.tertiary,
              ),
            ],
          ),
          if (stats.stitchesPerHour > 0) ...[
            const SizedBox(height: 10),
            Divider(color: colorScheme.outlineVariant),
            const SizedBox(height: 6),
            _RateRow(
              label: 'Stitches / hour',
              value: stats.stitchesPerHour.toStringAsFixed(1),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Daily bar chart ──────────────────────────────────────────────────────────

class StitchOpsDailyChart extends StatefulWidget {
  final List<(DateTime, int)> dailyData;
  final ColorScheme colorScheme;
  const StitchOpsDailyChart({super.key, required this.dailyData, required this.colorScheme});

  @override
  State<StitchOpsDailyChart> createState() => _StitchOpsDailyChartState();
}

class _StitchOpsDailyChartState extends State<StitchOpsDailyChart> {
  int? _hoverIndex;
  Offset? _hoverPos;
  static const double _chartH = 110.0;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader('Daily (60 days)'),
          const SizedBox(height: 12),
          SizedBox(
            height: _chartH,
            child: LayoutBuilder(builder: (context, constraints) {
              final chartW = constraints.maxWidth;
              return MouseRegion(
                onHover: (e) {
                  if (widget.dailyData.isEmpty) return;
                  final idx = (e.localPosition.dx /
                          (chartW / widget.dailyData.length))
                      .floor()
                      .clamp(0, widget.dailyData.length - 1);
                  setState(() {
                    _hoverIndex = idx;
                    _hoverPos = e.localPosition;
                  });
                },
                onExit: (_) => setState(() {
                  _hoverIndex = null;
                  _hoverPos = null;
                }),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CustomPaint(
                      painter: _BarChartPainter(
                        data: widget.dailyData,
                        barColor: widget.colorScheme.primary,
                        axisColor: widget.colorScheme.outlineVariant,
                        labelColor: widget.colorScheme.onSurfaceVariant,
                        hoverIndex: _hoverIndex,
                      ),
                      size: Size.infinite,
                    ),
                    if (_hoverIndex != null && _hoverPos != null)
                      _ChartTooltip(
                        hoverPos: _hoverPos!,
                        chartWidth: chartW,
                        chartHeight: _chartH,
                        colorScheme: widget.colorScheme,
                        rows: [
                          (null, _shortDate(widget.dailyData[_hoverIndex!].$1)),
                          ('Stitches', _fmt(widget.dailyData[_hoverIndex!].$2)),
                        ],
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<(DateTime, int)> data;
  final Color barColor;
  final Color axisColor;
  final Color labelColor;
  final int? hoverIndex;

  const _BarChartPainter({
    required this.data,
    required this.barColor,
    required this.axisColor,
    required this.labelColor,
    this.hoverIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final maxVal = data.map((d) => d.$2).fold(0, max);
    if (maxVal == 0) return;

    const labelHeight = 14.0;
    const topPad = 4.0;
    final chartH = size.height - labelHeight - topPad;
    final barWidth = size.width / data.length;
    const barGap = 1.0;

    final barPaint = Paint()..color = barColor;
    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1;
    final todayPaint = Paint()..color = barColor.withValues(alpha: 0.35);
    final today = DateTime.now();

    for (int i = 0; i < data.length; i++) {
      final (date, count) = data[i];
      final isToday = date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      if (count > 0) {
        final barH = (count / maxVal) * chartH;
        final rect = Rect.fromLTWH(
          i * barWidth + barGap / 2,
          topPad + chartH - barH,
          barWidth - barGap,
          barH,
        );
        canvas.drawRect(rect, isToday ? todayPaint : barPaint);
        if (isToday) {
          canvas.drawRect(
              rect,
              Paint()
                ..color = barColor
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5);
        }
      }
    }

    canvas.drawLine(Offset(0, topPad + chartH),
        Offset(size.width, topPad + chartH), axisPaint);

    // Hover crosshair.
    if (hoverIndex != null && hoverIndex! < data.length) {
      final cx = hoverIndex! * barWidth + barWidth / 2;
      canvas.drawLine(
        Offset(cx, topPad),
        Offset(cx, topPad + chartH),
        Paint()
          ..color = barColor.withValues(alpha: 0.5)
          ..strokeWidth = 1.0,
      );
    }

    final tp = TextPainter(textDirection: TextDirection.ltr);
    String? prevMonth;
    for (int i = 0; i < data.length; i++) {
      final (date, _) = data[i];
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}';
      if (key != prevMonth) {
        prevMonth = key;
        tp.text = TextSpan(
            text: _monthAbbr(date.month),
            style: TextStyle(color: labelColor, fontSize: 9));
        tp.layout();
        tp.paint(canvas,
            Offset(i * barWidth, topPad + chartH + 2));
      }
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.data != data || old.barColor != barColor || old.hoverIndex != hoverIndex;
}

// ─── Cumulative line chart ────────────────────────────────────────────────────

class StitchOpsCumulativeChart extends StatefulWidget {
  final List<(DateTime, int)> cumulativeData;
  final int total;
  final DateTime? estimatedCompletion;
  final ColorScheme colorScheme;
  const StitchOpsCumulativeChart({
    super.key,
    required this.cumulativeData,
    required this.total,
    required this.estimatedCompletion,
    required this.colorScheme,
  });

  @override
  State<StitchOpsCumulativeChart> createState() => _StitchOpsCumulativeChartState();
}

class _StitchOpsCumulativeChartState extends State<StitchOpsCumulativeChart> {
  int? _hoverIndex;
  Offset? _hoverPos;
  static const double _chartH = 110.0;

  int? _hitTest(double localX, double chartWidth) {
    final data = widget.cumulativeData;
    if (data.length < 2) return null;
    final startDate = data.first.$1;
    final lastDataDate = data.last.$1;
    final etaDate = widget.estimatedCompletion;
    final chartEndDate = (etaDate != null && etaDate.isAfter(lastDataDate))
        ? etaDate
        : lastDataDate;
    final totalDays =
        chartEndDate.difference(startDate).inDays.toDouble().clamp(1.0, double.infinity);
    final hoveredDays = (localX / chartWidth) * totalDays;
    int best = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < data.length; i++) {
      final d = data[i].$1.difference(startDate).inDays.toDouble();
      final dist = (d - hoveredDays).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader('Cumulative'),
          const SizedBox(height: 12),
          SizedBox(
            height: _chartH,
            child: LayoutBuilder(builder: (context, constraints) {
              final chartW = constraints.maxWidth;
              return MouseRegion(
                onHover: (e) {
                  final idx = _hitTest(e.localPosition.dx, chartW);
                  setState(() {
                    _hoverIndex = idx;
                    _hoverPos = e.localPosition;
                  });
                },
                onExit: (_) => setState(() {
                  _hoverIndex = null;
                  _hoverPos = null;
                }),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CustomPaint(
                      painter: _LineChartPainter(
                        data: widget.cumulativeData,
                        total: widget.total,
                        estimatedCompletion: widget.estimatedCompletion,
                        lineColor: widget.colorScheme.primary,
                        projectionColor:
                            widget.colorScheme.primary.withValues(alpha: 0.5),
                        targetColor: widget.colorScheme.outlineVariant,
                        fillColor:
                            widget.colorScheme.primary.withValues(alpha: 0.12),
                        labelColor: widget.colorScheme.onSurfaceVariant,
                        hoverIndex: _hoverIndex,
                      ),
                      size: Size.infinite,
                    ),
                    if (_hoverIndex != null && _hoverPos != null) ...[
                      _ChartTooltip(
                        hoverPos: _hoverPos!,
                        chartWidth: chartW,
                        chartHeight: _chartH,
                        colorScheme: widget.colorScheme,
                        rows: [
                          (null,
                              _shortDate(
                                  widget.cumulativeData[_hoverIndex!].$1)),
                          (
                            'Stitches',
                            _fmt(widget.cumulativeData[_hoverIndex!].$2)
                          ),
                          if (widget.total > 0)
                            (
                              '%',
                              '${(widget.cumulativeData[_hoverIndex!].$2 / widget.total * 100).toStringAsFixed(1)}%'
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<(DateTime, int)> data;
  final int total;
  final DateTime? estimatedCompletion;
  final Color lineColor;
  final Color projectionColor;
  final Color targetColor;
  final Color fillColor;
  final Color labelColor;
  final int? hoverIndex;

  const _LineChartPainter({
    required this.data,
    required this.total,
    required this.estimatedCompletion,
    required this.lineColor,
    required this.projectionColor,
    required this.targetColor,
    required this.fillColor,
    required this.labelColor,
    this.hoverIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final maxVal = total > 0 ? total.toDouble() : data.last.$2.toDouble();
    if (maxVal == 0) return;

    const labelHeight = 14.0;
    const topPad = 4.0;
    final chartH = size.height - labelHeight - topPad;

    final startDate = data.first.$1;
    // Extend x-axis to estimatedCompletion if it lies in the future.
    final lastDataDate = data.last.$1;
    final chartEndDate =
        (estimatedCompletion != null && estimatedCompletion!.isAfter(lastDataDate))
            ? estimatedCompletion!
            : lastDataDate;
    final totalDays =
        chartEndDate.difference(startDate).inDays.toDouble().clamp(1.0, double.infinity);

    Offset toOffset(DateTime date, int count) {
      final x = date.difference(startDate).inDays / totalDays * size.width;
      final y = topPad + chartH - (count / maxVal) * chartH;
      return Offset(x, y);
    }

    // Fill area under actual data.
    final fillPath = Path();
    fillPath.moveTo(0, topPad + chartH);
    for (final (date, count) in data) {
      final o = toOffset(date, count);
      fillPath.lineTo(o.dx, o.dy);
    }
    fillPath.lineTo(toOffset(data.last.$1, data.last.$2).dx, topPad + chartH);
    fillPath.close();
    canvas.drawPath(fillPath, Paint()..color = fillColor);

    // Actual line.
    final linePath = Path();
    linePath.moveTo(toOffset(data.first.$1, data.first.$2).dx,
        toOffset(data.first.$1, data.first.$2).dy);
    for (int i = 1; i < data.length; i++) {
      final o = toOffset(data[i].$1, data[i].$2);
      linePath.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Dashed projection line from last point → (estimatedCompletion, total).
    if (estimatedCompletion != null &&
        estimatedCompletion!.isAfter(lastDataDate) &&
        data.last.$2 < total) {
      final from = toOffset(lastDataDate, data.last.$2);
      final to = toOffset(estimatedCompletion!, total);
      _drawDashed(
        canvas,
        from,
        to,
        Paint()
          ..color = projectionColor
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }

    // Target line.
    if (data.last.$2 < total) {
      canvas.drawLine(
        Offset(0, topPad),
        Offset(size.width, topPad),
        Paint()
          ..color = targetColor
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );
    }

    // Baseline.
    canvas.drawLine(
      Offset(0, topPad + chartH),
      Offset(size.width, topPad + chartH),
      Paint()..color = targetColor..strokeWidth = 1,
    );

    // Hover crosshair + dot.
    if (hoverIndex != null && hoverIndex! < data.length) {
      final (hDate, hCount) = data[hoverIndex!];
      final ho = toOffset(hDate, hCount);
      // Vertical line.
      canvas.drawLine(
        Offset(ho.dx, topPad),
        Offset(ho.dx, topPad + chartH),
        Paint()
          ..color = lineColor.withValues(alpha: 0.4)
          ..strokeWidth = 1.0,
      );
      // Filled dot.
      canvas.drawCircle(
          ho, 4.0, Paint()..color = lineColor);
      canvas.drawCircle(
          ho,
          3.0,
          Paint()..color = fillColor.withValues(alpha: 1.0));
      canvas.drawCircle(
          ho, 4.0,
          Paint()
            ..color = lineColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0);
    }

    // Date labels.
    final tp = TextPainter(textDirection: TextDirection.ltr);
    String? prevLabel;
    for (final (date, _) in data) {
      final x = date.difference(startDate).inDays / totalDays * size.width;
      final label = totalDays > 180 ? '${date.year}' : _monthAbbr(date.month);
      if (label != prevLabel) {
        prevLabel = label;
        tp.text = TextSpan(
            text: label, style: TextStyle(color: labelColor, fontSize: 9));
        tp.layout();
        tp.paint(canvas, Offset(x, topPad + chartH + 2));
      }
    }
  }

  void _drawDashed(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dashLen = 5.0;
    const gapLen = 3.0;
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist < 1) return;
    final ux = dx / dist;
    final uy = dy / dist;
    double d = 0;
    while (d < dist) {
      canvas.drawLine(
        Offset(from.dx + ux * d, from.dy + uy * d),
        Offset(from.dx + ux * min(d + dashLen, dist),
            from.dy + uy * min(d + dashLen, dist)),
        paint,
      );
      d += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.data != data ||
      old.total != total ||
      old.estimatedCompletion != estimatedCompletion ||
      old.hoverIndex != hoverIndex;
}

// ─── Activity heatmap ─────────────────────────────────────────────────────────

class StitchOpsHeatmap extends StatefulWidget {
  final Map<String, int> dailyMap;
  final DateTime today;
  final ColorScheme colorScheme;
  const StitchOpsHeatmap(
      {super.key,
      required this.dailyMap,
      required this.today,
      required this.colorScheme});

  @override
  State<StitchOpsHeatmap> createState() => _StitchOpsHeatmapState();
}

class _StitchOpsHeatmapState extends State<StitchOpsHeatmap> {
  (int, int)? _hoverCell; // (week, dayOfWeek)
  Offset? _hoverPos;
  static const double _chartH = 96.0;
  static const int _weeks = 16;
  static const int _days = 7;

  (int, int)? _hitTest(Offset pos, double chartWidth) {
    const dayLabelW = 16.0;
    const monthLabelH = 14.0;
    const gap = 2.0;
    final availW = chartWidth - dayLabelW;
    const availH = _chartH - monthLabelH;
    final cellW = (availW / _weeks) - gap;
    const cellH = (availH / _days) - gap;
    final cell = min(cellW, cellH).clamp(4.0, 20.0);
    final col = ((pos.dx - dayLabelW) / (cell + gap)).floor();
    final row = ((pos.dy - monthLabelH) / (cell + gap)).floor();
    if (col < 0 || col >= _weeks || row < 0 || row >= _days) return null;
    return (col, row);
  }

  @override
  Widget build(BuildContext context) {
    final today = widget.today;
    // Grid starts on Monday of the week 15 full weeks before the current week.
    final daysFromMonday = today.weekday - 1;
    final thisWeekMonday =
        DateTime(today.year, today.month, today.day).subtract(
      Duration(days: daysFromMonday),
    );
    final gridStart = thisWeekMonday.subtract(const Duration(days: 15 * 7));
    final todayMidnight = DateTime(today.year, today.month, today.day);

    // Tooltip content for hovered cell.
    List<(String?, String)>? tooltipRows;
    if (_hoverCell != null) {
      final (col, row) = _hoverCell!;
      final date = gridStart.add(Duration(days: col * 7 + row));
      if (!date.isAfter(todayMidnight)) {
        final iso =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        final count = widget.dailyMap[iso] ?? 0;
        tooltipRows = [
          (null, _shortDate(date)),
          ('Stitches', count == 0 ? 'No activity' : _fmt(count)),
        ];
      }
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader('Activity (16 weeks)'),
          const SizedBox(height: 10),
          SizedBox(
            height: _chartH,
            child: LayoutBuilder(builder: (context, constraints) {
              final chartW = constraints.maxWidth;
              return MouseRegion(
                onHover: (e) {
                  final cell = _hitTest(e.localPosition, chartW);
                  setState(() {
                    _hoverCell = cell;
                    _hoverPos = e.localPosition;
                  });
                },
                onExit: (_) => setState(() {
                  _hoverCell = null;
                  _hoverPos = null;
                }),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CustomPaint(
                      painter: _HeatmapPainter(
                        dailyMap: widget.dailyMap,
                        gridStart: gridStart,
                        today: todayMidnight,
                        activeColor: widget.colorScheme.primary,
                        emptyColor: widget.colorScheme.surfaceContainerHighest,
                        labelColor: widget.colorScheme.onSurfaceVariant,
                        hoverCell: _hoverCell,
                      ),
                      size: Size.infinite,
                    ),
                    if (tooltipRows != null && _hoverPos != null)
                      _ChartTooltip(
                        hoverPos: _hoverPos!,
                        chartWidth: chartW,
                        chartHeight: _chartH,
                        colorScheme: widget.colorScheme,
                        rows: tooltipRows,
                      ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Less',
                  style: TextStyle(
                      fontSize: 9, color: widget.colorScheme.onSurfaceVariant)),
              const SizedBox(width: 4),
              ...List.generate(5, (i) {
                final alpha = 0.1 + i * 0.22;
                return Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: i == 0
                          ? widget.colorScheme.surfaceContainerHighest
                          : widget.colorScheme.primary.withValues(alpha: alpha),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
              const SizedBox(width: 4),
              Text('More',
                  style: TextStyle(
                      fontSize: 9, color: widget.colorScheme.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final Map<String, int> dailyMap;
  final DateTime gridStart;
  final DateTime today;
  final Color activeColor;
  final Color emptyColor;
  final Color labelColor;
  final (int, int)? hoverCell;

  static const int _weeks = 16;
  static const int _days = 7;

  const _HeatmapPainter({
    required this.dailyMap,
    required this.gridStart,
    required this.today,
    required this.activeColor,
    required this.emptyColor,
    required this.labelColor,
    this.hoverCell,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const dayLabelW = 16.0;
    const monthLabelH = 14.0;
    const gap = 2.0;

    final availW = size.width - dayLabelW;
    final availH = size.height - monthLabelH;
    final cellW = (availW / _weeks) - gap;
    final cellH = (availH / _days) - gap;
    final cell = min(cellW, cellH).clamp(4.0, 20.0);

    // Find max activity for alpha scaling.
    int maxCount = 1;
    for (int w = 0; w < _weeks; w++) {
      for (int d = 0; d < _days; d++) {
        final count = dailyMap[_iso(gridStart.add(Duration(days: w * 7 + d)))] ?? 0;
        if (count > maxCount) maxCount = count;
      }
    }

    final tp = TextPainter(textDirection: TextDirection.ltr);

    // Day-of-week labels (Mon, Wed, Fri).
    const dayLabels = ['M', '', 'W', '', 'F', '', ''];
    for (int d = 0; d < _days; d++) {
      if (dayLabels[d].isEmpty) continue;
      tp.text = TextSpan(
          text: dayLabels[d],
          style: TextStyle(color: labelColor, fontSize: 8));
      tp.layout();
      tp.paint(
          canvas,
          Offset(
              0,
              monthLabelH +
                  d * (cell + gap) +
                  (cell - 8) / 2));
    }

    // Cells + month labels.
    String? prevMonthKey;
    for (int w = 0; w < _weeks; w++) {
      for (int d = 0; d < _days; d++) {
        final date = gridStart.add(Duration(days: w * 7 + d));
        final isFuture = date.isAfter(today);
        final count = isFuture ? 0 : (dailyMap[_iso(date)] ?? 0);

        final x = dayLabelW + w * (cell + gap);
        final y = monthLabelH + d * (cell + gap);

        final Color cellColor;
        if (isFuture) {
          cellColor = emptyColor.withValues(alpha: 0.4);
        } else if (count == 0) {
          cellColor = emptyColor;
        } else {
          final alpha = (0.25 + 0.75 * count / maxCount).clamp(0.0, 1.0);
          cellColor = activeColor.withValues(alpha: alpha);
        }

        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, cell, cell),
            const Radius.circular(2),
          ),
          Paint()..color = cellColor,
        );

        // Month label at the first visible day of each new month (only row 0).
        if (d == 0) {
          final monthKey =
              '${date.year}-${date.month.toString().padLeft(2, '0')}';
          if (monthKey != prevMonthKey && !isFuture) {
            prevMonthKey = monthKey;
            tp.text = TextSpan(
                text: _monthAbbr(date.month),
                style: TextStyle(color: labelColor, fontSize: 8));
            tp.layout();
            tp.paint(canvas, Offset(x, 0));
          }
        }
      }
    }

    // Hover highlight border.
    if (hoverCell != null) {
      final (hw, hd) = hoverCell!;
      final x = dayLabelW + hw * (cell + gap);
      final y = monthLabelH + hd * (cell + gap);
      final date = gridStart.add(Duration(days: hw * 7 + hd));
      if (!date.isAfter(today)) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, cell, cell),
            const Radius.circular(2),
          ),
          Paint()
            ..color = activeColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      old.dailyMap != dailyMap || old.today != today || old.hoverCell != hoverCell;
}

// ─── Chart tooltip overlay ────────────────────────────────────────────────────

class _ChartTooltip extends StatelessWidget {
  final Offset hoverPos;
  final double chartWidth;
  final double chartHeight;
  final ColorScheme colorScheme;

  /// Each row is (label, value). A null label renders as a bold header row.
  final List<(String?, String)> rows;

  const _ChartTooltip({
    required this.hoverPos,
    required this.chartWidth,
    required this.chartHeight,
    required this.colorScheme,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    const tooltipW = 144.0;
    const xOff = 12.0;
    const yOff = -8.0;

    double left = hoverPos.dx + xOff;
    double top = hoverPos.dy + yOff;
    // Flip horizontally if near right edge.
    if (left + tooltipW > chartWidth) left = hoverPos.dx - tooltipW - xOff;
    left = left.clamp(0.0, max(0.0, chartWidth - tooltipW));
    top = top.clamp(0.0, chartHeight - 10.0);

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.inverseSurface.withValues(alpha: 0.93),
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x28000000),
                  blurRadius: 6,
                  offset: Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: rows.map((row) {
              final (label, value) = row;
              if (label == null) {
                return Text(
                  value,
                  style: TextStyle(
                    color: colorScheme.onInverseSurface,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$label: ',
                      style: TextStyle(
                        color: colorScheme.onInverseSurface
                            .withValues(alpha: 0.65),
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        color: colorScheme.onInverseSurface,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ─── Thread breakdown section ─────────────────────────────────────────────────

class _ThreadBreakdownSection extends StatelessWidget {
  final _StitchOpsStats stats;
  final ColorScheme colorScheme;
  const _ThreadBreakdownSection(
      {required this.stats, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader('Threads'),
          const SizedBox(height: 8),
          ...stats.threadStats.map((ts) => _ThreadRow(
                ts: ts,
                colorScheme: colorScheme,
              )),
        ],
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  final _ThreadStats ts;
  final ColorScheme colorScheme;
  const _ThreadRow({required this.ts, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final isDone = ts.done >= ts.total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: ts.thread.color,
              border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.4), width: 1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: Text(
              'DMC ${ts.thread.dmcCode}',
              style: const TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ts.pct,
                minHeight: 6,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDone ? colorScheme.secondary : colorScheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 56,
            child: Text(
              '${_fmt(ts.done)}/${_fmt(ts.total)}',
              style: TextStyle(
                fontSize: 10,
                color:
                    isDone ? colorScheme.secondary : colorScheme.onSurfaceVariant,
                fontWeight: isDone ? FontWeight.w600 : null,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── No-data card ─────────────────────────────────────────────────────────────

class _NoDataCard extends StatelessWidget {
  final ColorScheme colorScheme;
  const _NoDataCard({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Icon(Icons.bar_chart_outlined,
                size: 40, color: colorScheme.outlineVariant),
            const SizedBox(height: 10),
            Text(
              'No stitching history yet',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              'Switch to Stitch mode and start marking\nstitches done to track your progress here.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Controls section (collapsible) ──────────────────────────────────────────

class _ControlsSection extends StatelessWidget {
  final ColorScheme colorScheme;
  const _ControlsSection({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.hardEdge,
      child: ExpansionTile(
        leading:
            Icon(Icons.help_outline_rounded, size: 18, color: colorScheme.primary),
        title: Text(
          'CONTROLS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        tilePadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        childrenPadding:
            const EdgeInsets.fromLTRB(16, 0, 16, 14),
        initiallyExpanded: false,
        children: [
          _ControlRow(
            icon: Icons.touch_app_outlined,
            label: 'Tap',
            detail: 'Mark / frog one stitch',
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 8),
          _ControlRow(
            icon: Icons.mouse_outlined,
            label: 'Double-tap',
            detail:
                'Flood fill — marks all connected stitches of the same colour (or frogs if already done)',
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 8),
          _ControlRow(
            icon: Icons.crop_outlined,
            label: 'Drag to select',
            detail:
                'Draw a region, then tap Mark in the sidebar to mark all stitches inside it',
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }
}

class _ControlRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String detail;
  final ColorScheme colorScheme;
  const _ControlRow(
      {required this.icon,
      required this.label,
      required this.detail,
      required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
              Text(detail,
                  style: TextStyle(
                      fontSize: 11, color: colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Clear progress button ────────────────────────────────────────────────────

class _ClearProgressButton extends StatelessWidget {
  final VoidCallback onClearProgress;
  final ColorScheme colorScheme;
  const _ClearProgressButton(
      {required this.onClearProgress, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.delete_sweep_outlined, size: 16),
        label: const Text('Clear all progress'),
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.error,
          side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Clear all progress?'),
              content: const Text(
                  'This will remove all stitches marked as done. This can be undone.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                      foregroundColor: colorScheme.error),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Clear'),
                ),
              ],
            ),
          );
          if (confirmed == true && context.mounted) {
            onClearProgress();
            Navigator.of(context).pop();
          }
        },
      ),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatTile(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ─── Formatting helpers ───────────────────────────────────────────────────────

String _fmt(int n) {
  final sign = n < 0 ? '-' : '';
  final abs = n.abs();
  if (abs >= 1000000) return '$sign${(abs / 1000000).toStringAsFixed(1)}M';
  if (abs >= 1000) return '$sign${(abs / 1000).toStringAsFixed(1)}k';
  return n.toString();
}

String _shortDate(DateTime d) => '${d.day} ${_monthAbbr(d.month)} ${d.year}';
String _longDate(DateTime d) => '${d.day} ${_monthName(d.month)} ${d.year}';

String _monthAbbr(int m) => const [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ][m - 1];

String _monthName(int m) => const [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ][m - 1];
