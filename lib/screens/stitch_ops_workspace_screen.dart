import 'dart:math';
import 'package:flutter/material.dart';
import '../models/pattern.dart';
import '../models/progress_log.dart';
import '../models/stitch.dart';
import '../services/file_service.dart';

// ─── Public entry point ───────────────────────────────────────────────────────

void showWorkspaceStitchOps(
    BuildContext context, List<String> filePaths, String workspaceName) {
  final isWide = MediaQuery.of(context).size.shortestSide >= 600;
  if (isWide) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(
          width: 580,
          child: WorkspaceStitchOpsScreen(
            filePaths: filePaths,
            workspaceName: workspaceName,
          ),
        ),
      ),
    );
  } else {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => WorkspaceStitchOpsScreen(
          filePaths: filePaths,
          workspaceName: workspaceName,
        ),
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

class _WorkspaceStats {
  final int patternCount;
  final int totalStitches;
  final int completedStitches;
  final int completedPatterns;

  /// Combined stitches added today / this week / this month / this year
  /// across all patterns.
  final int todayDelta;
  final int weekDelta;
  final int monthDelta;
  final int yearDelta;

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
    required this.patterns,
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

  // Build daily deltas
  int prevCount = 0;
  final dailyMap = <String, int>{};
  for (final entry in log) {
    final delta = max(0, entry.stitchCount - prevCount);
    dailyMap[entry.isoDate] = delta;
    prevCount = entry.stitchCount;
  }

  final today = DateTime.now();
  int recentDelta = 0;
  for (int i = 0; i < 14; i++) {
    final d = today.subtract(Duration(days: i));
    final iso =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    recentDelta += dailyMap[iso] ?? 0;
  }

  return _PatternSummary(
    name: p.name,
    totalStitches: cellSet.length,
    completedStitches: p.progress.completedStitches.length,
    lastActiveDate: lastActiveDate,
    recentDelta: recentDelta,
  );
}

int _sumFromMap(Map<String, int> dailyMap, DateTime today, int days) {
  int s = 0;
  for (int i = 0; i < days; i++) {
    final d = today.subtract(Duration(days: i));
    final iso =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    s += dailyMap[iso] ?? 0;
  }
  return s;
}

_WorkspaceStats _aggregateStats(List<CrossStitchPattern> patterns) {
  final today = DateTime.now();

  int totalStitches = 0;
  int completedStitches = 0;
  int completedPatterns = 0;
  int todayDelta = 0;
  int weekDelta = 0;
  int monthDelta = 0;
  int yearDelta = 0;
  final summaries = <_PatternSummary>[];

  for (final p in patterns) {
    final summary = _summarisePattern(p);
    summaries.add(summary);
    totalStitches += summary.totalStitches;
    completedStitches += summary.completedStitches;
    if (summary.isComplete) completedPatterns++;

    // Build daily map for this pattern
    final log = [...p.progressLog]
      ..sort((a, b) => a.isoDate.compareTo(b.isoDate));
    int prevCount = 0;
    final dailyMap = <String, int>{};
    for (final entry in log) {
      final delta = max(0, entry.stitchCount - prevCount);
      dailyMap[entry.isoDate] = delta;
      prevCount = entry.stitchCount;
    }

    todayDelta += _sumFromMap(dailyMap, today, 1);
    weekDelta += _sumFromMap(dailyMap, today, 7);
    monthDelta += _sumFromMap(dailyMap, today, 30);
    yearDelta += _sumFromMap(dailyMap, today, 365);
  }

  // Sort: active recently first, then by name
  summaries.sort((a, b) {
    if (a.recentDelta != b.recentDelta) {
      return b.recentDelta.compareTo(a.recentDelta);
    }
    return a.name.compareTo(b.name);
  });

  return _WorkspaceStats(
    patternCount: patterns.length,
    totalStitches: totalStitches,
    completedStitches: completedStitches,
    completedPatterns: completedPatterns,
    todayDelta: todayDelta,
    weekDelta: weekDelta,
    monthDelta: monthDelta,
    yearDelta: yearDelta,
    patterns: summaries,
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

class WorkspaceStitchOpsScreen extends StatefulWidget {
  final List<String> filePaths;
  final String workspaceName;

  const WorkspaceStitchOpsScreen({
    super.key,
    required this.filePaths,
    required this.workspaceName,
  });

  @override
  State<WorkspaceStitchOpsScreen> createState() =>
      _WorkspaceStitchOpsScreenState();
}

class _WorkspaceStitchOpsScreenState
    extends State<WorkspaceStitchOpsScreen> {
  _WorkspaceStats? _stats;
  String? _error;
  int _loaded = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final paths = widget.filePaths
        .where((p) => p.endsWith('.stitches'))
        .toList();
    setState(() {
      _total = paths.length;
      _loaded = 0;
    });

    final patterns = <CrossStitchPattern>[];
    for (final path in paths) {
      try {
        final (pattern, _, __) = await FileService.openFileFromPath(path);
        patterns.add(pattern);
      } catch (_) {
        // Skip unreadable files silently.
      }
      if (!mounted) return;
      setState(() => _loaded++);
    }

    if (!mounted) return;
    setState(() {
      _stats = _aggregateStats(patterns);
    });
  }

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
              widget.workspaceName,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        leading: Navigator.canPop(context) ? const CloseButton() : null,
      ),
      body: _stats == null
          ? _LoadingView(loaded: _loaded, total: _total)
          : _StatsView(stats: _stats!, colorScheme: colorScheme),
    );
  }
}

