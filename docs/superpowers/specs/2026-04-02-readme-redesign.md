# README Redesign — Design Spec
_2026-04-02_

## Goal

Replace the current wall-of-text README with a polished hero-first layout that impresses quickly, uses videos to show features, and keeps full detail available without dominating the page.

---

## Layout (top to bottom)

### 1. Hero

Centred block:

- App icon — `assets/icon/stitches_icon.png` at 90px, `border-radius: 18px`
- Title — `# Stitches` (H1)
- Tagline — one sentence, e.g. _"A free, open-source cross-stitch pattern editor for macOS, Windows, iOS and Android"_
- **Badge row 1** (CI / version / Flutter / licence / stars):
  ```markdown
  [![CI](https://img.shields.io/github/actions/workflow/status/scme0/Stitches/ci.yml?label=CI&logo=github)](https://github.com/scme0/Stitches/actions/workflows/ci.yml)
  [![version](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2Fscme0%2FStitches%2Fmain%2Fpubspec.yaml&query=%24.version&label=version&color=6366f1)](CHANGELOG.md)
  [![Flutter](https://img.shields.io/badge/Flutter-3.41.4-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
  [![MIT](https://img.shields.io/badge/licence-MIT-22c55e)](LICENSE)
  [![Stars](https://img.shields.io/github/stars/scme0/Stitches?style=social)](https://github.com/scme0/Stitches/stargazers)
  ```
- **Badge row 2** (platforms):
  ```markdown
  ![macOS](https://img.shields.io/badge/macOS-000000?logo=apple&logoColor=white)
  ![Windows](https://img.shields.io/badge/Windows-0078D4?logo=windows11&logoColor=white)
  ![iOS](https://img.shields.io/badge/iOS-000000?logo=apple&logoColor=white)
  ![Android](https://img.shields.io/badge/Android-3DDC84?logo=android&logoColor=white)
  ```
