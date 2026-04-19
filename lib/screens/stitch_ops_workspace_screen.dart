import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../models/pattern.dart';
import '../models/progress_log.dart';
import '../models/stitch.dart';
import '../models/storage_location.dart';
import '../providers/google_drive_provider.dart';
import '../services/file_service.dart';
import '../services/google_drive_service.dart';
import 'stitch_ops_screen.dart';

// ─── Public entry point ───────────────────────────────────────────────────────

void showWorkspaceStitchOps(
    BuildContext context, StorageLocation workspace) {
  final isWide = MediaQuery.of(context).size.shortestSide >= 600;
  if (isWide) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 580,
            maxHeight: MediaQuery.of(ctx).size.height - 48,
          ),
          child: WorkspaceStitchOpsScreen(workspace: workspace),
        ),
      ),
    );
  } else {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => WorkspaceStitchOpsScreen(workspace: workspace),
      ),
    );
  }
}

// ─── Per-pattern summary ──────────────────────────────────────────────────────

class _PatternSummary {
  final String name;
  final int totalStitches;
  final int completedStitches;
  final DateTime? lastActiveDate;
  final int recentDelta; // stitches in last 14 days

  const _PatternSummary({
    required this.name,
    required this.totalStitches,
    required this.completedStitches,
    required this.lastActiveDate,
    required this.recentDelta,
  });

  double get pct =>
      totalStitches == 0 ? 0 : completedStitches / totalStitches;
  bool get isComplete => completedStitches >= totalStitches && totalStitches > 0;
}

// ─── Aggregated workspace stats ───────────────────────────────────────────────

class _WorkspaceStats {
  final int patternCount;
  final int totalStitches;
  final int completedStitches;
  final int completedPatterns;

  // Velocity
  final int todayDelta;
  final int weekDelta;
  final int monthDelta;
  final int yearDelta;

  // Temporal
  final DateTime? startDate;
  final DateTime? lastActiveDate;
  final int currentStreak;
  final int longestStreak;

  // Chart data
  final Map<String, int> dailyMap; // iso → total stitches across all patterns
  final Map<String, int> timeMap;  // iso → total minutes across all patterns
  final List<(DateTime, int)> dailyData; // last 60 days
  final List<(DateTime, int)> cumulativeData; // full history

  // Time totals
  final int totalMinutes;
  final int todayMinutes;
  final int weekMinutes;
  final double stitchesPerHour;

  // Per-pattern list
  final List<_PatternSummary> patterns;

  const _WorkspaceStats({
    required this.patternCount,
    required this.totalStitches,
    required this.completedStitches,
    required this.completedPatterns,
    required this.todayDelta,
    required this.weekDelta,
    required this.monthDelta,
    required this.yearDelta,
    required this.startDate,
    required this.lastActiveDate,
    required this.currentStreak,
    required this.longestStreak,
    required this.dailyMap,
    required this.timeMap,
    required this.dailyData,
    required this.cumulativeData,
    required this.patterns,
    required this.totalMinutes,
    required this.todayMinutes,
    required this.weekMinutes,
    required this.stitchesPerHour,
  });

  double get overallPct =>
      totalStitches == 0 ? 0 : completedStitches / totalStitches;
}

_PatternSummary _summarisePattern(CrossStitchPattern p) {
  final cellSet = <(int, int)>{};
  for (final s in p.stitches) {
    if (s is BackStitch) continue;
    final xy = _stitchXY(s);
    if (xy != null) cellSet.add(xy);
  }

  final log = [...p.progressLog]
    ..sort((a, b) => a.isoDate.compareTo(b.isoDate));
  final lastActiveDate =
      log.isNotEmpty ? parseIsoDate(log.last.isoDate) : null;

  final today = DateTime.now();
  final completed = p.progress.completedStitches.length;
  final recentDelta =
      completed - logCountAsOf(log, today.subtract(const Duration(days: 14)));

  return _PatternSummary(
    name: p.name,
    totalStitches: cellSet.length,
    completedStitches: completed,
    lastActiveDate: lastActiveDate,
    recentDelta: recentDelta,
  );
}

