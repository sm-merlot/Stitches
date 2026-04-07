# Home Screen & Storage Uplift — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate home screen open actions into a single Open… button, add pattern thumbnail previews to recent items, and introduce a pinned Home storage shortcut on mobile backed by the app's sandboxed documents directory.

**Architecture:** New `ThumbnailCache` service stores PNG thumbnails keyed by file path (base64) or Drive fileId. `RecentItem` gains a `thumbnailKey` field. The home screen is rearchitected with a unified header, optional `_HomeItem` (mobile-only), flattened mixed recents, and a new `_OpenModal` bottom sheet/dialog replacing the current button grid. Thumbnail generation is hooked into every file-open flow (home screen + workspace screen).

**Tech Stack:** Flutter/Dart, Riverpod (Notifier pattern), `path_provider` (`getApplicationDocumentsDirectory`, `getApplicationSupportDirectory`), `dart:ui` (PictureRecorder for PNG rendering), `shared_preferences`.

**User Verification:** NO — this is a UI/UX uplift; correctness is verifiable by running the app.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/services/thumbnail_cache.dart` | Create | Store/load/remove/prune PNG thumbnails on disk |
| `lib/services/pattern_thumbnail.dart` | Create | Render a `CrossStitchPattern` to a PNG `Uint8List` |
| `lib/providers/recent_items_provider.dart` | Modify | Add `thumbnailKey` to `RecentItem`; update `add()` signature; suppress home folder |
| `lib/screens/home_screen.dart` | Modify | New layout; Open modal trigger; HOME item; mixed recents; mobile new-pattern flow |
| `lib/screens/home_screen_widgets.dart` | Modify | New widgets: `_OpenModal`, `_HomeItem`, `_RecentItemTile` with thumbnails; remove `_RecentSection` |
| `lib/screens/workspace_screen.dart` | Modify | Generate thumbnail after `_openNativeFile`; background thumbnail refresh |

---

## Task 0: Create feature branch

**Goal:** All implementation work happens on a branch from `scme0/feature/share-export-redesign`.

**Files:** none

**Acceptance Criteria:**
- [ ] New branch exists and is checked out
- [ ] Branch is based on `scme0/feature/share-export-redesign`

**Verify:** `git log --oneline -1` shows a commit from the share/export redesign branch.

**Steps:**

- [ ] **Step 1: Create and check out the branch**

```bash
git fetch origin
git checkout scme0/feature/share-export-redesign
git checkout -b scme0/feature/home-storage-uplift
```

Expected: `Switched to a new branch 'scme0/feature/home-storage-uplift'`

- [ ] **Step 2: Verify**

```bash
git log --oneline -3
```

Expected: top commit is from the share/export redesign branch.

```json:metadata
{"files": [], "verifyCommand": "git log --oneline -3", "acceptanceCriteria": ["branch exists and is based on share-export-redesign"], "requiresUserVerification": false}
```

---

## Task 1: ThumbnailCache service

**Goal:** Persistent on-disk PNG cache for pattern thumbnails, keyed by a stable string identifier.

**Files:**
- Create: `lib/services/thumbnail_cache.dart`

**Acceptance Criteria:**
- [ ] `ThumbnailCache.store(key, bytes)` writes a PNG file to `getApplicationSupportDirectory()/thumbnails/`
- [ ] `ThumbnailCache.load(key)` returns bytes or null if not cached
- [ ] `ThumbnailCache.remove(key)` deletes the cached file
- [ ] `ThumbnailCache.pruneLocal(paths)` removes entries for local paths that no longer exist
- [ ] `localThumbnailKey(path)` encodes a local path to a safe filename-friendly string
- [ ] `driveThumbnailKey(fileId)` returns the fileId as-is (already filename-safe)

**Verify:** `flutter analyze lib/services/thumbnail_cache.dart` → no issues.

**Steps:**

- [ ] **Step 1: Create `lib/services/thumbnail_cache.dart`**

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// Stable thumbnail key for a local file path.
/// URL-safe base64 of the UTF-8 path bytes — filename-safe, reversible.
String localThumbnailKey(String path) =>
    base64Url.encode(utf8.encode(path));

/// Stable thumbnail key for a Google Drive file.
/// The fileId is already alphanumeric, no encoding needed.
String driveThumbnailKey(String fileId) => fileId;

class ThumbnailCache {
  static Directory? _dir;

  static Future<Directory> _thumbnailDir() async {
    if (_dir != null) return _dir!;
    final support = await getApplicationSupportDirectory();
    _dir = Directory('${support.path}/thumbnails');
    await _dir!.create(recursive: true);
    return _dir!;
  }

  // Encode key → safe filename (replace '=' padding with '_').
  static String _filename(String key) =>
      key.replaceAll('/', '-').replaceAll('+', '_').replaceAll('=', '');

  /// Write [pngBytes] to cache under [key].
  static Future<void> store(String key, Uint8List pngBytes) async {
    final dir = await _thumbnailDir();
    await File('${dir.path}/${_filename(key)}.png').writeAsBytes(pngBytes);
  }

  /// Return cached bytes for [key], or null if not present.
  static Future<Uint8List?> load(String key) async {
    final dir = await _thumbnailDir();
    final file = File('${dir.path}/${_filename(key)}.png');
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  /// Delete the cached entry for [key] (no-op if absent).
  static Future<void> remove(String key) async {
    final dir = await _thumbnailDir();
    final file = File('${dir.path}/${_filename(key)}.png');
    if (await file.exists()) await file.delete();
  }

  /// Delete thumbnail entries for local paths that no longer exist on disk.
  /// [localPaths] is the set of all local file paths tracked in recents.
  static Future<void> pruneLocal(Iterable<String> localPaths) async {
    for (final path in localPaths) {
      if (!File(path).existsSync()) {
        await remove(localThumbnailKey(path));
      }
    }
  }
}
```

- [ ] **Step 2: Analyse**

```bash
export PATH="/opt/homebrew/bin:$PATH" && flutter analyze lib/services/thumbnail_cache.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/services/thumbnail_cache.dart
git commit -m "feat: add ThumbnailCache service for pattern thumbnail persistence"
```

