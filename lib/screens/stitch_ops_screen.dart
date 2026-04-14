import 'dart:math';
import 'package:flutter/material.dart';
import '../models/pattern.dart';
import '../models/pattern_progress.dart';
import '../models/progress_log.dart';
import '../models/stitch.dart';
import '../models/thread.dart';

// ─── Public entry point ───────────────────────────────────────────────────────

void showStitchOps(BuildContext context, CrossStitchPattern pattern) {
  final isWide = MediaQuery.of(context).size.shortestSide >= 600;
  if (isWide) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(
          width: 540,
          child: StitchOpsScreen(pattern: pattern),
        ),
      ),
    );
  } else {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => StitchOpsScreen(pattern: pattern),
      ),
    );
  }
}

// ─── Stats computation ────────────────────────────────────────────────────────

class _ThreadStats {
  final Thread thread;
  final int total;    // unique cells belonging to this thread
  final int done;     // completed cells

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

  // ── Temporal ──────────────────────────────────────────────────────────────
  final int todayDelta;
  final int weekDelta;
  final int monthDelta;
  final int yearDelta;

  /// Date of the very first log entry.
  final DateTime? startDate;

  /// Most recent activity date.
  final DateTime? lastActiveDate;

  /// Estimated completion date based on [recentDailyRate].
  final DateTime? estimatedCompletion;

  /// Average stitches per active day (overall).
  final double avgPerActiveDay;

  /// Average stitches per day over the last 14 days (used for ETA).
  final double recentDailyRate;

  // ── Per-thread ─────────────────────────────────────────────────────────────
  final List<_ThreadStats> threadStats;

  // ── Chart data ─────────────────────────────────────────────────────────────
  /// Last 60 days of daily stitch counts (0 if no activity).
  final List<(DateTime, int)> dailyData;

  /// Cumulative progress over entire log history.
  final List<(DateTime, int)> cumulativeData;