- Small italic footnote: _Built with the assistance of [Claude Code](https://claude.ai/claude-code)_
- Note: _\*may not be free on the Apple App Store to offset the $99/year Apple Developer Program fee_

---

### 2. Feature highlights grid

6 items rendered as a markdown table (3 columns × 2 rows — GitHub renders tables cleanly):

| | | |
|---|---|---|
| 🪡 **Full stitch toolkit** — full, half, quarter, backstitch, fill | 🎨 **~300 DMC colours** — with Anchor cross-reference | ☁️ **Google Drive sync** — auto-save across devices |
| ✂️ **Snippets & sprite importer** — reusable motifs from pixel art | ✏️ **Apple Pencil** — hover preview, double-tap erase | 📄 **PDF scanner** *(beta)* — convert printed charts to patterns |

---

### 3. See it in action

Heading: `## 📺 See it in action`

10 videos, each in a `<details>` block so the page stays compact. Two-column layout using a markdown table of `<details>` pairs.

**Video format:** MP4 uploaded directly to GitHub (drag into a comment/issue to get the URL, then embed with `<video>`). Aim for 1080p, no audio needed, cursor visible.

#### Shot lists

**1. Core drawing loop** (~20s, desktop)
- Start on a blank new pattern (30×30)
- Draw a row of full stitches in one colour
- Switch to a second colour, draw half stitches `/` and `\`
- Add a backstitch outline — tap two grid intersections
- Undo twice, redo once
- Pinch/scroll to zoom in so stitches fill the frame

**2. Layers & blend modes** (~25s, desktop)
- Open a pattern with a base layer already drawn
- Add a new layer, rename it "glow"
- Draw some stitches on top in a bright colour
- Toggle layer visibility on/off
- Change blend mode to **Add** — show the glow composite
- Reduce layer opacity to ~60%
- Switch to stitch mode briefly to show the composite palette

**3. Select, copy & transform** (~20s, desktop)
- Rubber-band select a distinct motif region
- Tap Copy
- Paste — ghost follows cursor
- Flip horizontal
- Rotate 90° CW
- Stamp onto a new area of the canvas

**4. Snippets** (~30s, desktop)
- Select a small motif, tap "Save as snippet", name it
- Open the snippets panel (slide-up sheet)
- Tap the snippet — enters paste mode
- Stamp it 3–4 times across the canvas
- Long-press the snippet → Edit → open snippet editor
- Draw one extra stitch in the editor, close
- Back on main canvas — stamp the updated snippet

**5. Sprite sheet importer** (~30s, desktop)
- Open a pixel-art sprite sheet (retro game characters work well)
- Crop mode: drag a rectangle around one character
- Watch the DMC colour-matching conversion
- Drag the palette simplification slider — show colours merging
- Tap "Add to Snippets"
- Switch back to main canvas, open snippets panel, stamp it

**6. Stitch mode** (~20s, desktop or iPad)
- Open a colourful finished pattern in design mode
- Tap the "Stitch Mode" FAB — UI simplifies
- Tap one colour in the palette — all other stitches dim to grey
- Tap a different colour — focus switches
- Show the keep-screen-on toggle
- Tap "Exit Stitch Mode" to return

**7. Apple Pencil on iPad** (~20s, iPad)
- Hover pencil over canvas — preview cell highlights before touching
- Draw a row of stitches with the pencil
- Double-tap pencil barrel — switches to erase mode (show indicator change)
- Double-tap again — back to draw
- In paste mode: hover pencil to position ghost, tap finger to stamp

**8. Google Drive sync** (~15s, desktop)
- Show Drive connected state in the toolbar (sync indicator)
- Make a small edit — watch the auto-save indicator pulse
- Open the Drive folder picker briefly
- Show the same file listed in the home screen Drive section

**9. PDF scanner** *(beta, ~35s, desktop)*
- Open a cross-stitch chart PDF
- Select the page containing the grid
- Crop the grid bounds (auto-detect, tweak handles)
- Enter stitch count dimensions
- Tap a few cells for each symbol type, assign DMC codes
- Tap "Scan" — watch cells fill in
- Review a flagged cell, reassign it
- Show the finished pattern
- Caption/caveat: _"Works best on clean, high-contrast charts. Full-stitch only in this release."_

**10. Stitch demonstration** *(beta, ~25s, desktop)*
- Open a small finished pattern
- Tap the stitch demo button
- Animation plays — needle traces the stitch order thread by thread
- Show colour-coded passes (front/back)
- Tap a different start cell — animation re-plans
- Export GIF button briefly visible
- Caption/caveat: _"Beta — some complex patterns may produce suboptimal stitch paths."_

---

### 4. Getting Started

```markdown
## 🚀 Getting Started

Requires [Flutter 3.41.4+](https://flutter.dev/docs/get-started/install).

```bash
git clone https://github.com/scme0/Stitches.git
cd Stitches
flutter pub get
./run          # macOS / Linux  (or Git Bash on Windows)
./run.ps1      # Windows PowerShell
```

For device-specific targets (`ios`, `android`, `windows`, …) see `./run help`.
```

---

### 5. Full feature reference

Collapsed `<details>` block. Moves the entire existing Features section inside it verbatim — nothing is lost, just not the first thing you see.

```markdown
<details>
<summary>📖 Full feature reference</summary>

### Pattern editing
...existing content...

</details>
```

---

### 6. Changelog

```markdown
## 📋 Changelog

See [CHANGELOG.md](CHANGELOG.md) — generated automatically from [changesets](https://github.com/changesets/changesets).
```

---

### 7. Backlog

Keep as-is from the current README.

---

## What stays the same

- All existing feature text — moved into the collapsed `<details>` block
- The Apple Store cost caveat — moved to a footnote in the hero
- Backlog section content

## Implementation notes

- Videos: record as MP4, upload by dragging into a GitHub issue/PR comment box to get a CDN URL, then embed in the README with `<video src="..." controls width="100%"></video>` inside each `<details>` block
- Icon: use the PNG (`assets/icon/stitches_icon.png`) — GitHub renders PNGs inline in markdown with `<img src="assets/icon/stitches_icon.png" width="90">`
- GitHub social preview: set a custom OG image in repo Settings → Social preview (app icon + a screenshot collage recommended)
- The `run` and `run.ps1` scripts are already updated on branch `scme0/feature/dependabot-changesets` — wait for that to merge or cherry-pick