```json:metadata
{"files": ["lib/services/thumbnail_cache.dart"], "verifyCommand": "flutter analyze lib/services/thumbnail_cache.dart", "acceptanceCriteria": ["store/load/remove/pruneLocal all implemented", "no analysis issues"], "requiresUserVerification": false}
```

---

## Task 2: PatternThumbnail renderer

**Goal:** Render a `CrossStitchPattern` to a 160×110 PNG `Uint8List` using `dart:ui`.

**Files:**
- Create: `lib/services/pattern_thumbnail.dart`

**Acceptance Criteria:**
- [ ] `generatePatternThumbnail(pattern)` returns a non-null `Uint8List` for any non-empty pattern
- [ ] Empty pattern (no stitches) returns bytes for a plain white/aida-coloured rectangle
- [ ] Returns null on any rendering error without throwing
- [ ] No analysis issues

**Verify:** `flutter analyze lib/services/pattern_thumbnail.dart` → no issues.

**Steps:**

- [ ] **Step 1: Create `lib/services/pattern_thumbnail.dart`**

The renderer works identically to `_SnippetThumbnailPainter` but operates on `CrossStitchPattern` (with layers, not a single stitch list). It walks all layer stitches. It runs on the main isolate — `toImage()` is async so it doesn't block the UI thread.

```dart
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/pattern.dart';
import '../models/stitch.dart';

const _kThumbW = 160;
const _kThumbH = 110;

/// Render [pattern] to a [_kThumbW]×[_kThumbH] PNG.
/// Returns null if rendering fails.
Future<Uint8List?> generatePatternThumbnail(CrossStitchPattern pattern) async {
  try {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder,
        Rect.fromLTWH(0, 0, _kThumbW.toDouble(), _kThumbH.toDouble()));

    // White background.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, _kThumbW.toDouble(), _kThumbH.toDouble()),
      Paint()..color = Colors.white,
    );

    if (pattern.width > 0 && pattern.height > 0) {
      final cellW = _kThumbW / pattern.width;
      final cellH = _kThumbH / pattern.height;
      final paint = Paint()..style = PaintingStyle.fill;

      // Collect all stitches from all visible layers.
      for (final layer in pattern.layers) {
        if (!layer.visible) continue;
        for (final item in layer.items) {
          final thread = pattern.threads.firstWhere(
            (t) => t.id == item.threadId,
            orElse: () => pattern.threads.first,
          );
          paint.color = thread.color;
          _paintStitch(canvas, item.stitch, cellW, cellH, paint);
        }
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(_kThumbW, _kThumbH);
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return byteData?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

void _paintStitch(
    Canvas canvas, Stitch stitch, double cellW, double cellH, Paint paint) {
  switch (stitch) {
    case FullStitch(:final x, :final y):
      canvas.drawRect(
          Rect.fromLTWH(x * cellW, y * cellH, cellW, cellH), paint);
    case HalfStitch(:final x, :final y):
      canvas.drawRect(
          Rect.fromLTWH(x * cellW, y * cellH, cellW, cellH), paint);
    case QuarterStitch(:final x, :final y):
      canvas.drawRect(
          Rect.fromLTWH(
              x * cellW + cellW * 0.25, y * cellH + cellH * 0.25,
              cellW * 0.5, cellH * 0.5),
          paint);
    case HalfCrossStitch(:final x, :final y):
      canvas.drawRect(
          Rect.fromLTWH(x * cellW, y * cellH, cellW, cellH), paint);
    case QuarterCrossStitch(:final x, :final y):
      canvas.drawRect(
          Rect.fromLTWH(
              x * cellW + cellW * 0.25, y * cellH + cellH * 0.25,
              cellW * 0.5, cellH * 0.5),
          paint);
    case BackStitch(:final x1, :final y1, :final x2, :final y2):
      canvas.drawLine(
        Offset(x1 * cellW, y1 * cellH),
        Offset(x2 * cellW, y2 * cellH),
        Paint()
          ..color = paint.color
          ..strokeWidth = (cellW * 0.2).clamp(0.5, 2.0)
          ..style = PaintingStyle.stroke,
      );
  }
}
```

- [ ] **Step 2: Check the pattern model's layer/item structure**

`CrossStitchPattern.layers` is `List<Layer>`. Each `Layer` has a `List<LayerItem>` (via `layer.items`), and each `LayerItem` has a `Stitch stitch` and `String threadId`. Verify by reading `lib/models/layer.dart` and `lib/models/layer_item.dart` — adjust field names in the code above if they differ.

- [ ] **Step 3: Analyse**

```bash
export PATH="/opt/homebrew/bin:$PATH" && flutter analyze lib/services/pattern_thumbnail.dart
```

Fix any field name mismatches found in Step 2.

- [ ] **Step 4: Commit**

```bash
git add lib/services/pattern_thumbnail.dart
git commit -m "feat: add pattern thumbnail PNG renderer"
```

```json:metadata
{"files": ["lib/services/pattern_thumbnail.dart"], "verifyCommand": "flutter analyze lib/services/pattern_thumbnail.dart", "acceptanceCriteria": ["generatePatternThumbnail returns Uint8List for any pattern", "no analysis issues"], "requiresUserVerification": false}
```

---

## Task 3: RecentItem — add thumbnailKey, update add(), add isMobile + isHomeFolder helpers

**Goal:** `RecentItem` carries an optional `thumbnailKey`; `RecentItemsNotifier.add()` accepts it; home-folder items are suppressed from recents on mobile.

**Files:**
- Modify: `lib/providers/recent_items_provider.dart`

**Acceptance Criteria:**
- [ ] `RecentItem.thumbnailKey` field exists (nullable `String?`)
- [ ] `RecentItem.toJson()` / `fromJson()` round-trips `thumbnailKey` (omitted when null — backward-compatible)
- [ ] `recentItemsProvider.notifier.add()` has optional `thumbnailKey` parameter
- [ ] `isHomeFolderPath(path)` returns true for `getApplicationDocumentsDirectory()` path on mobile, always false on desktop
- [ ] Adding a recent item whose `id` equals the home folder path is a no-op on mobile
- [ ] No analysis issues

