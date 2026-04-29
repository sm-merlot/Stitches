import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/page_layout.dart';
import '../models/pattern.dart';
import '../models/progress_log.dart';
import '../models/stitch.dart';
import '../models/stitch_geometry.dart';
import '../models/thread.dart';
import '../providers/editor/editor_provider.dart';

// ─── Public entry point ───────────────────────────────────────────────────────

void showStitchOps(
  BuildContext context,
  CrossStitchPattern pattern, {
  VoidCallback? onClearProgress,
  void Function(String isoDate, int newMinutes)? onAdjustTime,
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
            onAdjustTime: onAdjustTime,
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
            pattern: pattern,
            onClearProgress: onClearProgress,
            onAdjustTime: onAdjustTime),
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
  /// All log entries that have [minutesSpent] > 0, sorted descending by date,
  /// used to populate the time-history editor.
  final List<ProgressLogEntry> timeLog;

  // ── Per-thread ─────────────────────────────────────────────────────────────
  final List<_ThreadStats> threadStats;

  // ── Chart data ─────────────────────────────────────────────────────────────
  /// date-string → stitches added that day (high-watermark deltas, always ≥ 0)
  final Map<String, int> dailyMap;

  /// date-string → minutes spent stitching that day (from progress log).
  final Map<String, int> timeMap;

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
    required this.timeMap,
    required this.dailyData,
    required this.cumulativeData,
    required this.totalMinutes,
    required this.todayMinutes,
    required this.weekMinutes,
    required this.stitchesPerHour,
    required this.timeLog,
  });

  double get overallPct =>
      totalStitches == 0 ? 0 : completedStitches / totalStitches;
}

