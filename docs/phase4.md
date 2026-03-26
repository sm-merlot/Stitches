# Phase 4 Design

## 1. Snippets

Snippets are named mini-canvases — a list of stitches with a fixed width and height — stored globally across all patterns. They act as a reusable design library: create once, stamp into any pattern as many times as needed.

### User flows

**Creating a snippet manually:**
1. Open the Snippets panel (new toolbar button — a grid/library icon).
2. Tap **"New snippet"** — opens `SnippetEditorScreen`, a full editor scoped to that snippet's canvas. User sets a name and canvas size, draws stitches, taps Save.
3. Snippet appears as a thumbnail in the panel.

**Using a snippet:**
1. Open the Snippets panel.
2. Tap any snippet thumbnail — panel closes and the editor enters **paste mode** with the snippet's stitches as the ghost.
3. Tap the canvas to stamp (can stamp multiple times). Esc or Cancel to exit paste mode.

**Managing snippets:**
- Long-press a thumbnail to rename or delete it.
- Tap the pencil icon on a thumbnail to open it in `SnippetEditorScreen` for editing.

### Data model

```dart
// lib/models/snippet.dart

class Snippet {
  final String id;      // UUID v4
  String name;
  final int width;
  final int height;
  final List<Stitch> stitches;

  Snippet({required this.id, required this.name, required this.width,
           required this.height, required this.stitches});
}
```

### Storage

Snippets are stored **per-pattern**, inside the `.stitchx` file alongside the pattern data. They are serialised as a top-level `snippets:` list in the YAML, each entry with `id`, `name`, `width`, `height`, and `stitches` keys — the same stitch format as the main canvas.

To reuse a snippet in another pattern, the user pastes it onto the main canvas and then copies it normally (using the existing select → copy/cut → paste flow) when working in the target pattern. There is no global snippet library; this keeps each `.stitchx` file self-contained.

### Key files

```
lib/
  models/
    snippet.dart                # Snippet model; serialise/deserialise to/from YAML map
  providers/
    snippets_provider.dart      # StateNotifier<List<Snippet>>; snippets are part of pattern state,
                                # persisted by the existing FileService when the pattern is saved
  screens/
    snippet_editor_screen.dart  # Full editor scoped to a snippet canvas; Save button instead of file menu
  widgets/
    snippets_panel.dart         # Slide-in drawer: thumbnail grid + New/Rename/Delete actions
    snippet_thumbnail.dart      # CustomPainter rendering a snippet at small size
```

---

## 2. Sprite Sheet Importer

### User flow

1. User taps **"Open sprite sheet…"** from the editor toolbar (new icon, between the existing tools and the demo button).
2. A full-screen sheet slides up showing the image with controls:
   - **Tile mode** — a grid overlay divides the image into equal tiles; user taps a tile to select it. Tile size configurable (8, 16, 32, 64 px — common sprite sizes).
   - **Crop mode** — user drags a rubber-band rectangle to define an arbitrary region.
   - Toggle between modes with a segmented control.
3. Selected region is shown with a highlight.
4. User sets a snippet name (pre-filled as "Sprite 1", "Sprite 2", etc.) and taps **"Add to Snippets"**.
5. Each pixel in the region is matched to the nearest DMC thread (see colour matching below).
6. Result is saved as a new `Snippet` via `SnippetsProvider`.
7. Sheet stays open — user can select another tile/region and add more snippets without reopening.
8. User taps **Done** to close the sheet. The Snippets panel is automatically opened so the user can immediately paste their new sprites.

### Colour matching

- Pre-compute **CIE Lab** values for all ~300 DMC colours at app startup (one-time cost, cached).
- For each pixel, convert sRGB → Linear → XYZ → Lab, then find the nearest DMC entry by Euclidean distance in Lab space.
- Pixels with `alpha < 128` are skipped (no stitch placed).
- Optional **palette reduction**: after matching, merge DMC colours that appear fewer than N times into the nearest remaining colour. Keeps patterns stitchable by limiting thread count. Exposed as a slider ("Merge colours used fewer than N times") in the importer screen.

### Key files

```
lib/
  screens/
    sprite_sheet_screen.dart     # full-screen importer UI
  services/
    sprite_importer.dart         # pixel extraction + DMC colour matching
  widgets/
    sprite_sheet_painter.dart    # tile grid / crop overlay painter
```