// ─── Loading view ─────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  final int loaded;
  final int total;
  const _LoadingView({required this.loaded, required this.total});

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
            'Scanning patterns…',
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

// ─── Stats view ───────────────────────────────────────────────────────────────

class _StatsView extends StatelessWidget {
  final _WorkspaceStats stats;
  final ColorScheme colorScheme;
  const _StatsView({required this.stats, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AggregateCard(stats: stats, colorScheme: colorScheme),
        const SizedBox(height: 16),
        _PatternListCard(stats: stats, colorScheme: colorScheme),
      ],
    );
  }
}

// ─── Aggregate overview card ──────────────────────────────────────────────────

class _AggregateCard extends StatelessWidget {
  final _WorkspaceStats stats;
  final ColorScheme colorScheme;
  const _AggregateCard({required this.stats, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final pct = stats.overallPct;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader('Workspace overview'),
            const SizedBox(height: 12),
            Row(
              children: [
                _WSTile(
                    label: 'Patterns',
                    value: stats.patternCount.toString(),
                    color: colorScheme.primary),
                const SizedBox(width: 12),
                _WSTile(
                    label: 'Complete',
                    value: stats.completedPatterns.toString(),
                    color: colorScheme.secondary),
                const SizedBox(width: 12),
                _WSTile(
                    label: 'Stitches done',
                    value: _fmt(stats.completedStitches),
                    color: colorScheme.tertiary),
                const SizedBox(width: 12),
                _WSTile(
                    label: 'Total',
                    value: _fmt(stats.totalStitches),
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
                      valueColor: AlwaysStoppedAnimation<Color>(
                          colorScheme.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${(pct * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionHeader('Combined velocity'),
            const SizedBox(height: 10),
            Row(
              children: [
                _WSTile(
                    label: 'Today',
                    value: _fmt(stats.todayDelta),
                    color: colorScheme.primary),
                const SizedBox(width: 12),
                _WSTile(
                    label: 'This week',
                    value: _fmt(stats.weekDelta),
                    color: colorScheme.secondary),
                const SizedBox(width: 12),
                _WSTile(
                    label: 'This month',
                    value: _fmt(stats.monthDelta),
                    color: colorScheme.tertiary),
                const SizedBox(width: 12),
                _WSTile(
                    label: 'This year',
                    value: _fmt(stats.yearDelta),
                    color: colorScheme.outline),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Per-pattern list card ────────────────────────────────────────────────────

class _PatternListCard extends StatelessWidget {
  final _WorkspaceStats stats;
  final ColorScheme colorScheme;
  const _PatternListCard({required this.stats, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    if (stats.patterns.isEmpty) {
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
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader('Patterns'),
            const SizedBox(height: 8),
            ...stats.patterns.map((p) =>
                _PatternRow(summary: p, colorScheme: colorScheme)),
          ],
        ),
      ),
    );
  }
}

class _PatternRow extends StatelessWidget {
  final _PatternSummary summary;
  final ColorScheme colorScheme;
  const _PatternRow({required this.summary, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final pct = summary.pct;
    final isDone = summary.isComplete;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          // Status indicator
          Icon(
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
          const SizedBox(width: 8),
          // Name
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
                        fontSize: 10,
                        color: colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Progress bar
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
          // Count
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
        fontSize: 11,
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
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color)),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _fmt(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return n.toString();
}

String _shortDate(DateTime d) =>
    '${d.day} ${_monthAbbr(d.month)} ${d.year}';

String _monthAbbr(int m) => const [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ][m - 1];