_StitchOpsStats _computeStats(CrossStitchPattern pattern,
    {Map<String, Thread>? compositeCache}) {
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
      final xy = s.cellCoords;
      if (xy != null) cellSet.add(xy);
    }
  }
  final totalStitches = cellSet.length;
  final totalDone = progress.completedStitches.length;

  // ── Per-thread stats ─────────────────────────────────────────────────────
  // Use the composite cache when available so cell→thread attribution exactly
  // matches what the sidebar colours panel shows (topmost visible layer wins).
  // Falls back to a last-layer-wins scan when no cache is present.
  final threadCounts = <String, int>{};
  final threadDoneCounts = <String, int>{};
  if (compositeCache != null && compositeCache.isNotEmpty) {
    // Each cache entry is "x,y" → Thread (topmost visible layer for that cell).
    for (final entry in compositeCache.entries) {
      final parts = entry.key.split(',');
      if (parts.length != 2) continue;
      final x = int.tryParse(parts[0]);
      final y = int.tryParse(parts[1]);
      if (x == null || y == null) continue;
      final id = entry.value.dmcCode;
      threadCounts[id] = (threadCounts[id] ?? 0) + 1;
      if (progress.completedStitches.contains((x, y))) {
        threadDoneCounts[id] = (threadDoneCounts[id] ?? 0) + 1;
      }
    }
  } else {
    // No composite cache: build a cell→threadId map where the last (topmost)
    // visible layer claiming a cell wins — consistent with the composite renderer.
    final cellThread = <(int, int), String>{};
    for (final layer in pattern.layers) {
      if (!layer.visible) continue;
      for (final s in layer.stitches) {
        if (s is! FullStitch) continue;
        cellThread[(s.x, s.y)] = s.threadId; // later layer overwrites → top wins
      }
    }
    for (final entry in cellThread.entries) {
      final id = entry.value;
      threadCounts[id] = (threadCounts[id] ?? 0) + 1;
      if (progress.completedStitches.contains(entry.key)) {
        threadDoneCounts[id] = (threadDoneCounts[id] ?? 0) + 1;
      }
    }
  }
  // Non-FullStitch, non-BackStitch counted individually per stitch object.
  for (final s in pattern.stitches) {
    if (s is FullStitch || s is BackStitch) continue;
    final xy = s.cellCoords;
    if (xy == null) continue;
    threadCounts[s.threadId] = (threadCounts[s.threadId] ?? 0) + 1;
    if (progress.completedStitches.contains(xy)) {
      threadDoneCounts[s.threadId] = (threadDoneCounts[s.threadId] ?? 0) + 1;
    }
  }
  final threadStats = pattern.threads.values.map((t) {
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
  final doneColours = pattern.threads.values
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
    timeMap: {for (final e in log) e.isoDate: e.minutesSpent},
    dailyData: dailyData,
    cumulativeData: cumulativeData,
    totalMinutes: _computeTotalMinutes(log),
    todayMinutes: _computeMinutesInRange(log, today, const Duration(days: 1)),
    weekMinutes: _computeMinutesInRange(log, today, const Duration(days: 7)),
    stitchesPerHour: _computeStitchesPerHour(log, totalDone),
    // All days with any stitching activity, sorted newest-first.
    // Includes days where minutesSpent == 0 so the user can fill them in.
    timeLog: [...log]
      ..sort((a, b) => b.isoDate.compareTo(a.isoDate)),
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

/// Format minutes as "Xh Ym", "Xh", or "Ym".
String _fmtMins(int mins) {
  if (mins <= 0) return '0m';
  final h = mins ~/ 60;
  final m = mins.remainder(60);
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

/// Convert a [DateTime] to an ISO-8601 date string, e.g. `'2024-01-15'`.
String _isoFromDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';


// ─── Screen ───────────────────────────────────────────────────────────────────

class StitchOpsScreen extends ConsumerWidget {
  /// Seed pattern — used as fallback if [editorProvider] has no file open
  /// (e.g. when the screen is shown standalone without an active editor).
  final CrossStitchPattern pattern;
  final VoidCallback? onClearProgress;
  /// Called when the user saves a manual time adjustment.
  /// Arguments are the ISO date string and the new total minutes for that day.
  final void Function(String isoDate, int newMinutes)? onAdjustTime;
  /// When true the screen renders without a Scaffold so the dialog can
  /// shrink-wrap to its content.  Set automatically by [showStitchOps].
  final bool isDialog;

  const StitchOpsScreen({
    super.key,
    required this.pattern,
    this.onClearProgress,
    this.onAdjustTime,
    this.isDialog = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the editor so any mutation (time adjust, clear progress, etc.)
    // immediately re-renders the stats without needing to close and reopen.
    final editorState = ref.watch(editorProvider);
    final livePattern =
        editorState.isFileOpen ? editorState.pattern : pattern;
    final compositeLayer = editorState.compositeLayer;
    final compositeCache = compositeLayer == null ? null : {
      for (final e in compositeLayer.fullStitches.entries) e.key: e.value.resolvedThread,
    };
    final stats = _computeStats(livePattern, compositeCache: compositeCache);
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
            final timeCard = stats.timeLog.isNotEmpty
                ? _TimeSection(
                    stats: stats,
                    colorScheme: colorScheme,
                    onAdjustTime: onAdjustTime,
                    timeLog: stats.timeLog)
                : null;
            final dailyCard = hasDaily
                ? StitchOpsDailyChart(
                    dailyData: stats.dailyData,
                    timeMap: stats.timeMap,
                    colorScheme: colorScheme)
                : null;
            final cumulativeCard = hasCumulative
                ? StitchOpsCumulativeChart(
                    cumulativeData: stats.cumulativeData,
                    total: stats.totalStitches,
                    estimatedCompletion: stats.estimatedCompletion,
                    timeMap: stats.timeMap,
                    colorScheme: colorScheme,
                  )
                : null;
            final heatmapCard = hasHeatmap
                ? StitchOpsHeatmap(
                    dailyMap: stats.dailyMap,
                    timeMap: stats.timeMap,
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
  final List<ProgressLogEntry> timeLog;
  final void Function(String isoDate, int newMinutes)? onAdjustTime;
  const _TimeSection({
    required this.stats,
    required this.colorScheme,
    required this.timeLog,
    this.onAdjustTime,
  });

  Future<void> _showHistoryDialog(BuildContext context) async {
    final results = await showDialog<Map<String, int>>(
      context: context,
      builder: (ctx) => _TimeHistoryDialog(
        timeLog: timeLog,
        colorScheme: colorScheme,
      ),
    );
    if (results == null || !context.mounted) return;
    for (final entry in results.entries) {
      onAdjustTime!(entry.key, entry.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = onAdjustTime != null;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _SectionHeader('Time')),
              if (canEdit)
                Tooltip(
                  message: 'Edit time history',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => _showHistoryDialog(context),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.edit_outlined,
                        size: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
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

// ─── Time history editor dialog ───────────────────────────────────────────────
//
// Shows every day that has logged time (sorted newest first) plus today even if
// it has 0 minutes, so the user can always add or correct any entry.
// Returns a Map<isoDate, newMinutes> of only the entries that changed.

class _TimeHistoryDialog extends StatefulWidget {
  final List<ProgressLogEntry> timeLog; // sorted desc by date
  final ColorScheme colorScheme;
  const _TimeHistoryDialog({
    required this.timeLog,
    required this.colorScheme,
  });

  @override
  State<_TimeHistoryDialog> createState() => _TimeHistoryDialogState();
}

class _TimeHistoryDialogState extends State<_TimeHistoryDialog> {
  // isoDate → (hoursController, minutesController, originalMinutes)
  late final Map<String, (TextEditingController, TextEditingController, int)>
      _rows;
  late final List<String> _dates; // display order (desc)

  @override
  void initState() {
    super.initState();
    final today = todayIsoDate();
    // Build ordered date list: today first, then all other log entries
    // (already sorted desc). Today is pinned at top even if not in the log.
    final dateSet = <String>{today};
    _dates = [today];
    for (final e in widget.timeLog) {
      if (dateSet.add(e.isoDate)) _dates.add(e.isoDate);
    }

    // Build a lookup of minutesSpent by date.
    final byDate = {for (final e in widget.timeLog) e.isoDate: e.minutesSpent};

    _rows = {};
    for (final d in _dates) {
      final mins = byDate[d] ?? 0;
      _rows[d] = (
        TextEditingController(text: (mins ~/ 60).toString()),
        TextEditingController(text: mins.remainder(60).toString()),
        mins,
      );
    }
  }

  @override
  void dispose() {
    for (final (h, m, _) in _rows.values) {
      h.dispose();
      m.dispose();
    }
    super.dispose();
  }

  int _minutesFor(String date) {
    final (hCtrl, mCtrl, _) = _rows[date]!;
    final h = int.tryParse(hCtrl.text) ?? 0;
    final m = int.tryParse(mCtrl.text) ?? 0;
    return (h.clamp(0, 99) * 60) + m.clamp(0, 59);
  }

  void _save() {
    final changes = <String, int>{};
    for (final date in _dates) {
      final newMins = _minutesFor(date);
      final (_, _, original) = _rows[date]!;
      if (newMins != original) changes[date] = newMins;
    }
    Navigator.of(context).pop(changes);
  }

  String _friendlyDate(String iso) {
    final today = todayIsoDate();
    if (iso == today) return 'Today';
    final dt = parseIsoDate(iso);
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(dt.year, dt.month, dt.day))
        .inDays;
    if (diff == 1) return 'Yesterday';
    return '${dt.day} ${_monthFull(dt.month)} ${dt.year != now.year ? '${dt.year}' : ''}'.trim();
  }

  static const _months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static String _monthFull(int m) => _months[m];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit time history'),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Correct the total stitching time for any day.\nChanges overwrite the recorded values.',
              style: TextStyle(
                fontSize: 12,
                color: widget.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380),
              child: SingleChildScrollView(
                child: Column(
                  children: _dates.map((date) {
                    final (hCtrl, mCtrl, _) = _rows[date]!;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _friendlyDate(date),
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                          SizedBox(
                            width: 52,
                            child: TextField(
                              controller: hCtrl,
                              keyboardType: TextInputType.number,
                              maxLength: 2,
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                labelText: 'h',
                                counterText: '',
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    vertical: 8, horizontal: 6),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 52,
                            child: TextField(
                              controller: mCtrl,
                              keyboardType: TextInputType.number,
                              maxLength: 2,
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                labelText: 'm',
                                counterText: '',
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    vertical: 8, horizontal: 6),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ─── Daily bar chart ──────────────────────────────────────────────────────────

class StitchOpsDailyChart extends StatefulWidget {
  final List<(DateTime, int)> dailyData;
  final Map<String, int> timeMap;
  final ColorScheme colorScheme;
  const StitchOpsDailyChart({
    super.key,
    required this.dailyData,
    required this.timeMap,
    required this.colorScheme,
  });

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
                          ...() {
                            final iso = _isoFromDate(widget.dailyData[_hoverIndex!].$1);
                            final mins = widget.timeMap[iso] ?? 0;
                            return mins > 0
                                ? [('Time', _fmtMins(mins))]
                                : <(String?, String)>[];
                          }(),
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
    double lastLabelX = -100.0;
    for (int i = 0; i < data.length; i++) {
      final (date, _) = data[i];
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}';
      if (key != prevMonth) {
        tp.text = TextSpan(
            text: _monthAbbr(date.month),
            style: TextStyle(color: labelColor, fontSize: 9));
        tp.layout();
        final x = i * barWidth;
        if (x - lastLabelX >= tp.width + 4) {
          prevMonth = key;
          tp.paint(canvas, Offset(x, topPad + chartH + 2));
          lastLabelX = x;
        }
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
  final Map<String, int> timeMap;
  final ColorScheme colorScheme;
  const StitchOpsCumulativeChart({
    super.key,
    required this.cumulativeData,
    required this.total,
    required this.estimatedCompletion,
    required this.timeMap,
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
                          ...() {
                            // Cumulative minutes up to and including hovered date.
                            final hDate = widget.cumulativeData[_hoverIndex!].$1;
                            final hIso = _isoFromDate(hDate);
                            final cumMins = widget.timeMap.entries
                                .where((e) => e.key.compareTo(hIso) <= 0)
                                .fold(0, (s, e) => s + e.value);
                            return cumMins > 0
                                ? [('Time', _fmtMins(cumMins))]
                                : <(String?, String)>[];
                          }(),
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
  final Map<String, int> timeMap;
  final DateTime today;
  final ColorScheme colorScheme;
  const StitchOpsHeatmap({
    super.key,
    required this.dailyMap,
    required this.timeMap,
    required this.today,
    required this.colorScheme,
  });

  @override
  State<StitchOpsHeatmap> createState() => _StitchOpsHeatmapState();
}

class _StitchOpsHeatmapState extends State<StitchOpsHeatmap> {
  (int, int)? _hoverCell; // (week col, dayOfWeek row)
  Offset? _hoverPos;
  int _weekOffset = 0; // weeks scrolled back from "now"; steps of 4

  static const double _chartH = 96.0;
  static const double _monthLabelH = 14.0;
  static const double _dayLabelW = 16.0;
  static const double _gap = 2.0;
  static const int _days = 7;
  static const int _step = 4; // weeks per arrow press

  /// Square cell size derived from the fixed chart height.
  static double get _cellSize {
    final availH = _chartH - _monthLabelH;
    return availH / _days - _gap; // ≈ 9.7 px
  }

  /// Column pitch (cell + gap), same in both axes → square cells.
  static double get _colW => _cellSize + _gap;

  /// How many full week columns fit in [availableWidth].
  static int _weeksForWidth(double availableWidth) =>
      ((availableWidth - _dayLabelW) / _colW).floor().clamp(4, 104);

  // Earliest iso date that has any data, used to cap the left arrow.
  String? get _earliestIso {
    final keys = [
      ...widget.dailyMap.keys,
      ...widget.timeMap.keys,
    ];
    if (keys.isEmpty) return null;
    return (keys..sort()).first;
  }

  DateTime _gridStart(DateTime thisWeekMonday, int weeksVisible) =>
      thisWeekMonday.subtract(
          Duration(days: (weeksVisible - 1 + _weekOffset) * 7));

  bool _canGoBack(int weeksVisible) {
    final earliest = _earliestIso;
    if (earliest == null) return false;
    final earliestDate = parseIsoDate(earliest);
    final today = widget.today;
    final daysFromMonday = today.weekday - 1;
    final thisWeekMonday = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: daysFromMonday));
    // Allow going back only if the earliest data date falls before the current
    // window's start — i.e. there is genuine history not yet in view.
    return earliestDate.isBefore(_gridStart(thisWeekMonday, weeksVisible));
  }

  (int, int)? _hitTest(Offset pos, double chartWidth, int weeksVisible) {
    final availW = chartWidth - _dayLabelW;
    final colW = availW / weeksVisible;
    final rowH = (_chartH - _monthLabelH) / _days;
    final col = ((pos.dx - _dayLabelW) / colW).floor();
    final row = ((pos.dy - _monthLabelH) / rowH).floor();
    if (col < 0 || col >= weeksVisible || row < 0 || row >= _days) return null;
    return (col, row);
  }

  String _windowLabel(DateTime gridStart, int weeksVisible) {
    final end = gridStart.add(Duration(days: weeksVisible * 7 - 1));
    final startLabel =
        '${_monthAbbr(gridStart.month)} ${gridStart.year != end.year ? gridStart.year.toString() : ''}';
    final endLabel = '${_monthAbbr(end.month)} ${end.year}';
    final start = startLabel.trim();
    return start == endLabel.split(' ').first ? endLabel : '$start – $endLabel';
  }

  static const _kMonths = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static String _monthAbbr(int m) => _kMonths[m];

  @override
  Widget build(BuildContext context) {
    final today = widget.today;
    final daysFromMonday = today.weekday - 1;
    final thisWeekMonday = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: daysFromMonday));
    final todayMidnight = DateTime(today.year, today.month, today.day);

    return _Card(
      child: LayoutBuilder(builder: (context, constraints) {
        final weeksVisible = _weeksForWidth(constraints.maxWidth);
        final gridStart = _gridStart(thisWeekMonday, weeksVisible);

        // Tooltip content for hovered cell.
        List<(String?, String)>? tooltipRows;
        if (_hoverCell != null) {
          final (col, row) = _hoverCell!;
          final date = gridStart.add(Duration(days: col * 7 + row));
          if (!date.isAfter(todayMidnight)) {
            final iso =
                '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
            final count = widget.dailyMap[iso] ?? 0;
            final mins = widget.timeMap[iso] ?? 0;
            tooltipRows = [
              (null, _shortDate(date)),
              ('Stitches', count == 0 ? 'No activity' : _fmt(count)),
              if (mins > 0) ('Time', _fmtMins(mins)),
            ];
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with navigation arrows.
            Row(
              children: [
                Expanded(
                    child: _SectionHeader(_windowLabel(gridStart, weeksVisible))),
                SizedBox(
                  width: 28,
                  height: 20,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Earlier',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _canGoBack(weeksVisible)
                        ? () => setState(() {
                              _weekOffset += _step;
                              _hoverCell = null;
                            })
                        : null,
                  ),
                ),
                SizedBox(
                  width: 28,
                  height: 20,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Later',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _weekOffset > 0
                        ? () => setState(() {
                              _weekOffset =
                                  (_weekOffset - _step).clamp(0, _weekOffset);
                              _hoverCell = null;
                            })
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: _chartH,
              child: MouseRegion(
                onHover: (e) {
                  final cell =
                      _hitTest(e.localPosition, constraints.maxWidth, weeksVisible);
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
                        weeksVisible: weeksVisible,
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
                        chartWidth: constraints.maxWidth,
                        chartHeight: _chartH,
                        colorScheme: widget.colorScheme,
                        rows: tooltipRows,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Legend
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Less',
                    style: TextStyle(
                        fontSize: 9,
                        color: widget.colorScheme.onSurfaceVariant)),
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
                            : widget.colorScheme.primary
                                .withValues(alpha: alpha),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
                const SizedBox(width: 4),
                Text('More',
                    style: TextStyle(
                        fontSize: 9,
                        color: widget.colorScheme.onSurfaceVariant)),
              ],
            ),
          ],
        );
      }),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final Map<String, int> dailyMap;
  final DateTime gridStart;
  final DateTime today;
  final int weeksVisible;
  final Color activeColor;
  final Color emptyColor;
  final Color labelColor;
  final (int, int)? hoverCell;

  static const int _days = 7;

  const _HeatmapPainter({
    required this.dailyMap,
    required this.gridStart,
    required this.today,
    required this.weeksVisible,
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

    final availH = size.height - monthLabelH;
    // Square cells: derive size from the fixed height so cells are always square
    // regardless of the chart width. Extra width shows more weeks of history.
    final cellSize = (availH / _days - gap).clamp(4.0, double.infinity);
    final colW = cellSize + gap; // column pitch = row pitch → square

    // Find max activity across ALL recorded history so the colour scale stays
    // consistent when scrolling — a busy day always looks the same shade
    // regardless of which window is visible.
    int maxCount = 1;
    for (final count in dailyMap.values) {
      if (count > maxCount) maxCount = count;
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
                  d * colW + // colW == rowPitch → square
                  (cellSize - 8) / 2));
    }

    // Cells + month labels.
    String? prevMonthKey;
    double lastLabelX = -999;
    for (int w = 0; w < weeksVisible; w++) {
      for (int d = 0; d < _days; d++) {
        final date = gridStart.add(Duration(days: w * 7 + d));
        final isFuture = date.isAfter(today);
        final count = isFuture ? 0 : (dailyMap[_iso(date)] ?? 0);

        final x = dayLabelW + w * colW;
        final y = monthLabelH + d * colW;

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
            Rect.fromLTWH(x, y, cellSize, cellSize),
            const Radius.circular(2),
          ),
          Paint()..color = cellColor,
        );

        // Month label: only at row 0, new month, and far enough from previous.
        if (d == 0) {
          final monthKey =
              '${date.year}-${date.month.toString().padLeft(2, '0')}';
          if (monthKey != prevMonthKey && !isFuture) {
            tp.text = TextSpan(
                text: _monthAbbr(date.month),
                style: TextStyle(color: labelColor, fontSize: 8));
            tp.layout();
            // Only draw if there's enough space since the last label.
            if (x - lastLabelX >= tp.width + 4) {
              prevMonthKey = monthKey;
              tp.paint(canvas, Offset(x, 0));
              lastLabelX = x;
            }
          }
        }
      }
    }

    // Hover highlight border.
    if (hoverCell != null) {
      final (hw, hd) = hoverCell!;
      final x = dayLabelW + hw * colW;
      final y = monthLabelH + hd * colW;
      final date = gridStart.add(Duration(days: hw * 7 + hd));
      if (!date.isAfter(today)) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, cellSize, cellSize),
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

  String _monthAbbr(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][m];

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      old.dailyMap != dailyMap ||
      old.today != today ||
      old.weeksVisible != weeksVisible ||
      old.gridStart != gridStart ||
      old.hoverCell != hoverCell;
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
    // Estimate tooltip height so it never overflows below the chart and covers
    // sibling widgets (e.g. the heatmap legend row).
    final estimatedH = rows.length * 18.0 + 16.0;
    top = top.clamp(0.0, max(0.0, chartHeight - estimatedH));

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

class _ThreadBreakdownSection extends StatefulWidget {
  final _StitchOpsStats stats;
  final ColorScheme colorScheme;
  const _ThreadBreakdownSection(
      {required this.stats, required this.colorScheme});

  @override
  State<_ThreadBreakdownSection> createState() =>
      _ThreadBreakdownSectionState();
}

class _ThreadBreakdownSectionState extends State<_ThreadBreakdownSection> {
  final _scrollController = ScrollController();
  bool _canScrollUp = false;
  bool _canScrollDown = false;

  // Show ~6 rows before scrolling (each row ≈ 32 px).
  static const double _maxListH = 192.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScroll());
  }

  void _updateScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final up = pos.pixels > 0;
    final down = pos.pixels < pos.maxScrollExtent;
    if (up != _canScrollUp || down != _canScrollDown) {
      setState(() {
        _canScrollUp = up;
        _canScrollDown = down;
      });
    }
  }

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      (_scrollController.offset + delta)
          .clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.stats.threadStats;
    final cs = widget.colorScheme;

    // Only constrain height when there are enough rows to overflow.
    const rowH = 32.0;
    final contentH = rows.length * rowH;
    final listH = contentH > _maxListH ? _maxListH : contentH;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader('Threads'),
          const SizedBox(height: 8),
          if (_canScrollUp)
            _StitchOpsScrollArrow(
                up: true, onTap: () => _scrollBy(-rowH * 3)),
          SizedBox(
            height: listH,
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.zero,
              itemCount: rows.length,
              itemBuilder: (_, i) =>
                  _ThreadRow(ts: rows[i], colorScheme: cs),
            ),
          ),
          if (_canScrollDown)
            _StitchOpsScrollArrow(
                up: false, onTap: () => _scrollBy(rowH * 3)),
        ],
      ),
    );
  }
}

/// Compact up/down scroll arrow used inside StitchOps cards.
class _StitchOpsScrollArrow extends StatelessWidget {
  final bool up;
  final VoidCallback onTap;
  const _StitchOpsScrollArrow({required this.up, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 18,
        color: cs.surfaceContainerHighest.withValues(alpha: 0.8),
        alignment: Alignment.center,
        child: Icon(
          up ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          size: 16,
          color: cs.onSurfaceVariant,
        ),
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