  const _StitchOpsStats({
    required this.totalStitches,
    required this.totalBackstitches,
    required this.completedStitches,
    required this.completedBackstitches,
    required this.todayDelta,
    required this.weekDelta,
    required this.monthDelta,
    required this.yearDelta,
    required this.startDate,
    required this.lastActiveDate,
    required this.estimatedCompletion,
    required this.avgPerActiveDay,
    required this.recentDailyRate,
    required this.threadStats,
    required this.dailyData,
    required this.cumulativeData,
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

  // ── Per-thread stats ─────────────────────────────────────────────────────
  final threadCells = <String, Set<(int, int)>>{};
  for (final s in pattern.stitches) {
    if (s is BackStitch) continue;
    final xy = _stitchXY(s);
    if (xy == null) continue;
    threadCells.putIfAbsent(s.threadId, () => {}).add(xy);
  }
  final threadStats = pattern.threads.map((t) {
    final cells = threadCells[t.dmcCode] ?? {};
    final done =
        cells.where((c) => progress.completedStitches.contains(c)).length;
    return _ThreadStats(thread: t, total: cells.length, done: done);
  }).where((ts) => ts.total > 0).toList()
    ..sort((a, b) => b.total.compareTo(a.total));

  // ── Log-derived delta stats ──────────────────────────────────────────────
  final today = DateTime.now();
  final todayIso = todayIsoDate();

  // Build a map of date → stitches for that day.
  // Daily stitches = entry[i].stitchCount - entry[i-1].stitchCount (or entry[0].stitchCount).
  int prevCount = 0;
  final dailyMap = <String, int>{};
  for (final entry in log) {
    final delta = max(0, entry.stitchCount - prevCount);
    dailyMap[entry.isoDate] = delta;
    prevCount = entry.stitchCount;
  }

  int _sumDays(int days) {
    int sum = 0;
    for (int i = 0; i < days; i++) {
      final d = today.subtract(Duration(days: i));
      final iso =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      sum += dailyMap[iso] ?? 0;
    }
    return sum;
  }

  final todayDelta = dailyMap[todayIso] ?? 0;
  final weekDelta = _sumDays(7);
  final monthDelta = _sumDays(30);
  final yearDelta = _sumDays(365);

  // ── Start / last active ──────────────────────────────────────────────────
  final startDate = log.isNotEmpty ? parseIsoDate(log.first.isoDate) : null;
  final lastActiveDate =
      log.isNotEmpty ? parseIsoDate(log.last.isoDate) : null;

  // ── Average rates ────────────────────────────────────────────────────────
  final activeDays =
      dailyMap.values.where((v) => v > 0).length;
  final totalDone = progress.completedStitches.length;
  final avgPerActiveDay =
      activeDays == 0 ? 0.0 : totalDone / activeDays;

  // Recent rate: sum of last 14 days divided by 14 (includes zero days).
  final recentTotal = _sumDays(14);
  final recentDailyRate = recentTotal / 14.0;

  // ── Estimated completion ─────────────────────────────────────────────────
  DateTime? estimatedCompletion;
  final remaining = totalStitches - totalDone;
  if (recentDailyRate > 0 && remaining > 0) {
    final daysLeft = (remaining / recentDailyRate).ceil();
    estimatedCompletion = today.add(Duration(days: daysLeft));
  }

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

  return _StitchOpsStats(
    totalStitches: totalStitches,
    totalBackstitches: totalBackstitches,
    completedStitches: totalDone,
    completedBackstitches: progress.completedBackstitches.length,
    todayDelta: todayDelta,
    weekDelta: weekDelta,
    monthDelta: monthDelta,
    yearDelta: yearDelta,
    startDate: startDate,
    lastActiveDate: lastActiveDate,
    estimatedCompletion: estimatedCompletion,
    avgPerActiveDay: avgPerActiveDay,
    recentDailyRate: recentDailyRate,
    threadStats: threadStats,
    dailyData: dailyData,
    cumulativeData: cumulativeData,
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

class StitchOpsScreen extends StatelessWidget {
  final CrossStitchPattern pattern;
  const StitchOpsScreen({super.key, required this.pattern});

  @override
  Widget build(BuildContext context) {
    final stats = _computeStats(pattern);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('StitchOps', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              pattern.name,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        leading: Navigator.canPop(context)
            ? const CloseButton()
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _OverviewSection(stats: stats, colorScheme: colorScheme),
          const SizedBox(height: 20),
          _RateSection(stats: stats, colorScheme: colorScheme),
          const SizedBox(height: 20),
          if (stats.dailyData.any((d) => d.$2 > 0)) ...[
            _DailyBarChart(dailyData: stats.dailyData, colorScheme: colorScheme),
            const SizedBox(height: 20),
          ],
          if (stats.cumulativeData.length >= 2) ...[
            _CumulativeLineChart(
              cumulativeData: stats.cumulativeData,
              total: stats.totalStitches,
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 20),
          ],
          if (stats.threadStats.isNotEmpty) ...[
            _ThreadBreakdownSection(
                stats: stats, colorScheme: colorScheme),
            const SizedBox(height: 20),
          ],
          if (stats.startDate == null)
            _NoDataCard(colorScheme: colorScheme),
        ],
      ),
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
                label: 'Completed',
                value: _fmt(stats.completedStitches),
                color: colorScheme.primary,
              ),
              const SizedBox(width: 12),
              _StatTile(
                label: 'Total',
                value: _fmt(stats.totalStitches),
                color: colorScheme.secondary,
              ),
              const SizedBox(width: 12),
              _StatTile(
                label: 'Remaining',
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
                    minHeight: 12,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(colorScheme.primary),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 48,
                child: Text(
                  pctStr,
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: colorScheme.primary),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          if (stats.totalBackstitches > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Backstitches: ${_fmt(stats.completedBackstitches)} / ${_fmt(stats.totalBackstitches)}',
              style: TextStyle(
                  fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ],
          if (stats.startDate != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _dateChip(context, 'Started', stats.startDate!),
                const SizedBox(width: 8),
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
      label: Text(
        '$label: ${_shortDate(date)}',
        style: const TextStyle(fontSize: 12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
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
          Row(
            children: [
              _StatTile(
                  label: 'Today', value: _fmt(stats.todayDelta), color: colorScheme.primary),
              const SizedBox(width: 12),
              _StatTile(
                  label: 'This week', value: _fmt(stats.weekDelta), color: colorScheme.secondary),
              const SizedBox(width: 12),
              _StatTile(
                  label: 'This month', value: _fmt(stats.monthDelta), color: colorScheme.tertiary),
              const SizedBox(width: 12),
              _StatTile(
                  label: 'This year', value: _fmt(stats.yearDelta), color: colorScheme.outline),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: colorScheme.outlineVariant),
          const SizedBox(height: 8),
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
                  label: 'Recent rate (14d)',
                  value: stats.recentDailyRate.toStringAsFixed(1) + '/day',
                ),
              ),
            ],
          ),
          if (stats.estimatedCompletion != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha:0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.flag_outlined,
                      size: 18, color: colorScheme.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Estimated completion: ${_longDate(stats.estimatedCompletion!)}',
                      style: TextStyle(
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha:0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 18, color: colorScheme.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Text(
                    'Pattern complete!',
                    style: TextStyle(
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
            style: const TextStyle(fontSize: 11),
            overflow: TextOverflow.ellipsis),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      ],
    );
  }
}

// ─── Daily bar chart ──────────────────────────────────────────────────────────

class _DailyBarChart extends StatelessWidget {
  final List<(DateTime, int)> dailyData;
  final ColorScheme colorScheme;
  const _DailyBarChart({required this.dailyData, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader('Daily stitches (last 60 days)'),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: CustomPaint(
              painter: _BarChartPainter(
                data: dailyData,
                barColor: colorScheme.primary,
                axisColor: colorScheme.outlineVariant,
                labelColor: colorScheme.onSurfaceVariant,
              ),
              size: Size.infinite,
            ),
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

  const _BarChartPainter({
    required this.data,
    required this.barColor,
    required this.axisColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final maxVal = data.map((d) => d.$2).fold(0, max);
    if (maxVal == 0) return;

    const labelHeight = 16.0;
    const topPad = 4.0;
    final chartHeight = size.height - labelHeight - topPad;
    final barWidth = size.width / data.length;
    const barGap = 1.0;

    final barPaint = Paint()..color = barColor;
    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1;
    final todayPaint = Paint()..color = barColor.withValues(alpha:0.35);

    final today = DateTime.now();

    for (int i = 0; i < data.length; i++) {
      final (date, count) = data[i];
      final isToday = date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      final x = i * barWidth;
      if (count > 0) {
        final barH = (count / maxVal) * chartHeight;
        final rect = Rect.fromLTWH(
          x + barGap / 2,
          topPad + chartHeight - barH,
          barWidth - barGap,
          barH,
        );
        canvas.drawRect(rect, isToday ? todayPaint : barPaint);
        if (isToday) {
          canvas.drawRect(rect,
              Paint()..color = barColor..style = PaintingStyle.stroke..strokeWidth = 1.5);
        }
      }
    }

    // Baseline
    canvas.drawLine(
      Offset(0, topPad + chartHeight),
      Offset(size.width, topPad + chartHeight),
      axisPaint,
    );

    // Month labels — one label per month at the first bar of that month
    final tp = TextPainter(textDirection: TextDirection.ltr);
    String? prevMonth;
    for (int i = 0; i < data.length; i++) {
      final (date, _) = data[i];
      final monthKey =
          '${date.year}-${date.month.toString().padLeft(2, '0')}';
      if (monthKey != prevMonth) {
        prevMonth = monthKey;
        tp.text = TextSpan(
          text: _monthAbbr(date.month),
          style: TextStyle(color: labelColor, fontSize: 10),
        );
        tp.layout();
        tp.paint(canvas, Offset(i * barWidth, topPad + chartHeight + 3));
      }
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter old) =>
      old.data != data || old.barColor != barColor;
}

// ─── Cumulative line chart ────────────────────────────────────────────────────

class _CumulativeLineChart extends StatelessWidget {
  final List<(DateTime, int)> cumulativeData;
  final int total;
  final ColorScheme colorScheme;
  const _CumulativeLineChart({
    required this.cumulativeData,
    required this.total,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader('Cumulative progress'),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: CustomPaint(
              painter: _LineChartPainter(
                data: cumulativeData,
                total: total,
                lineColor: colorScheme.primary,
                targetColor: colorScheme.outlineVariant,
                fillColor: colorScheme.primary.withValues(alpha:0.12),
                labelColor: colorScheme.onSurfaceVariant,
              ),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<(DateTime, int)> data;
  final int total;
  final Color lineColor;
  final Color targetColor;
  final Color fillColor;
  final Color labelColor;

  const _LineChartPainter({
    required this.data,
    required this.total,
    required this.lineColor,
    required this.targetColor,
    required this.fillColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final maxVal = total > 0 ? total.toDouble() : data.last.$2.toDouble();
    if (maxVal == 0) return;

    const labelHeight = 16.0;
    const topPad = 4.0;
    final chartH = size.height - labelHeight - topPad;

    final startDate = data.first.$1;
    final endDate = data.last.$1;
    final totalDays =
        endDate.difference(startDate).inDays.toDouble().clamp(1.0, double.infinity);

    Offset toOffset((DateTime, int) point) {
      final dayOffset = point.$1.difference(startDate).inDays;
      final x = (dayOffset / totalDays) * size.width;
      final y = topPad + chartH - (point.$2 / maxVal) * chartH;
      return Offset(x, y);
    }

    // Filled area
    final fillPath = Path();
    fillPath.moveTo(0, topPad + chartH);
    for (final point in data) {
      final o = toOffset(point);
      fillPath.lineTo(o.dx, o.dy);
    }
    fillPath.lineTo(toOffset(data.last).dx, topPad + chartH);
    fillPath.close();
    canvas.drawPath(fillPath, Paint()..color = fillColor);

    // Line
    final linePath = Path();
    final first = toOffset(data.first);
    linePath.moveTo(first.dx, first.dy);
    for (int i = 1; i < data.length; i++) {
      final o = toOffset(data[i]);
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

    // Target line (total)
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

    // Baseline
    canvas.drawLine(
      Offset(0, topPad + chartH),
      Offset(size.width, topPad + chartH),
      Paint()..color = targetColor..strokeWidth = 1,
    );

    // Year / month labels
    final tp = TextPainter(textDirection: TextDirection.ltr);
    String? prevLabel;
    for (final (date, _) in data) {
      final dayOffset = date.difference(startDate).inDays;
      final x = (dayOffset / totalDays) * size.width;
      String label;
      if (totalDays > 180) {
        label = '${date.year}';
      } else {
        label = _monthAbbr(date.month);
      }
      if (label != prevLabel) {
        prevLabel = label;
        tp.text = TextSpan(
            text: label, style: TextStyle(color: labelColor, fontSize: 10));
        tp.layout();
        tp.paint(canvas, Offset(x, topPad + chartH + 3));
      }
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.data != data || old.total != total;
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
          _SectionHeader('Thread breakdown'),
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
    final pct = ts.pct;
    final isDone = ts.done >= ts.total;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: ts.thread.color,
              border: Border.all(
                  color: colorScheme.outline.withValues(alpha:0.4), width: 1),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              'DMC ${ts.thread.dmcCode} ${ts.thread.name}',
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 6,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isDone ? colorScheme.secondary : colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Text(
              '${_fmt(ts.done)}/${_fmt(ts.total)}',
              style: TextStyle(
                fontSize: 11,
                color: isDone
                    ? colorScheme.secondary
                    : colorScheme.onSurfaceVariant,
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
                size: 48, color: colorScheme.outlineVariant),
            const SizedBox(height: 12),
            Text(
              'No stitching history yet',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              'Switch to Stitch mode and start marking\nstitches done to track your progress here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
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
        padding: const EdgeInsets.all(16),
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
        fontSize: 11,
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
                  fontSize: 20,
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

// ─── Formatting helpers ───────────────────────────────────────────────────────

String _fmt(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return n.toString();
}

String _shortDate(DateTime d) =>
    '${d.day} ${_monthAbbr(d.month)} ${d.year}';

String _longDate(DateTime d) =>
    '${d.day} ${_monthName(d.month)} ${d.year}';

String _monthAbbr(int m) => const [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ][m - 1];

String _monthName(int m) => const [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ][m - 1];