_WorkspaceStats _aggregateStats(List<CrossStitchPattern> patterns) {
  final today = DateTime.now();
  final todayIso =
      '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

  // ── Per-pattern summaries ─────────────────────────────────────────────────
  int totalStitches = 0;
  int completedStitches = 0;
  int completedPatterns = 0;
  final summaries = <_PatternSummary>[];

  for (final p in patterns) {
    final summary = _summarisePattern(p);
    summaries.add(summary);
    totalStitches += summary.totalStitches;
    completedStitches += summary.completedStitches;
    if (summary.isComplete) completedPatterns++;
  }

  summaries.sort((a, b) {
    if (a.recentDelta != b.recentDelta) {
      return b.recentDelta.compareTo(a.recentDelta);
    }
    return a.name.compareTo(b.name);
  });

  // ── Velocity (net-change, same logic as pattern StitchOps) ───────────────
  int todayDelta = 0;
  int weekDelta = 0;
  int monthDelta = 0;
  int yearDelta = 0;

  for (final p in patterns) {
    final log = [...p.progressLog]
      ..sort((a, b) => a.isoDate.compareTo(b.isoDate));
    final completed = p.progress.completedStitches.length;
    todayDelta +=
        completed - logCountAsOf(log, today.subtract(const Duration(days: 1)));
    weekDelta +=
        completed - logCountAsOf(log, today.subtract(const Duration(days: 7)));
    monthDelta +=
        completed -
        logCountAsOf(log, today.subtract(const Duration(days: 30)));
    yearDelta +=
        completed -
        logCountAsOf(log, today.subtract(const Duration(days: 365)));
  }

  // ── Aggregated daily map (sum of all patterns' daily deltas) ─────────────
  final dailyMap = <String, int>{};
  final timeMap = <String, int>{};  // iso → sum of minutesSpent across patterns
  DateTime? startDate;
  DateTime? lastActiveDate;

  for (final p in patterns) {
    final log = [...p.progressLog]
      ..sort((a, b) => a.isoDate.compareTo(b.isoDate));
    int prevCount = 0;
    for (final entry in log) {
      final delta = max(0, entry.stitchCount - prevCount);
      if (delta > 0) {
        dailyMap[entry.isoDate] = (dailyMap[entry.isoDate] ?? 0) + delta;
      }
      if (entry.minutesSpent > 0) {
        timeMap[entry.isoDate] =
            (timeMap[entry.isoDate] ?? 0) + entry.minutesSpent;
      }
      prevCount = entry.stitchCount;
    }
    if (log.isNotEmpty) {
      final first = parseIsoDate(log.first.isoDate);
      final last = parseIsoDate(log.last.isoDate);
      if (startDate == null || first.isBefore(startDate)) startDate = first;
      if (lastActiveDate == null || last.isAfter(lastActiveDate)) {
        lastActiveDate = last;
      }
    }
  }

  // ── Daily data (last 60 days) ─────────────────────────────────────────────
  final dailyData = <(DateTime, int)>[];
  for (int i = 59; i >= 0; i--) {
    final d = today.subtract(Duration(days: i));
    final iso =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    dailyData.add((DateTime(d.year, d.month, d.day), dailyMap[iso] ?? 0));
  }

  // ── Cumulative data (aggregate across all patterns) ───────────────────────
  // Collect all log dates across all patterns, plus today.
  final allIsos = <String>{todayIso};
  for (final p in patterns) {
    for (final e in p.progressLog) {
      allIsos.add(e.isoDate);
    }
  }
  final sortedIsos = allIsos.toList()..sort();

  final cumulativeData = <(DateTime, int)>[];
  for (final iso in sortedIsos) {
    int total = 0;
    for (final p in patterns) {
      final log = [...p.progressLog]
        ..sort((a, b) => a.isoDate.compareTo(b.isoDate));
      total += logCountAsOf(log, parseIsoDate(iso));
    }
    // For today, use actual completedStitches (handles frogging not yet in log).
    if (iso == todayIso) total = completedStitches;
    cumulativeData.add((parseIsoDate(iso), total));
  }
  // Remove leading zero entries.
  while (cumulativeData.length > 1 && cumulativeData.first.$2 == 0) {
    cumulativeData.removeAt(0);
  }

  // ── Streaks ───────────────────────────────────────────────────────────────
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

  // ── Time totals ───────────────────────────────────────────────────────────
  final totalMinutes = timeMap.values.fold(0, (s, v) => s + v);
  int minsInRange(int days) {
    final cutoff = today.subtract(Duration(days: days));
    final cutoffIso = '${cutoff.year}-${cutoff.month.toString().padLeft(2, '0')}-${cutoff.day.toString().padLeft(2, '0')}';
    return timeMap.entries
        .where((e) => e.key.compareTo(cutoffIso) > 0)
        .fold(0, (s, e) => s + e.value);
  }
  final todayMinutes = minsInRange(1);
  final weekMinutes = minsInRange(7);
  final stitchesPerHour = totalMinutes == 0
      ? 0.0
      : completedStitches / (totalMinutes / 60.0);

  return _WorkspaceStats(
    patternCount: patterns.length,
    totalStitches: totalStitches,
    completedStitches: completedStitches,
    completedPatterns: completedPatterns,
    todayDelta: todayDelta,
    weekDelta: weekDelta,
    monthDelta: monthDelta,
    yearDelta: yearDelta,
    startDate: startDate,
    lastActiveDate: lastActiveDate,
    currentStreak: currentStreak,
    longestStreak: longestStreak,
    dailyMap: dailyMap,
    timeMap: timeMap,
    dailyData: dailyData,
    cumulativeData: cumulativeData,
    patterns: summaries,
    totalMinutes: totalMinutes,
    todayMinutes: todayMinutes,
    weekMinutes: weekMinutes,
    stitchesPerHour: stitchesPerHour,
  );
}

