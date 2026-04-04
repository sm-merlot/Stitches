# File Format v2 Design

**Date:** 2026-04-04
**Status:** Approved, awaiting implementation
**Depends on:** nothing
**Required by:** Three-Mode Architecture, Progress Tracking

---

## Problem

The current `.stitches` YAML format is flat — pattern definition data, stitching config, and (soon) progress tracking all sit at the same top level. This makes it hard to reason about what belongs where and what gets shared when exporting a file.

---

## Goals

- Clear top-level sections: `pattern` (the design) and `stitching` (everything about the act of stitching it)
- Versioned format so old files continue to load cleanly
- One-way migration: old files load as v1, save as v2 from that point forward
- Strip `stitching.progress` on share by default; keep `stitching.pageMode` (it's useful to share your page setup)

---

## Format

### v1 (current, no version field)

```yaml
name: My Pattern
width: 100
height: 80
aidaColor: '#F5F5DC'
designer: Jane
layers:
  - ...
threads:
  - ...
snippets:
  - ...
pageMode:
  enabled: true
  pageWidth: 50
  pageHeight: 40
  fuzzyAmount: 2
```

### v2 (new)

```yaml
version: 2
name: My Pattern
pattern:
  width: 100
  height: 80
  aidaColor: '#F5F5DC'
  designer: Jane
  layers:
    - ...
  threads:
    - ...
  snippets:
    - ...
stitching:
  pageMode:
    enabled: true
    pageWidth: 50
    pageHeight: 40
    fuzzyAmount: 2
  progress:
    completedStitches:
      - [12, 4]
      - [12, 5]
    completedPages: [0, 2]
```

---

## Data Ownership

| Field | Section | Shared on export? |
|---|---|---|
| name | top-level | ✓ always |
| width, height, aidaColor, designer, notes | pattern | ✓ always |
| layers, threads, snippets | pattern | ✓ always |
| pageMode | stitching | ✓ yes (useful to share page setup) |
| progress | stitching | ✗ stripped by default, opt-in to include |

---

## Migration Strategy

**Reading:**
- No `version` field → parse as v1 (current flat structure)
- `version: 2` → parse as v2 (nested structure)

**Writing:**
- Always write v2
- First save of a v1 file upgrades it to v2 automatically

**Backwards compatibility:** v1 files continue to load indefinitely. No data is lost during migration — all fields map 1:1 to their new location.

---

## Implementation

### Files to change

**`lib/models/pattern.dart`**
- `CrossStitchPattern.fromYaml()`: detect version, delegate to `_fromYamlV1()` or `_fromYamlV2()`
- `CrossStitchPattern.toYaml()`: always write v2 structure

**`lib/models/page_config.dart`**
- No change to model — just moves from `yaml['pageMode']` to `yaml['stitching']['pageMode']` in the parser

**`lib/services/file_service.dart`**
- `toYamlString()`: write v2 structure with `version: 2` at top
- `fromYamlString()`: version detection before delegating to pattern parser

**New: `lib/models/pattern_progress.dart`**
- `PatternProgress` model with `completedStitches: Set<(int,int)>` and `completedPages: Set<int>`
- `fromYaml()` / `toYaml()` — reads from `yaml['stitching']['progress']`
- `PatternProgress.empty` constant

### Share stripping

In the share/export flow, when "share without progress" is chosen (the default):
- Write v2 YAML but omit the `progress:` key under `stitching:`
- `pageMode` is always included

---

## Testing

- Load a v1 file → confirm all fields parse correctly, no data loss
- Save a loaded v1 file → confirm output is v2 format
- Load the saved v2 file → confirm round-trip fidelity
- Load a v2 file with `progress:` → confirm progress data parses
- Load a v2 file without `progress:` → confirm `PatternProgress.empty` used (no crash)