---

## 3. PDF Pattern Scanner

### User flow

1. From the PDF viewer, user taps **"Scan as pattern"**.
2. The current page is rasterised to a PNG (at ~200 DPI).
3. App checks for a configured AI API key in Settings; if missing, prompts the user to enter one.
4. Image is sent to the configured AI provider with a structured prompt.
5. Provider returns a JSON payload describing the pattern (dimensions, threads, stitches).
6. A preview dialog shows the parsed pattern. User can accept (opens as new pattern) or cancel.

### AI provider abstraction

All AI interaction goes through a single interface so providers are swappable:

```dart
// lib/services/ai/ai_provider.dart

abstract class AiProvider {
  String get id;           // e.g. 'gemini', 'claude', 'openai'
  String get displayName;  // shown in Settings
  bool get requiresApiKey;

  /// Analyse a rasterised pattern image and return a structured result.
  Future<PatternScanResult> scanPattern(
    Uint8List imageBytes, {
    String? hint, // free-text hint from the user, e.g. "14-count aida, DMC only"
  });
}
```

**`PatternScanResult`** (returned by all providers):

```dart
class PatternScanResult {
  final int width;
  final int height;
  final List<ScannedThread> threads;  // [{dmcCode, name, colour}]
  final List<ScannedStitch> stitches; // [{x, y, type, dmcCode}]
  final String? warning;              // non-fatal issues the model flagged
}
```

### Gemini provider (initial implementation)

- Package: `google_generative_ai` (official Dart/Flutter SDK).
- Model: `gemini-1.5-flash` (fast, cheap, strong vision).
- Prompt strategy:
  1. Send the rasterised page PNG as an inline image part.
  2. Send a system prompt with the full DMC colour list (code + name + hex).
  3. Ask for a JSON response matching the `PatternScanResult` schema.
  4. Use Gemini's JSON mode (`responseMimeType: 'application/json'`) to enforce structure.
- API key stored in `flutter_secure_storage` (never in SharedPreferences).

### Adding a future provider

1. Create `lib/services/ai/my_provider.dart` implementing `AiProvider`.
2. Register it in `AiProviderRegistry`.
3. It appears automatically in Settings → AI Provider.

```dart
// lib/services/ai/ai_provider_registry.dart

class AiProviderRegistry {
  static final List<AiProvider> all = [
    GeminiAiProvider(),
    // ClaudeAiProvider(),   // uncomment when implemented
    // OpenAiProvider(),
  ];

  static AiProvider forId(String id) =>
      all.firstWhere((p) => p.id == id, orElse: () => all.first);
}
```

### Key files

```
lib/
  services/
    ai/
      ai_provider.dart             # abstract interface + result types
      ai_provider_registry.dart    # registry of available providers
      gemini_provider.dart         # Gemini 1.5 Flash implementation
    pdf_scanner.dart               # rasterises PDF page, calls AiProvider
  screens/
    pattern_scan_preview.dart      # shows parsed result before committing
  widgets/
    api_key_dialog.dart            # prompts for API key if not set
```

### Settings additions

| Setting | Type | Storage |
|---|---|---|
| `aiProviderId` | `String` | SharedPreferences |
| `geminiApiKey` | `String` | flutter_secure_storage |

---

## 4. Proton Drive Sync

Deferred. Same shape as Google Drive integration — OAuth2, file tree, background sync.

---

## Build order

1. **Snippets** — self-contained, no external dependencies. Foundational for sprite sheet UX.
   - `Snippet` model (with YAML serialisation); `FileService` extended to read/write `snippets:` key
   - `SnippetsProvider` (StateNotifier, part of pattern state)
   - `SnippetThumbnail` painter
   - `SnippetsPanel` drawer + toolbar button
   - Paste-from-snippet wiring (snippet tap → paste mode)
   - `SnippetEditorScreen` (manual snippet creation/editing)

2. **Sprite sheet importer** — depends on Snippets for its output step; no other external dependencies.
   - `SpriteImporter` service (colour matching)
   - `SpriteSheetPainter` widget
   - `SpriteSheetScreen` (tile/crop UI, "Add to Snippets" button)
   - Toolbar button

3. **PDF scanner** — needs `google_generative_ai` + `flutter_secure_storage` + PDF rasterisation package; add Settings UI for API key.

4. **Proton Drive** — lowest priority.