(int, int)? _stitchXY(Stitch s) => switch (s) {
      FullStitch(:final x, :final y) => (x, y),
      HalfStitch(:final x, :final y) => (x, y),
      HalfCrossStitch(:final x, :final y) => (x, y),
      QuarterStitch(:final x, :final y) => (x, y),
      QuarterCrossStitch(:final x, :final y) => (x, y),
      BackStitch() => null,
    };

// ─── Screen ───────────────────────────────────────────────────────────────────

class WorkspaceStitchOpsScreen extends ConsumerStatefulWidget {
  final StorageLocation workspace;

  const WorkspaceStitchOpsScreen({super.key, required this.workspace});

  @override
  ConsumerState<WorkspaceStitchOpsScreen> createState() =>
      _WorkspaceStitchOpsScreenState();
}

class _WorkspaceStitchOpsScreenState
    extends ConsumerState<WorkspaceStitchOpsScreen> {
  List<CrossStitchPattern>? _allPatterns;
  Map<String, _PatternSummary>? _allSummaries;
  final Set<String> _excludedNames = {};
  String? _error;
  int _loaded = 0;
  int _total = 0;

  _WorkspaceStats? get _stats {
    final all = _allPatterns;
    if (all == null) return null;
    final included =
        _excludedNames.isEmpty ? all : all.where((p) => !_excludedNames.contains(p.name)).toList();
    return _aggregateStats(included);
  }

  void _togglePattern(String name, bool included) {
    setState(() {
      if (included) {
        _excludedNames.remove(name);
      } else {
        _excludedNames.add(name);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final ws = widget.workspace;
    if (ws is LocalFolder) {
      await _loadLocal(ws);
    } else if (ws is DriveFolder) {
      await _loadDrive(ws);
    }
  }

  // ── Local folder loading ──────────────────────────────────────────────────

  Future<void> _loadLocal(LocalFolder folder) async {
    final paths = await FileService.openFolderFromPath(folder.path);
    if (!mounted) return;
    setState(() {
      _total = paths.length;
      _loaded = 0;
    });

    final patterns = <CrossStitchPattern>[];
    for (final path in paths) {
      try {
        final (pattern, _, _) = await FileService.openFileFromPath(path);
        patterns.add(pattern);
      } catch (_) {}
      if (!mounted) return;
      setState(() => _loaded++);
    }

    if (!mounted) return;
    setState(() {
      _allPatterns = patterns;
      _allSummaries = {for (final p in patterns) p.name: _summarisePattern(p)};
    });
  }

  // ── Google Drive loading ──────────────────────────────────────────────────

  Future<void> _loadDrive(DriveFolder folder) async {
    GoogleDriveService? service;
    try {
      service = await ref.read(googleDriveProvider.notifier).getService();
    } catch (_) {}

    if (!mounted) return;
    if (service == null) {
      setState(() => _error = 'Not signed in to Google Drive.');
      return;
    }

    List<DrivePatternFile> allFiles;
    try {
      allFiles = await _collectDriveFiles(service, folder);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not list Drive folder: $e');
      return;
    }

    if (!mounted) return;
    setState(() {
      _total = allFiles.length;
      _loaded = 0;
    });

    final tempDir = await getTemporaryDirectory();
    final patterns = <CrossStitchPattern>[];

    for (final file in allFiles) {
      try {
        final tempPath = '${tempDir.path}/${file.fileId}.stitches';
        final cached = File(tempPath);
        if (!await cached.exists()) {
          final bytes = await service.downloadFile(file.fileId);
          await cached.writeAsBytes(bytes, flush: true);
        }
        final (pattern, _, _) = await FileService.openFileFromPath(tempPath);
        patterns.add(pattern);
      } catch (_) {}
      if (!mounted) return;
      setState(() => _loaded++);
    }

    if (!mounted) return;
    setState(() {
      _allPatterns = patterns;
      _allSummaries = {for (final p in patterns) p.name: _summarisePattern(p)};
    });
  }

  Future<List<DrivePatternFile>> _collectDriveFiles(
      GoogleDriveService service, DriveFolder folder,
      {int maxDepth = 4}) async {
    if (maxDepth <= 0) return [];
    final contents = await service.listFolderContents(folder);
    final files = contents.files.whereType<DrivePatternFile>().toList();
    for (final sub in contents.subfolders.whereType<DriveFolder>()) {
      try {
        files.addAll(await _collectDriveFiles(service, sub,
            maxDepth: maxDepth - 1));
      } catch (_) {}
    }
    return files;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('StitchOps',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              widget.workspace.displayName,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        leading: Navigator.canPop(context) ? const CloseButton() : null,
      ),
      body: _error != null
          ? _ErrorView(message: _error!, colorScheme: colorScheme)
          : _stats == null
              ? _LoadingView(
                  loaded: _loaded,
                  total: _total,
                  isDrive: widget.workspace is DriveFolder)
              : _StatsView(
                  stats: _stats!,
                  colorScheme: colorScheme,
                  allPatterns: _allPatterns!,
                  allSummaries: _allSummaries!,
                  excludedNames: _excludedNames,
                  onToggle: _togglePattern,
                ),
    );
  }
}

// ─── Loading view ─────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  final int loaded;
  final int total;
  final bool isDrive;
  const _LoadingView(
      {required this.loaded, required this.total, required this.isDrive});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            value: total == 0 ? null : loaded / total,
          ),
          const SizedBox(height: 16),
          Text(
            isDrive
                ? 'Downloading patterns from Drive…'
                : 'Scanning patterns…',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          if (total > 0)
            Text(
              '$loaded / $total',
              style: TextStyle(
                  fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

// ─── Error view ───────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final ColorScheme colorScheme;
  const _ErrorView({required this.message, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

// ─── Stats view ───────────────────────────────────────────────────────────────

class _StatsView extends StatelessWidget {
  final _WorkspaceStats stats;
  final ColorScheme colorScheme;
  final List<CrossStitchPattern> allPatterns;
  final Map<String, _PatternSummary> allSummaries;
  final Set<String> excludedNames;
  final void Function(String name, bool included) onToggle;

  const _StatsView({
    required this.stats,
    required this.colorScheme,
    required this.allPatterns,
    required this.allSummaries,
    required this.excludedNames,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final hasDaily = stats.dailyData.any((d) => d.$2 > 0);
    final hasCumulative = stats.cumulativeData.length >= 2;
    final hasHeatmap = stats.dailyMap.values.any((v) => v > 0);

    return LayoutBuilder(builder: (context, constraints) {
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

      final overviewCard = _WsOverviewCard(stats: stats, colorScheme: colorScheme);
      final velocityCard = _WsVelocityCard(stats: stats, colorScheme: colorScheme);
      final timeCard = stats.totalMinutes > 0
          ? _WsTimeCard(stats: stats, colorScheme: colorScheme)
          : null;
      final dailyCard = hasDaily
          ? _WsChartCard(
              title: 'Daily (60 days)',
              child: StitchOpsDailyChart(
                dailyData: stats.dailyData,
                timeMap: stats.timeMap,
                colorScheme: colorScheme,
              ),
            )
          : null;
      final cumulativeCard = hasCumulative
          ? _WsChartCard(
              title: 'Cumulative',
              child: StitchOpsCumulativeChart(
                cumulativeData: stats.cumulativeData,
                total: stats.totalStitches,
                estimatedCompletion: null,
                timeMap: stats.timeMap,
                colorScheme: colorScheme,
              ),
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

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Overview + Velocity.
          if (isWide)
            pair(overviewCard, velocityCard)
          else ...[
            overviewCard,
            gap,
            velocityCard,
          ],
          gap,

          if (timeCard != null) ...[timeCard, gap],

          // Charts.
          if (isWide) ...[
            if (dailyCard != null && cumulativeCard != null)
              pair(dailyCard, cumulativeCard)
            else if (dailyCard != null)
              dailyCard
            else
              ?cumulativeCard,
            if (dailyCard != null || cumulativeCard != null) gap,
          ] else ...[
            if (dailyCard != null) ...[dailyCard, gap],
            if (cumulativeCard != null) ...[cumulativeCard, gap],
          ],

          if (heatmapCard != null) ...[heatmapCard, gap],

          // Per-pattern list.
          _PatternListCard(
            stats: stats,
            colorScheme: colorScheme,
            allPatterns: allPatterns,
            allSummaries: allSummaries,
            excludedNames: excludedNames,
            onToggle: onToggle,
          ),
        ],
      );
    });
  }
}

// ─── Workspace overview card ──────────────────────────────────────────────────

class _WsOverviewCard extends StatelessWidget {
  final _WorkspaceStats stats;
  final ColorScheme colorScheme;
  const _WsOverviewCard({required this.stats, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final pct = stats.overallPct;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader('Overview'),
            const SizedBox(height: 12),
            Row(
              children: [
                _WSTile(
                    label: 'Done',
                    value: _fmt(stats.completedStitches),
                    color: colorScheme.primary),
                const SizedBox(width: 8),
                _WSTile(
                    label: 'Total',
                    value: _fmt(stats.totalStitches),
                    color: colorScheme.secondary),
                const SizedBox(width: 8),
                _WSTile(
                    label: 'Patterns',
                    value: stats.patternCount.toString(),
                    color: colorScheme.tertiary),
                const SizedBox(width: 8),
                _WSTile(
                    label: 'Complete',
                    value: stats.completedPatterns.toString(),
                    color: colorScheme.outline),
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
                  '${(pct * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: colorScheme.primary),
                ),
              ],
            ),
            if (stats.startDate != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _dateChip('Started', stats.startDate!),
                  if (stats.lastActiveDate != null)
                    _dateChip('Last active', stats.lastActiveDate!),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dateChip(String label, DateTime date) {
    return Chip(
      label: Text('$label: ${_shortDate(date)}',
          style: const TextStyle(fontSize: 11)),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}

// ─── Velocity card ────────────────────────────────────────────────────────────

class _WsVelocityCard extends StatelessWidget {
  final _WorkspaceStats stats;
  final ColorScheme colorScheme;
  const _WsVelocityCard({required this.stats, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader('Velocity'),
            const SizedBox(height: 12),
            Row(
              children: [
                _WSTile(
                    label: 'Today',
                    value: _fmt(stats.todayDelta),
                    color: colorScheme.primary),
                const SizedBox(width: 8),
                _WSTile(
                    label: 'Week',
                    value: _fmt(stats.weekDelta),
                    color: colorScheme.secondary),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _WSTile(
                    label: 'Month',
                    value: _fmt(stats.monthDelta),
                    color: colorScheme.tertiary),
                const SizedBox(width: 8),
                _WSTile(
                    label: 'Year',
                    value: _fmt(stats.yearDelta),
                    color: colorScheme.outline),
              ],
            ),
            if (stats.currentStreak > 0 || stats.longestStreak > 0) ...[
              const SizedBox(height: 10),
              Divider(color: colorScheme.outlineVariant),
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
          ],
        ),
      ),
    );
  }
}

// ─── Chart wrapper card ───────────────────────────────────────────────────────

class _WsChartCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _WsChartCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(title),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

// ─── Per-pattern list card ────────────────────────────────────────────────────

class _PatternListCard extends StatefulWidget {
  final _WorkspaceStats stats;
  final ColorScheme colorScheme;
  final List<CrossStitchPattern> allPatterns;
  final Map<String, _PatternSummary> allSummaries;
  final Set<String> excludedNames;
  final void Function(String name, bool included) onToggle;

  const _PatternListCard({
    required this.stats,
    required this.colorScheme,
    required this.allPatterns,
    required this.allSummaries,
    required this.excludedNames,
    required this.onToggle,
  });

  @override
  State<_PatternListCard> createState() => _PatternListCardState();
}

class _PatternListCardState extends State<_PatternListCard> {
  bool _filterExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final allPatterns = widget.allPatterns;
    final excludedNames = widget.excludedNames;
    final includedCount = allPatterns.length - excludedNames.length;
    final isFiltering = excludedNames.isNotEmpty;

    if (allPatterns.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text('No patterns found',
                style: TextStyle(color: colorScheme.onSurfaceVariant)),
          ),
        ),
      );
    }

    // Build display list: included rows first (in stats-computed order),
    // then excluded rows sorted by name.
    final includedNames =
        widget.stats.patterns.map((s) => s.name).toSet();
    final orderedSummaries = <_PatternSummary>[
      ...widget.stats.patterns,
      ...widget.allSummaries.entries
          .where((e) => !includedNames.contains(e.key))
          .map((e) => e.value)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name)),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row.
            Row(
              children: [
                Expanded(child: _SectionHeader('Patterns')),
                if (isFiltering) ...[
                  Text(
                    '$includedCount of ${allPatterns.length}',
                    style: TextStyle(fontSize: 11, color: colorScheme.primary),
                  ),
                  const SizedBox(width: 4),
                ],
                IconButton(
                  icon: Icon(
                    _filterExpanded
                        ? Icons.filter_list_off
                        : Icons.filter_list,
                    size: 18,
                  ),
                  visualDensity: VisualDensity.compact,
                  tooltip: _filterExpanded ? 'Hide filter' : 'Filter patterns',
                  onPressed: () =>
                      setState(() => _filterExpanded = !_filterExpanded),
                ),
              ],
            ),
            // Select all / none row.
            if (_filterExpanded) ...[
              Row(
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    onPressed: () {
                      for (final p in allPatterns) {
                        widget.onToggle(p.name, true);
                      }
                    },
                    child: const Text('Select all'),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    onPressed: () {
                      for (final p in allPatterns) {
                        widget.onToggle(p.name, false);
                      }
                    },
                    child: const Text('Select none'),
                  ),
                ],
              ),
              Divider(height: 8, color: colorScheme.outlineVariant),
            ],
            const SizedBox(height: 4),
            // Pattern rows.
            ...orderedSummaries.map((s) => _PatternRow(
                  summary: s,
                  colorScheme: colorScheme,
                  showCheckbox: _filterExpanded,
                  isIncluded: !excludedNames.contains(s.name),
                  onToggle: (included) => widget.onToggle(s.name, included),
                )),
          ],
        ),
      ),
    );
  }
}