**Verify:** `flutter analyze lib/providers/recent_items_provider.dart` → no issues.

**Steps:**

- [ ] **Step 1: Add `thumbnailKey` to `RecentItem`**

In `lib/providers/recent_items_provider.dart`, add the field to the class and update the constructor, `toJson`, `fromJson`:

```dart
class RecentItem {
  final String id;
  final bool isFolder;
  final bool isDrive;
  final String? driveEmail;
  final String? driveName;
  final String? drivePath;
  final DateTime lastOpened;
  /// Cache key for the pattern thumbnail (see ThumbnailCache).
  final String? thumbnailKey;

  const RecentItem({
    required this.id,
    required this.isFolder,
    required this.lastOpened,
    this.isDrive = false,
    this.driveEmail,
    this.driveName,
    this.drivePath,
    this.thumbnailKey,
  });

  // ... existing displayName / displayPath / relativeTime getters unchanged ...

  Map<String, dynamic> toJson() => {
        'id': id,
        'isFolder': isFolder,
        'isDrive': isDrive,
        if (driveEmail != null) 'driveEmail': driveEmail,
        if (driveName != null) 'driveName': driveName,
        if (drivePath != null) 'drivePath': drivePath,
        'lastOpened': lastOpened.millisecondsSinceEpoch,
        if (thumbnailKey != null) 'thumbnailKey': thumbnailKey,
      };

  factory RecentItem.fromJson(Map<String, dynamic> json) => RecentItem(
        id: (json['id'] ?? json['path']) as String,
        isFolder: json['isFolder'] as bool,
        lastOpened:
            DateTime.fromMillisecondsSinceEpoch(json['lastOpened'] as int),
        isDrive: json['isDrive'] as bool? ?? false,
        driveEmail: json['driveEmail'] as String?,
        driveName: json['driveName'] as String?,
        drivePath: json['drivePath'] as String?,
        thumbnailKey: json['thumbnailKey'] as String?,
      );
}
```

- [ ] **Step 2: Add `isHomeFolderPath` helper and update `add()`**

Add a top-level helper and update `RecentItemsNotifier`:

```dart
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

/// Returns true on iOS/Android when [path] is the app's documents directory.
Future<bool> isHomeFolderPath(String path) async {
  if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return false;
  final home = await getApplicationDocumentsDirectory();
  return path == home.path;
}
```

Update `RecentItemsNotifier.add()`:

```dart
Future<void> add(
  String id, {
  required bool isFolder,
  bool isDrive = false,
  String? driveEmail,
  String? driveName,
  String? drivePath,
  String? thumbnailKey,          // ← new
}) async {
  // Suppress the home folder from appearing in recents on mobile.
  if (isFolder && !isDrive && await isHomeFolderPath(id)) return;

  final item = RecentItem(
    id: id,
    isFolder: isFolder,
    lastOpened: DateTime.now(),
    isDrive: isDrive,
    driveEmail: driveEmail,
    driveName: driveName,
    drivePath: drivePath,
    thumbnailKey: thumbnailKey,
  );
  var updated = [item, ...state.where((e) => e.id != id)];
  if (updated.length > _maxItems) updated = updated.sublist(0, _maxItems);
  state = updated;
  await _save();
}
```

- [ ] **Step 3: Add `pruneDeletedFiles()` to the notifier**

Called by home screen on load to remove stale local-file entries:

```dart
/// Remove recent items for local files/folders that no longer exist,
/// and prune their thumbnail cache entries.
Future<void> pruneDeletedFiles() async {
  final toRemove = <RecentItem>[];
  for (final item in state) {
    if (item.isDrive) continue;
    if (!FileSystemEntity.typeSync(item.id).isNotEmpty) {
      // File or folder is gone.
      toRemove.add(item);
      if (item.thumbnailKey != null) {
        await ThumbnailCache.remove(item.thumbnailKey!);
      }
    }
  }
  if (toRemove.isEmpty) return;
  state = state.where((e) => !toRemove.contains(e)).toList();
  await _save();
}
```

Add the import for `ThumbnailCache` at the top of the file:
```dart
import '../services/thumbnail_cache.dart';
```

- [ ] **Step 4: Fix `FileSystemEntity.typeSync` idiom**

`FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound` is the correct not-found check. Use:

```dart
if (FileSystemEntity.typeSync(item.id) == FileSystemEntityType.notFound) {
```

- [ ] **Step 5: Analyse**

```bash
export PATH="/opt/homebrew/bin:$PATH" && flutter analyze lib/providers/recent_items_provider.dart
```

- [ ] **Step 6: Commit**

```bash
git add lib/providers/recent_items_provider.dart
git commit -m "feat: add thumbnailKey to RecentItem, suppress home folder from recents"
```

```json:metadata
{"files": ["lib/providers/recent_items_provider.dart"], "verifyCommand": "flutter analyze lib/providers/recent_items_provider.dart", "acceptanceCriteria": ["thumbnailKey field added", "add() accepts thumbnailKey", "home folder suppressed from recents on mobile", "pruneDeletedFiles() implemented"], "requiresUserVerification": false}
```

---

## Task 4: Thumbnail generation on file open (home screen)

**Goal:** Every time a pattern file is opened from the home screen, generate its thumbnail and cache it; pass the key to `recentItemsProvider.add()`.

**Files:**
- Modify: `lib/screens/home_screen.dart`

**Acceptance Criteria:**
- [ ] After opening a local file, thumbnail is generated and stored; `add()` called with `thumbnailKey`
- [ ] After opening a Drive file, thumbnail is generated and stored using `driveThumbnailKey(fileId)`; `add()` called with `thumbnailKey`
- [ ] Opening a recent file similarly generates/stores thumbnail
- [ ] `pruneDeletedFiles()` is called in `initState` (via `addPostFrameCallback`)
- [ ] No analysis issues

**Verify:** `flutter analyze lib/screens/home_screen.dart` → no issues.

**Steps:**

- [ ] **Step 1: Add imports to `home_screen.dart`**

