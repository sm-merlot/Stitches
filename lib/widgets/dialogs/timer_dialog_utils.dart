/// Shared formatting helpers for timer dialogs.
library;

/// "1h 23m 45s" / "23m 45s" / "45s"
String fmtDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m}m ${s}s';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

/// "2:15 PM"
String fmtClock(DateTime dt) {
  final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final m = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour < 12 ? 'AM' : 'PM';
  return '$h:$m $period';
}

/// "Last activity: 2:15 PM — 47m ago" (null-safe)
String fmtLastActivity(DateTime? lastAt, DateTime now) {
  if (lastAt == null) return '';
  return 'Last activity: ${fmtClock(lastAt)} — ${fmtDuration(now.difference(lastAt))} ago';
}