class _PatternRow extends StatelessWidget {
  final _PatternSummary summary;
  final ColorScheme colorScheme;
  final bool showCheckbox;
  final bool isIncluded;
  final void Function(bool included) onToggle;

  const _PatternRow({
    required this.summary,
    required this.colorScheme,
    required this.showCheckbox,
    required this.isIncluded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final pct = summary.pct;
    final isDone = summary.isComplete;

    Widget row = Row(
      children: [
        if (showCheckbox)
          SizedBox(
            width: 32,
            child: Checkbox(
              value: isIncluded,
              onChanged: (v) => onToggle(v ?? true),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
        Tooltip(
          message: isDone
              ? 'Complete'
              : summary.recentDelta > 0
                  ? 'Active in the last 14 days'
                  : 'No recent activity',
          child: Icon(
            isDone
                ? Icons.check_circle
                : summary.recentDelta > 0
                    ? Icons.pending
                    : Icons.radio_button_unchecked,
            size: 16,
            color: isDone
                ? colorScheme.secondary
                : summary.recentDelta > 0
                    ? colorScheme.primary
                    : colorScheme.outlineVariant,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary.name,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              if (summary.lastActiveDate != null)
                Text(
                  'Last: ${_shortDate(summary.lastActiveDate!)}',
                  style: TextStyle(
                      fontSize: 10, color: colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                  isDone ? colorScheme.secondary : colorScheme.primary),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: Text(
            '${_fmt(summary.completedStitches)}/${_fmt(summary.totalStitches)}',
            style: TextStyle(
                fontSize: 11,
                color: isDone
                    ? colorScheme.secondary
                    : colorScheme.onSurfaceVariant,
                fontWeight: isDone ? FontWeight.w600 : null),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );

    if (showCheckbox && !isIncluded) {
      row = Opacity(opacity: 0.4, child: row);
    }

    return InkWell(
      onTap: showCheckbox ? () => onToggle(!isIncluded) : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: row,
      ),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

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

class _WSTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _WSTile(
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
            style:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      ],
    );
  }
}

// ─── Workspace time card ──────────────────────────────────────────────────────

class _WsTimeCard extends StatelessWidget {
  final _WorkspaceStats stats;
  final ColorScheme colorScheme;
  const _WsTimeCard({required this.stats, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader('Time'),
            const SizedBox(height: 12),
            Row(
              children: [
                _WSTile(
                  label: 'Total',
                  value: _fmtMins(stats.totalMinutes),
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                _WSTile(
                  label: 'Today',
                  value: _fmtMins(stats.todayMinutes),
                  color: colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                _WSTile(
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
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _fmtMins(int mins) {
  if (mins <= 0) return '0m';
  final h = mins ~/ 60;
  final m = mins.remainder(60);
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

String _fmt(int n) {
  final sign = n < 0 ? '-' : '';
  final abs = n.abs();
  if (abs >= 1000000) return '$sign${(abs / 1000000).toStringAsFixed(1)}M';
  if (abs >= 1000) return '$sign${(abs / 1000).toStringAsFixed(1)}k';
  return n.toString();
}

String _shortDate(DateTime d) => '${d.day} ${_monthAbbr(d.month)} ${d.year}';

String _monthAbbr(int m) => const [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ][m - 1];
