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

// ─── Public entry point ───────────────────────────────────────────────────────

void showWorkspaceStitchOps(
    BuildContext context, StorageLocation workspace) {
  final isWide = MediaQuery.of(context).size.shortestSide >= 600;
  if (isWide) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(
          width: 580,
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

class _WorkspaceStats {
  final int patternCount;
  final int totalStitches;
  final int completedStitches;
  final int completedPatterns;
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

class WorkspaceStitchOpsScreen extends ConsumerStatefulWidget {
  final StorageLocation workspace;

  const WorkspaceStitchOpsScreen({super.key, required this.workspace});

  @override
  ConsumerState<WorkspaceStitchOpsScreen> createState() =>
      _WorkspaceStitchOpsScreenState();
}

class _WorkspaceStitchOpsScreenState
    extends ConsumerState<WorkspaceStitchOpsScreen> {
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
        final (pattern, _, __) = await FileService.openFileFromPath(path);
        patterns.add(pattern);
      } catch (_) {
        // Skip unreadable files silently.
      }
      if (!mounted) return;
      setState(() => _loaded++);
    }

    if (!mounted) return;
    setState(() => _stats = _aggregateStats(patterns));
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

    // Enumerate all .stitches files under this folder (recursive).
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
        final bytes = await service.downloadFile(file.fileId);
        final tempPath = '${tempDir.path}/${file.fileId}.stitches';
        await File(tempPath).writeAsBytes(bytes, flush: true);
        final (pattern, _, __) = await FileService.openFileFromPath(tempPath);
        patterns.add(pattern);
      } catch (_) {
        // Skip files that can't be downloaded or parsed.
      }
      if (!mounted) return;
      setState(() => _loaded++);
    }

    if (!mounted) return;
    setState(() => _stats = _aggregateStats(patterns));
  }

  /// Recursively collects all [DrivePatternFile]s under [folder],
  /// up to [maxDepth] levels deep.
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
              ? _LoadingView(loaded: _loaded, total: _total,
                  isDrive: widget.workspace is DriveFolder)
              : _StatsView(stats: _stats!, colorScheme: colorScheme),
    );
  }
}

// ─── Loading view ─────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  final int loaded;
  final int total;
  final bool isDrive;
  const _LoadingView({required this.loaded, required this.total,
      required this.isDrive});

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
            isDrive ? 'Downloading patterns from Drive…' : 'Scanning patterns…',
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
            Icon(Icons.cloud_off_outlined,
                size: 48, color: colorScheme.error),
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