```dart
import '../services/thumbnail_cache.dart';
import '../services/pattern_thumbnail.dart';
```

- [ ] **Step 2: Add `_generateAndCacheThumbnail` helper method**

```dart
/// Generate a thumbnail for [pattern] and store it under [key].
/// Fire-and-forget — called unawaited after navigation.
static Future<void> _generateAndCacheThumbnail(
    CrossStitchPattern pattern, String key) async {
  final bytes = await generatePatternThumbnail(pattern);
  if (bytes != null) await ThumbnailCache.store(key, bytes);
}
```

- [ ] **Step 3: Call `pruneDeletedFiles()` in `initState`**

In `_HomeScreenState.initState`, add after the existing `addPostFrameCallback` block:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  ref.read(recentItemsProvider.notifier).pruneDeletedFiles();
});
```

- [ ] **Step 4: Update `_openFile()`**

After `ref.read(recentItemsProvider.notifier).add(path, isFolder: false)`, also generate thumbnail and re-add with key:

```dart
Future<void> _openFile() async {
  try {
    final result = await FileService.openFile();
    if (result == null || !mounted) return;
    final (pattern, path, wasCompressed) = result;
    final session = await EditorSessionService.load('local:$path');
    if (!mounted) return;
    ref.read(editorProvider.notifier).loadPattern(pattern,
        filePath: path, compressOnSave: wasCompressed, session: session);
    final key = localThumbnailKey(path);
    ref.read(recentItemsProvider.notifier).add(path,
        isFolder: false, thumbnailKey: key);
    unawaited(_generateAndCacheThumbnail(pattern, key));
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const EditorScreen()),
    );
  } catch (e) {
    if (!mounted) return;
    showError(context, 'Could not open file: $e');
  }
}
```

- [ ] **Step 5: Update `_openDriveFile()`**

After the existing `addToRecents()` call pattern, also cache a thumbnail. The key is `driveThumbnailKey(selection.fileId)`. In both the cache-hit and no-cache branches, after `loadPattern`:

```dart
final thumbKey = driveThumbnailKey(selection.fileId);
unawaited(_generateAndCacheThumbnail(pattern, thumbKey));
// Update the recent item with the thumbnail key:
unawaited(ref.read(recentItemsProvider.notifier).add(
  selection.fileId,
  isFolder: false,
  isDrive: true,
  driveName: selection.fileName,
  driveEmail: ref.read(googleDriveProvider).email,
  drivePath: selection.drivePath,
  thumbnailKey: thumbKey,
));
```

Remove the previous `addToRecents()` local helper and inline this.

- [ ] **Step 6: Update `_openFromIncomingPath()`**

After `ref.read(recentItemsProvider.notifier).add(resolvedPath, isFolder: false)`:

```dart
final key = localThumbnailKey(resolvedPath);
ref.read(recentItemsProvider.notifier).add(resolvedPath,
    isFolder: false, thumbnailKey: key);
unawaited(_generateAndCacheThumbnail(pattern, key));
```

- [ ] **Step 7: Update `_openRecentFile()`**

For local items, after `loadPattern`:
```dart
final key = localThumbnailKey(item.id);
unawaited(_generateAndCacheThumbnail(pattern, key));
// Re-add to bump lastOpened and ensure thumbnailKey is set.
ref.read(recentItemsProvider.notifier).add(item.id,
    isFolder: false, thumbnailKey: key);
```

For Drive items, similarly with `driveThumbnailKey(item.id)` and Drive metadata from `item`.

- [ ] **Step 8: Analyse**

```bash
export PATH="/opt/homebrew/bin:$PATH" && flutter analyze lib/screens/home_screen.dart
```

- [ ] **Step 9: Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: generate and cache pattern thumbnails on file open"
```

```json:metadata
{"files": ["lib/screens/home_screen.dart"], "verifyCommand": "flutter analyze lib/screens/home_screen.dart", "acceptanceCriteria": ["thumbnail generated on every file open path", "pruneDeletedFiles called on init", "no analysis issues"], "requiresUserVerification": false}
```

---

## Task 5: Home screen — new layout, _HomeItem, mixed recents with thumbnails

**Goal:** Rebuild the home screen UI: centered header (same on mobile+desktop), pinned HOME item (mobile only), flat mixed recents list with thumbnail previews.

**Files:**
- Modify: `lib/screens/home_screen.dart` (build method)
- Modify: `lib/screens/home_screen_widgets.dart` (replace `_RecentSection` + `_RecentItemTile`, add `_HomeItem`, add `_ThumbnailStrip`)

**Acceptance Criteria:**
- [ ] Header: centered icon+name+subtitle; settings gear top-right; identical on mobile and desktop
- [ ] Action buttons: filled "New Pattern" + outlined "Open…" side-by-side; no other open buttons
- [ ] Mobile only: `_HomeItem` appears above RECENT separator; shows HOME badge, pattern count, thumbnail strip
- [ ] RECENT section: flat list ordered by `lastOpened` desc; no Files/Folders split
- [ ] Each recent item shows an 80×44 thumbnail: file → cached PNG grid; folder → up to 4 cached PNG strips from child files
- [ ] No analysis issues

**Verify:** `flutter analyze lib/screens/` → no issues.

**Steps:**

- [ ] **Step 1: Add `_isMobile` getter and `_homeFolderPath` future to `_HomeScreenState`**

```dart
bool get _isMobile =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

Future<String> get _homeFolderPath async =>
    (await getApplicationDocumentsDirectory()).path;
```

Add imports:
```dart
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
```

- [ ] **Step 2: Add `_homePatternCount` state and loader**

```dart
int _homePatternCount = 0;

Future<void> _loadHomePatternCount() async {
  if (!_isMobile) return;
  final dir = await getApplicationDocumentsDirectory();
  final count = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.stitches') || f.path.endsWith('.oxs'))
      .length;
  if (mounted) setState(() => _homePatternCount = count);
}
```

Call `_loadHomePatternCount()` in `initState` and when returning from `WorkspaceScreen`.

- [ ] **Step 3: Rewrite `build()` in `home_screen.dart`**

