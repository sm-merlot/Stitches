# Phase 4 Design

## 1. Sprite Sheet Importer

### User flow

1. User taps **"Open sprite sheet…"** from the editor toolbar (new icon, between the existing tools and the demo button).
2. A full-screen sheet slides up showing the image with controls:
   - **Tile mode** — a grid overlay divides the image into equal tiles; user taps a tile to select it. Tile size configurable (8, 16, 32, 64 px — common sprite sizes).
   - **Crop mode** — user drags a rubber-band rectangle to define an arbitrary region.
   - Toggle between modes with a segmented control.
3. Selected region is shown with a highlight. User taps **Copy**.
4. Each pixel in the region is matched to the nearest DMC thread (see colour matching below).
5. Result is written to the editor clipboard as a list of `FullStitch` values, one per pixel, with transparent/very-light pixels omitted.
6. Sheet closes. User selects the Paste tool and positions the sprite on the canvas.

### Colour matching

- Pre-compute **CIE Lab** values for all ~300 DMC colours at app startup (one-time cost, cached).
- For each pixel, convert sRGB → Linear → XYZ → Lab, then find the nearest DMC entry by Euclidean distance in Lab space.
- Pixels with `alpha < 128` are skipped (no stitch placed).
- Optional **palette reduction**: after matching, merge DMC colours that appear fewer than N times into the nearest remaining colour. Keeps patterns stitchable by limiting thread count.

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

## 2. PDF Pattern Scanner

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

## 3. Proton Drive Sync

Deferred. Same shape as Google Drive integration — OAuth2, file tree, background sync.

---

## Build order

1. **Sprite sheet importer** — self-contained, no external dependencies, immediately useful.
2. **PDF scanner** — needs `google_generative_ai` + `flutter_secure_storage` + PDF rasterisation package; add Settings UI for API key.
3. **Proton Drive** — lowest priority.