```dart
@override
Widget build(BuildContext context) {
  final recents = ref.watch(recentItemsProvider);
  final driveState = ref.watch(googleDriveProvider);
  final theme = Theme.of(context);

  // Flat chronological list — no grouping.
  final sortedRecents = [...recents]
    ..sort((a, b) => b.lastOpened.compareTo(a.lastOpened));

  return Stack(
    children: [
      Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          children: [
            const SizedBox(height: 32),
            // ── Centered header (same on all platforms) ─────────────────
            Center(
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.grid_4x4,
                        size: 28,
                        color: theme.colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 10),
                  Text('Stitches',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Cross-stitch pattern editor',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey.shade600)),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // ── Action buttons ──────────────────────────────────────────
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _loading ? null : _newPattern,
                        icon: const Icon(Icons.add),
                        label: const Text('New Pattern'),
                        style: FilledButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 16)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _showOpenModal,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('Open\u2026'),
                        style: OutlinedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 16)),
                      ),
                    ),
                  ]),

                  // ── HOME item (mobile only) ─────────────────────────
                  if (_isMobile) ...[
                    const SizedBox(height: 24),
                    _HomeItem(
                      patternCount: _homePatternCount,
                      recentFiles: sortedRecents
                          .where((r) => !r.isFolder)
                          .take(4)
                          .toList(),
                      onTap: _openHomeFolder,
                    ),
                  ],

                  // ── RECENT section ──────────────────────────────────
                  if (sortedRecents.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('RECENT',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                              letterSpacing: 1.1,
                            )),
                        TextButton(
                          onPressed: _clearRecents,
                          style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero),
                          child: Text('Clear',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ...sortedRecents.map((item) => _RecentItemTile(
                          item: item,
                          allRecents: sortedRecents,
                          onTap: _loading
                              ? null
                              : () => item.isFolder
                                  ? _openRecentFolder(item)
                                  : _openRecentFile(item),
                          onRemove: () => ref
                              .read(recentItemsProvider.notifier)
                              .remove(item.id),
                        )),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
      if (_loading)
        const Positioned.fill(
          child: AbsorbPointer(
            child: ColoredBox(
              color: Color(0x55000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
    ],
  );
}
```

- [ ] **Step 4: Add `_clearRecents()` and `_openHomeFolder()` methods**

```dart
void _clearRecents() async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Clear Recent'),
      content: const Text('Remove all items from the recent list?'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear')),
      ],
    ),
  );
  if (confirmed != true || !mounted) return;
  for (final item in [...ref.read(recentItemsProvider)]) {
    ref.read(recentItemsProvider.notifier).remove(item.id);
  }
}

Future<void> _openHomeFolder() async {
  final path = await _homeFolderPath;
  ref.read(workspaceProvider.notifier).openWorkspace(LocalFolder(path));
  if (!mounted) return;
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const WorkspaceScreen()),
  );
  _loadHomePatternCount(); // refresh count on return
  _ = result;
}
```

- [ ] **Step 5: Add `_HomeItem` widget to `home_screen_widgets.dart`**

```dart
class _HomeItem extends ConsumerWidget {
  final int patternCount;
  final List<RecentItem> recentFiles; // up to 4 recent file items for thumbnails
  final VoidCallback onTap;

  const _HomeItem({
    required this.patternCount,
    required this.recentFiles,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            // Thumbnail strip
            _FolderThumbnailStrip(
              thumbnailKeys:
                  recentFiles.map((r) => r.thumbnailKey).whereType<String>().toList(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'HOME',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onPrimary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    '$patternCount pattern${patternCount == 1 ? '' : 's'}',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Add `_FolderThumbnailStrip` and `_FileThumbnailBox` widgets**

```dart
/// 80×44 strip showing up to 4 cached thumbnails side-by-side.
class _FolderThumbnailStrip extends StatelessWidget {
  final List<String> thumbnailKeys; // max 4

  const _FolderThumbnailStrip({required this.thumbnailKeys});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (thumbnailKeys.isEmpty) {
      return Container(
        width: 80,
        height: 44,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.folder_outlined,
            size: 22, color: theme.colorScheme.onPrimaryContainer),
      );
    }
    final n = thumbnailKeys.length.clamp(1, 4);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 80,
        height: 44,
        child: Row(
          children: thumbnailKeys.take(n).map((key) {
            return Expanded(
              child: _CachedThumbnailSlice(thumbnailKey: key),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// Loads a cached thumbnail PNG from disk and displays it, cropped to its slot.
class _CachedThumbnailSlice extends StatefulWidget {
  final String thumbnailKey;
  const _CachedThumbnailSlice({required this.thumbnailKey});

  @override
  State<_CachedThumbnailSlice> createState() => _CachedThumbnailSliceState();
}

class _CachedThumbnailSliceState extends State<_CachedThumbnailSlice> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await ThumbnailCache.load(widget.thumbnailKey);
    if (mounted) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) {
      return Container(color: Theme.of(context).colorScheme.primaryContainer);
    }
    return Image.memory(
      _bytes!,
      fit: BoxFit.cover,
    );
  }
}

/// 80×44 box showing the full pattern thumbnail for a file recent item.
class _FileThumbnailBox extends StatefulWidget {
  final String? thumbnailKey;
  const _FileThumbnailBox({this.thumbnailKey});

  @override
  State<_FileThumbnailBox> createState() => _FileThumbnailBoxState();
}

class _FileThumbnailBoxState extends State<_FileThumbnailBox> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    if (widget.thumbnailKey != null) _load();
  }

  Future<void> _load() async {
    final bytes = await ThumbnailCache.load(widget.thumbnailKey!);
    if (mounted) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_bytes == null) {
      return Container(
        width: 80,
        height: 44,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.insert_drive_file_outlined,
          size: 20,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 80,
        height: 44,
        child: Image.memory(_bytes!, fit: BoxFit.cover),
      ),
    );
  }
}
```

- [ ] **Step 7: Rewrite `_RecentItemTile` to use thumbnails and accept `allRecents`**

Replace the existing `_RecentItemTile` in `home_screen_widgets.dart`:

```dart
class _RecentItemTile extends ConsumerWidget {
  final RecentItem item;
  final List<RecentItem> allRecents;
  final VoidCallback? onTap;
  final VoidCallback onRemove;

  const _RecentItemTile({
    required this.item,
    required this.allRecents,
    required this.onTap,
    required this.onRemove,
  });

  String? _driveWarning(DriveState driveState) {
    if (!item.isDrive) return null;
    if (driveState.status != DriveStatus.connected) {
      return 'Not signed in to Google Drive';
    }
    if (item.driveEmail != null &&
        driveState.email != null &&
        item.driveEmail != driveState.email) {
      return 'Not available — saved to ${item.driveEmail}';
    }
    return null;
  }

  /// For a folder item: collect thumbnailKeys from the 4 most-recent child files.
  List<String> _folderThumbnailKeys() {
    if (!item.isFolder || item.isDrive) return [];
    return allRecents
        .where((r) => !r.isFolder && !r.isDrive &&
            r.id.startsWith('${item.id}/') &&
            r.thumbnailKey != null)
        .take(4)
        .map((r) => r.thumbnailKey!)
        .toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final driveWarning = _driveWarning(ref.watch(googleDriveProvider));
    final effectiveOnTap = driveWarning != null ? null : onTap;

    Widget thumbnail;
    if (item.isFolder) {
      final keys = item.thumbnailKey != null
          ? [item.thumbnailKey!, ..._folderThumbnailKeys()]
          : _folderThumbnailKeys();
      thumbnail = _FolderThumbnailStrip(
          thumbnailKeys: keys.take(4).toList());
    } else {
      thumbnail = _FileThumbnailBox(thumbnailKey: item.thumbnailKey);
    }

    return Opacity(
      opacity: driveWarning != null ? 0.55 : 1.0,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
        leading: thumbnail,
        title: Text(
          item.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        subtitle: driveWarning != null
            ? Row(children: [
                Icon(Icons.warning_amber_outlined,
                    size: 11, color: Colors.orange.shade700),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(driveWarning,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: Colors.orange.shade700)),
                ),
              ])
            : Text(
                item.displayPath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade500)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(item.relativeTime,
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade400)),
            const SizedBox(width: 4),
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close,
                    size: 14, color: Colors.grey.shade400),
              ),
            ),
          ],
        ),
        onTap: effectiveOnTap,
      ),
    );
  }
}
```

- [ ] **Step 8: Add `Uint8List` import to `home_screen_widgets.dart`**

```dart
import 'dart:typed_data';
import '../services/thumbnail_cache.dart';
```

- [ ] **Step 9: Remove the old `_RecentSection` and `_SectionLabel` classes** (they are no longer used).

- [ ] **Step 10: Analyse**

```bash
export PATH="/opt/homebrew/bin:$PATH" && flutter analyze lib/screens/
```

Fix any issues. Common ones: `_SectionLabel` still referenced, missing imports.

- [ ] **Step 11: Commit**

```bash
git add lib/screens/home_screen.dart lib/screens/home_screen_widgets.dart
git commit -m "feat: rebuild home screen layout — centered header, HOME item, mixed recents with thumbnails"
```

```json:metadata
{"files": ["lib/screens/home_screen.dart", "lib/screens/home_screen_widgets.dart"], "verifyCommand": "flutter analyze lib/screens/", "acceptanceCriteria": ["centered header same on mobile and desktop", "HOME item appears only on mobile", "RECENT section flat/mixed", "thumbnails shown in recent items", "no analysis issues"], "requiresUserVerification": false}
```

---

## Task 6: Open… modal

**Goal:** Single `_OpenModal` widget (bottom sheet on mobile, dialog on desktop) replaces the current Local/Drive button grid. Tapping a source row reveals File/Folder sub-rows.

**Files:**
- Modify: `lib/screens/home_screen.dart` (add `_showOpenModal()`)
- Modify: `lib/screens/home_screen_widgets.dart` (add `_OpenModal` widget)

**Acceptance Criteria:**
- [ ] Tapping Open… on mobile shows a bottom sheet; on desktop shows a dialog
- [ ] Two source rows: Local and Google Drive (with connection status)
- [ ] Tapping a source row expands it to show "File" and "Folder" sub-rows; only one source expanded at a time
- [ ] Local File → `FileService.openFile()` → EditorScreen
- [ ] Local Folder → `FilePicker.platform.getDirectoryPath()` → WorkspaceScreen
- [ ] Drive File (connected) → `DriveFilePickerDialog.show()` → EditorScreen
- [ ] Drive Folder (connected) → `DriveFolderPickerDialog.show()` → WorkspaceScreen
- [ ] Drive not connected → inline Connect button; tapping connects without dismissing
- [ ] No analysis issues

**Verify:** `flutter analyze lib/screens/` → no issues.

**Steps:**

- [ ] **Step 1: Add `_showOpenModal()` to `_HomeScreenState`**

```dart
void _showOpenModal() {
  if (_isMobile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _OpenModal(
        onOpenLocalFile: _openFile,
        onOpenLocalFolder: _openFolder,
        onOpenDriveFile: _openDriveFile,
        onOpenDriveFolder: _openDriveFolder,
        onConnectDrive: _connectDrive,
      ),
    );
  } else {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 360,
          child: _OpenModal(
            onOpenLocalFile: _openFile,
            onOpenLocalFolder: _openFolder,
            onOpenDriveFile: _openDriveFile,
            onOpenDriveFolder: _openDriveFolder,
            onConnectDrive: _connectDrive,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Add `_OpenModal` widget to `home_screen_widgets.dart`**

```dart
class _OpenModal extends ConsumerStatefulWidget {
  final VoidCallback onOpenLocalFile;
  final VoidCallback onOpenLocalFolder;
  final VoidCallback onOpenDriveFile;
  final VoidCallback onOpenDriveFolder;
  final VoidCallback onConnectDrive;

  const _OpenModal({
    required this.onOpenLocalFile,
    required this.onOpenLocalFolder,
    required this.onOpenDriveFile,
    required this.onOpenDriveFolder,
    required this.onConnectDrive,
  });

  @override
  ConsumerState<_OpenModal> createState() => _OpenModalState();
}

class _OpenModalState extends ConsumerState<_OpenModal> {
  String? _expanded; // 'local' | 'drive' | null

  void _tap(String source) =>
      setState(() => _expanded = _expanded == source ? null : source);

  void _invoke(VoidCallback action) {
    Navigator.of(context).pop(); // dismiss modal
    action();
  }

  @override
  Widget build(BuildContext context) {
    final driveState = ref.watch(googleDriveProvider);
    final driveConnected = driveState.status == DriveStatus.connected;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle bar (bottom sheet only, harmless on dialog)
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('Open',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),

          // ── Local row ──────────────────────────────────────────────
          _SourceRow(
            icon: Icons.folder_outlined,
            title: 'Local',
            subtitle: 'Files & folders on this device',
            expanded: _expanded == 'local',
            onTap: () => _tap('local'),
            subRows: [
              _SubRow(
                icon: Icons.insert_drive_file_outlined,
                label: 'File',
                onTap: () => _invoke(widget.onOpenLocalFile),
              ),
              _SubRow(
                icon: Icons.folder_open_outlined,
                label: 'Folder',
                onTap: () => _invoke(widget.onOpenLocalFolder),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── Google Drive row ───────────────────────────────────────
          if (driveConnected)
            _SourceRow(
              icon: Icons.cloud_outlined,
              title: 'Google Drive',
              subtitle: driveState.email ?? 'Connected',
              statusDot: true,
              expanded: _expanded == 'drive',
              onTap: () => _tap('drive'),
              subRows: [
                _SubRow(
                  icon: Icons.insert_drive_file_outlined,
                  label: 'File',
                  onTap: () => _invoke(widget.onOpenDriveFile),
                ),
                _SubRow(
                  icon: Icons.folder_open_outlined,
                  label: 'Folder',
                  onTap: () => _invoke(widget.onOpenDriveFolder),
                ),
              ],
            )
          else
            _DriveNotConnectedRow(onConnect: widget.onConnectDrive),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool statusDot;
  final bool expanded;
  final VoidCallback onTap;
  final List<Widget> subRows;

  const _SourceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.expanded,
    required this.onTap,
    required this.subRows,
    this.statusDot = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 22,
                      color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      Row(children: [
                        if (statusDot) ...[
                          Icon(Icons.circle,
                              size: 7, color: Colors.green.shade600),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600)),
                        ),
                      ]),
                    ],
                  ),
                ),
                Icon(expanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                    color: theme.colorScheme.primary),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Column(children: subRows),
          ),
      ],
    );
  }
}

class _SubRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SubRow(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 18),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      visualDensity: VisualDensity.compact,
      onTap: onTap,
    );
  }
}

class _DriveNotConnectedRow extends StatelessWidget {
  final VoidCallback onConnect;
  const _DriveNotConnectedRow({required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(
            color: Colors.grey.shade300, width: 1.5,
            style: BorderStyle.solid),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.cloud_outlined,
                size: 22, color: Colors.grey.shade400),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Google Drive',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.grey.shade600)),
                Text('Not connected',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade400)),
              ],
            ),
          ),
          FilledButton(
            onPressed: onConnect,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                textStyle: const TextStyle(fontSize: 12)),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Remove the old Local/Drive button section from `build()`**

The old `_SectionLabel('LOCAL')`, `_OpenButton` grid, and Drive section are now replaced by the single Open… button and `_showOpenModal`. Delete that block from `build()`.

- [ ] **Step 4: Analyse**

```bash
export PATH="/opt/homebrew/bin:$PATH" && flutter analyze lib/screens/
```

- [ ] **Step 5: Commit**

```bash
git add lib/screens/home_screen.dart lib/screens/home_screen_widgets.dart
git commit -m "feat: add unified Open modal replacing Local/Drive button grid"
```

```json:metadata
{"files": ["lib/screens/home_screen.dart", "lib/screens/home_screen_widgets.dart"], "verifyCommand": "flutter analyze lib/screens/", "acceptanceCriteria": ["single Open button", "bottom sheet on mobile / dialog on desktop", "local+drive accordion rows", "drive connect inline", "no analysis issues"], "requiresUserVerification": false}
```

---

## Task 7: New Pattern → auto-save to home folder on mobile

**Goal:** On mobile, tapping "New Pattern" immediately saves the file to the home folder and opens the editor with that file path. On desktop, behaviour unchanged.

**Files:**
- Modify: `lib/screens/home_screen.dart` (`_newPattern()` method)

**Acceptance Criteria:**
- [ ] On mobile: new pattern file saved to `{docsDir}/{name}.stitches` before navigating to EditorScreen
- [ ] On mobile: pattern count refreshed after creating
- [ ] On desktop: unchanged (no file path set, editor opens unsaved)
- [ ] Filename sanitised (replaces non-word chars with `_`)
- [ ] Duplicate filename gets a numeric suffix (e.g. `My Pattern_2.stitches`)
- [ ] No analysis issues

**Verify:** `flutter analyze lib/screens/home_screen.dart` → no issues.

**Steps:**

- [ ] **Step 1: Update `_newPattern()` in `home_screen.dart`**

```dart
Future<void> _newPattern() async {
  final pattern = await showDialog<CrossStitchPattern>(
    context: context,
    builder: (_) => const NewPatternDialog(),
  );
  if (pattern == null || !mounted) return;

  if (_isMobile) {
    await _newPatternMobile(pattern);
  } else {
    ref.read(editorProvider.notifier).newPattern(pattern);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const EditorScreen()),
    );
  }
}

Future<void> _newPatternMobile(CrossStitchPattern pattern) async {
  final docsDir = await getApplicationDocumentsDirectory();
  final safeName =
      pattern.name.replaceAll(RegExp(r'[^\w\s-]'), '_').trim();
  final filePath = _uniqueFilePath(docsDir.path, safeName);

  final compress = ref.read(settingsProvider).compressNewFiles;
  try {
    await FileService.saveFile(pattern, filePath, compress: compress);
  } catch (e) {
    if (!mounted) return;
    showError(context, 'Could not save pattern: $e');
    return;
  }

  if (!mounted) return;

  final key = localThumbnailKey(filePath);
  ref.read(editorProvider.notifier).loadPattern(
        pattern,
        filePath: filePath,
        compressOnSave: compress,
      );
  ref.read(recentItemsProvider.notifier).add(filePath,
      isFolder: false, thumbnailKey: key);
  unawaited(_generateAndCacheThumbnail(pattern, key));
  _loadHomePatternCount();

  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const EditorScreen()),
  );
}

/// Return a path that doesn't yet exist, appending _2, _3 … as needed.
String _uniqueFilePath(String dir, String baseName) {
  var path = '$dir/$baseName.stitches';
  if (!File(path).existsSync()) return path;
  var i = 2;
  while (true) {
    path = '$dir/${baseName}_$i.stitches';
    if (!File(path).existsSync()) return path;
    i++;
  }
}
```

Add import at top of `home_screen.dart`:
```dart
import '../providers/settings_provider.dart';
```

- [ ] **Step 2: Analyse**

```bash
export PATH="/opt/homebrew/bin:$PATH" && flutter analyze lib/screens/home_screen.dart
```

- [ ] **Step 3: Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: auto-save new patterns to home folder on mobile"
```

```json:metadata
{"files": ["lib/screens/home_screen.dart"], "verifyCommand": "flutter analyze lib/screens/home_screen.dart", "acceptanceCriteria": ["mobile new-pattern saved to docsDir", "unique filename collision handling", "desktop unchanged", "no analysis issues"], "requiresUserVerification": false}
```

---

## Task 8: Background thumbnail refresh in WorkspaceScreen

**Goal:** When `WorkspaceScreen` loads its file sidebar, generate thumbnails in the background for any `.stitches` files that don't yet have a cached entry. This populates folder thumbnail strips on the home screen without requiring every file to be opened individually.

**Files:**
- Modify: `lib/screens/workspace_screen.dart`

**Acceptance Criteria:**
- [ ] After folder contents load, any local `.stitches` file without a cached thumbnail gets its thumbnail generated and cached
- [ ] Runs fire-and-forget (does not block the UI or sidebar rendering)
- [ ] Only processes files visible in the current folder (not recursive)
- [ ] No analysis issues

**Verify:** `flutter analyze lib/screens/workspace_screen.dart` → no issues.

**Steps:**

- [ ] **Step 1: Add imports to `workspace_screen.dart`**

```dart
import '../services/thumbnail_cache.dart';
import '../services/pattern_thumbnail.dart';
```

- [ ] **Step 2: Add `_refreshThumbnailsInBackground()` to `_WorkspaceScreenState`**

```dart
/// For each local .stitches file in [paths] that has no cached thumbnail,
/// load the pattern and generate a thumbnail.
Future<void> _refreshThumbnailsInBackground(List<String> paths) async {
  for (final path in paths) {
    if (!path.endsWith('.stitches')) continue;
    final key = localThumbnailKey(path);
    final existing = await ThumbnailCache.load(key);
    if (existing != null) continue; // already cached
    try {
      final (pattern, _, __) = await FileService.openFileFromPath(path);
      final bytes = await generatePatternThumbnail(pattern);
      if (bytes != null) await ThumbnailCache.store(key, bytes);
    } catch (_) {
      // Skip files that can't be read.
    }
  }
}
```

- [ ] **Step 3: Call after folder contents are available**

Find where `WorkspaceScreen` loads or displays folder contents. The `folderContentsProvider` (or equivalent) refreshes the file list. In the `build()` method, after watching the folder contents, trigger the refresh:

```dart
// After watching folder contents in build():
final contents = ref.watch(folderContentsProvider(workspace));
// Fire background thumbnail refresh whenever contents change.
ref.listen(folderContentsProvider(workspace), (_, next) {
  if (next case AsyncData(:final value)) {
    final localPaths = value.files
        .whereType<LocalPatternFile>()
        .map((f) => f.path)
        .toList();
    unawaited(_refreshThumbnailsInBackground(localPaths));
  }
});
```

Place this `ref.listen` call in `build()` (Riverpod `ref.listen` is safe in `build` for `ConsumerStatefulWidget`).

- [ ] **Step 4: Analyse**

```bash
export PATH="/opt/homebrew/bin:$PATH" && flutter analyze lib/screens/workspace_screen.dart
```

Check that `folderContentsProvider` and `LocalPatternFile` imports are correct. Adjust provider/type names if they differ from the above.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/workspace_screen.dart
git commit -m "feat: background thumbnail refresh for files visible in workspace sidebar"
```

```json:metadata
{"files": ["lib/screens/workspace_screen.dart"], "verifyCommand": "flutter analyze lib/screens/workspace_screen.dart", "acceptanceCriteria": ["thumbnails generated in background for uncached files", "does not block UI", "no analysis issues"], "requiresUserVerification": false}
```

---

## Self-Review

**Spec coverage:**
- §1 Header: Task 5 ✓
- §1 HOME item: Task 5 ✓
- §1 RECENT flat mixed: Task 5 ✓
- §2 Open modal: Task 6 ✓
- §3 Thumbnails (generation + cache): Tasks 1, 2, 4 ✓
- §3 Folder thumbnails (strip): Task 5 ✓
- §3 Background refresh: Task 8 ✓
- §3 Prune deleted: Task 3 ✓
- §4 Home folder identity: Task 3 (`isHomeFolderPath`) ✓
- §4 New Pattern mobile: Task 7 ✓
- §5 Data model: Task 3 ✓
- §6 Files affected: all covered ✓

**Placeholder scan:** No TBDs. Task 2 Step 2 instructs reading model files to verify field names — this is intentional (can't know exact field names without runtime confirmation).

**Type consistency:** `localThumbnailKey`/`driveThumbnailKey` defined in Task 1, used in Tasks 3, 4, 5, 7, 8. `generatePatternThumbnail` defined in Task 2, used in Tasks 4, 7, 8. `ThumbnailCache.store/load/remove/pruneLocal` defined in Task 1, used in Tasks 3, 5, 8.

**Verification requirement:** NO — no user verification steps required per spec.
