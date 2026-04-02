# README Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the wall-of-text README with a polished hero-first layout including live badges, a feature highlights grid, 10 collapsible video slots, and a collapsed full feature reference.

**Architecture:** All changes are to a single file (`README.md`). The existing feature text is preserved verbatim inside a `<details>` block — nothing is deleted. Videos are placeholder `<video>` tags the user fills in after recording; shot lists are embedded as HTML comments.

**Tech Stack:** GitHub-flavoured Markdown, shields.io badges, GitHub `<details>`/`<video>` tags.

**User Verification:** NO — the README is written and committed; the user reviews the PR diff visually before merging.

---

## File Structure

| File | Change |
|---|---|
| `README.md` | Full rewrite — hero, grid, videos, getting started, collapsed features, changelog, backlog |
| `.changeset/readme-redesign.md` | New changeset file for this PR |

---

### Task 1: Hero section

**Goal:** Replace the current title + note block with a centred hero: icon, title, tagline, two badge rows, and footnotes.

**Files:**
- Modify: `README.md` (lines 1–8 replaced)

**Acceptance Criteria:**
- [ ] Icon renders at 90px centred, rounded corners
- [ ] Title is H1
- [ ] Two badge rows present with correct URLs
- [ ] Apple Store cost caveat and Claude Code footnote both present

**Verify:** `git diff README.md | head -60` — confirm old header gone, new hero present

**Steps:**

- [ ] **Step 1: Replace the opening section of README.md**

Replace everything from line 1 up to and including the `> [!NOTE]` cost caveat block (lines 1–8) with:

```markdown
<div align="center">

<img src="assets/icon/stitches_icon.png" width="90" style="border-radius:18px" alt="Stitches icon">

# Stitches

_A free, open-source cross-stitch pattern editor for macOS, Windows, iOS and Android_

[![CI](https://img.shields.io/github/actions/workflow/status/scme0/Stitches/ci.yml?label=CI&logo=github)](https://github.com/scme0/Stitches/actions/workflows/ci.yml)
[![version](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2Fscme0%2FStitches%2Fmain%2Fpubspec.yaml&query=%24.version&label=version&color=6366f1)](CHANGELOG.md)
[![Flutter](https://img.shields.io/badge/Flutter-3.41.4-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![MIT](https://img.shields.io/badge/licence-MIT-22c55e)](LICENSE)
[![Stars](https://img.shields.io/github/stars/scme0/Stitches?style=social)](https://github.com/scme0/Stitches/stargazers)

![macOS](https://img.shields.io/badge/macOS-000000?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-0078D4?logo=windows11&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-000000?logo=apple&logoColor=white)
![Android](https://img.shields.io/badge/Android-3DDC84?logo=android&logoColor=white)

_\*Free on all platforms. May not be free on the Apple App Store to offset the $99/year Apple Developer Program fee._

_Built with the assistance of [Claude Code](https://claude.ai/claude-code)_

</div>

```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs(readme): add hero section with icon and badges"
```

---

### Task 2: Feature highlights grid

**Goal:** Insert a 6-cell feature grid immediately after the hero, before the existing Features heading.

**Files:**
- Modify: `README.md` (insert after hero, before `## Features`)

**Acceptance Criteria:**
- [ ] 3×2 table with emoji, bold title, and brief description per cell
- [ ] PDF scanner cell includes *(beta)* marker
- [ ] Renders without raw HTML — pure markdown table

**Verify:** `git diff README.md` — confirm table present between hero and Features heading

**Steps:**

- [ ] **Step 1: Insert the grid immediately before the `## Features` heading**

```markdown
---

| | | |
|:---|:---|:---|
| 🪡 **Full stitch toolkit** — full, half, quarter, backstitch, fill | 🎨 **~300 DMC colours** — with Anchor cross-reference | ☁️ **Google Drive sync** — auto-save across devices |
| ✂️ **Snippets & sprite importer** — reusable motifs from pixel art | ✏️ **Apple Pencil** — hover preview, double-tap erase | 📄 **PDF scanner** *(beta)* — convert printed charts to patterns |

```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs(readme): add feature highlights grid"
```

---

### Task 3: Videos section

**Goal:** Insert a "See it in action" section with 10 collapsible `<details>` blocks — one per video — each containing a `<video>` placeholder and embedded shot list as an HTML comment.

**Files:**
- Modify: `README.md` (insert after feature grid, before existing Features heading)

**Acceptance Criteria:**
- [ ] 10 `<details>` blocks present
- [ ] Each has a `<summary>` with title and duration
- [ ] Each has a `<video src="VIDEO_URL_HERE" ...>` placeholder
- [ ] Each has an HTML comment shot list
- [ ] Beta videos (9, 10) have a caveat line below the video tag

**Verify:** `grep -c '<details>' README.md` → `10`

**Steps:**

- [ ] **Step 1: Insert the videos section after the feature grid and before `## Features`**

```markdown
## 📺 See it in action

> Videos coming soon — recordings in progress. Each `▶` block below will contain an MP4 demo.
>
> **To add a video:** record an MP4, drag it into any GitHub issue/PR comment box to get a CDN URL, then replace `VIDEO_URL_HERE` in the relevant block below.

<details>
<summary>▶ Core drawing loop (~20s)</summary>

<!--
Shot list:
1. Start on a blank new pattern (30×30)
2. Draw a row of full stitches in one colour
3. Switch to a second colour, draw half stitches / and \
4. Add a backstitch outline — tap two grid intersections
5. Undo twice, redo once
6. Pinch/scroll to zoom in so stitches fill the frame
-->

<video src="VIDEO_URL_HERE" controls width="100%"></video>

</details>

<details>
<summary>▶ Layers & blend modes (~25s)</summary>

<!--
Shot list:
1. Open a pattern with a base layer already drawn
2. Add a new layer, rename it "glow"
3. Draw some stitches on top in a bright colour
4. Toggle layer visibility on/off
5. Change blend mode to Add — show the glow composite
6. Reduce layer opacity to ~60%
7. Switch to stitch mode briefly to show the composite palette
-->

<video src="VIDEO_URL_HERE" controls width="100%"></video>

</details>

<details>
<summary>▶ Select, copy & transform (~20s)</summary>

<!--
Shot list:
1. Rubber-band select a distinct motif region
2. Tap Copy
3. Paste — ghost follows cursor
4. Flip horizontal
5. Rotate 90° CW
6. Stamp onto a new area of the canvas
-->

<video src="VIDEO_URL_HERE" controls width="100%"></video>

</details>

<details>
<summary>▶ Snippets (~30s)</summary>

<!--
Shot list:
1. Select a small motif, tap "Save as snippet", name it
2. Open the snippets panel (slide-up sheet)
3. Tap the snippet — enters paste mode
4. Stamp it 3–4 times across the canvas
5. Long-press the snippet → Edit → open snippet editor
6. Draw one extra stitch in the editor, close
7. Back on main canvas — stamp the updated snippet
-->

<video src="VIDEO_URL_HERE" controls width="100%"></video>

</details>

<details>
<summary>▶ Sprite sheet importer (~30s)</summary>

<!--
Shot list:
1. Open a pixel-art sprite sheet (retro game characters work well)
2. Crop mode: drag a rectangle around one character
3. Watch the DMC colour-matching conversion
4. Drag the palette simplification slider — show colours merging
5. Tap "Add to Snippets"
6. Switch back to main canvas, open snippets panel, stamp it
-->

<video src="VIDEO_URL_HERE" controls width="100%"></video>

</details>

<details>
<summary>▶ Stitch mode (~20s)</summary>

<!--
Shot list:
1. Open a colourful finished pattern in design mode
2. Tap the "Stitch Mode" FAB — UI simplifies
3. Tap one colour in the palette — all other stitches dim to grey
4. Tap a different colour — focus switches
5. Show the keep-screen-on toggle
6. Tap "Exit Stitch Mode" to return
-->

<video src="VIDEO_URL_HERE" controls width="100%"></video>

</details>

<details>
<summary>▶ Apple Pencil on iPad (~20s)</summary>

<!--
Shot list:
1. Hover pencil over canvas — preview cell highlights before touching
2. Draw a row of stitches with the pencil
3. Double-tap pencil barrel — switches to erase mode (show indicator change)
4. Double-tap again — back to draw
5. In paste mode: hover pencil to position ghost, tap finger to stamp
-->

<video src="VIDEO_URL_HERE" controls width="100%"></video>

</details>

<details>
<summary>▶ Google Drive sync (~15s)</summary>

<!--
Shot list:
1. Show Drive connected state in the toolbar (sync indicator)
2. Make a small edit — watch the auto-save indicator pulse
3. Open the Drive folder picker briefly
4. Show the same file listed in the home screen Drive section
-->

<video src="VIDEO_URL_HERE" controls width="100%"></video>

</details>

<details>
<summary>▶ PDF scanner — <em>beta</em> (~35s)</summary>

<!--
Shot list:
1. Open a cross-stitch chart PDF
2. Select the page containing the grid
3. Crop the grid bounds (auto-detect, tweak handles)
4. Enter stitch count dimensions
5. Tap a few cells for each symbol type, assign DMC codes
6. Tap "Scan" — watch cells fill in
7. Review a flagged cell, reassign it
8. Show the finished pattern
-->

<video src="VIDEO_URL_HERE" controls width="100%"></video>

> ⚠️ *Works best on clean, high-contrast charts. Full-stitch extraction only in this release.*

</details>

<details>
<summary>▶ Stitch demonstration — <em>beta</em> (~25s)</summary>

<!--
Shot list:
1. Open a small finished pattern
2. Tap the stitch demo button
3. Animation plays — needle traces the stitch order thread by thread
4. Show colour-coded passes (front/back)
5. Tap a different start cell — animation re-plans
6. Export GIF button briefly visible
-->

<video src="VIDEO_URL_HERE" controls width="100%"></video>

> ⚠️ *Beta — some complex patterns may produce suboptimal stitch paths.*

</details>

```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs(readme): add videos section with 10 placeholder slots and shot lists"
```

---

### Task 4: Getting started, collapse features, changelog, backlog

**Goal:** Update the Getting Started section, wrap all existing feature content in a `<details>` block, add a Changelog section, and keep the Backlog as-is.

**Files:**
- Modify: `README.md`

**Acceptance Criteria:**
- [ ] Getting Started shows `flutter pub get`, `./run`, `./run.ps1`
- [ ] All existing `## Features` content is inside `<details><summary>📖 Full feature reference</summary>`
- [ ] Changelog section present with link to `CHANGELOG.md`
- [ ] Backlog section unchanged

**Verify:** `grep -c '<details>' README.md` → `11` (10 videos + 1 feature reference)

**Steps:**

- [ ] **Step 1: Replace the existing `## Getting Started` section**

Find:
```markdown
## Getting Started

```bash
flutter run -d macos
```

Requires Flutter 3.41.4+.
```

Replace with:
```markdown
## 🚀 Getting Started

Requires [Flutter 3.41.4+](https://flutter.dev/docs/get-started/install).

```bash
git clone https://github.com/scme0/Stitches.git
cd Stitches
flutter pub get
./run        # macOS / Linux (or Git Bash on Windows)
./run.ps1    # Windows PowerShell
```

For device-specific targets (`ios`, `android`, `windows`, …) run `./run help`.
```

- [ ] **Step 2: Wrap the entire Features section in a `<details>` block**

Find the line `## Features` and add `<details>\n<summary>📖 Full feature reference</summary>\n\n` immediately before it.

Find the line `## Getting Started` (now updated) — add `\n</details>\n\n` immediately before it.

The result should look like:

```markdown
<details>
<summary>📖 Full feature reference</summary>

## Features

### Pattern editing
...all existing content verbatim...

</details>

## 🚀 Getting Started
```

- [ ] **Step 3: Add Changelog section after Getting Started**

Insert after the Getting Started section and before `## Backlog`:

```markdown
## 📋 Changelog

See [CHANGELOG.md](CHANGELOG.md) — generated automatically from [changesets](https://github.com/changesets/changesets).

```

- [ ] **Step 4: Verify structure**

```bash
grep -n "^##\|^<details>\|^</details>" README.md
```

Expected output (in order):
```
<div align="center">          ← hero
## 📺 See it in action        ← videos
<details> × 10                ← video blocks
<details>                     ← feature reference open
## Features
...
</details>                    ← feature reference close
## 🚀 Getting Started
## 📋 Changelog
## Backlog
```

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs(readme): collapse features, update getting started, add changelog link"
```

---

### Task 5: Changeset and PR

**Goal:** Add a changeset, push the branch, and open the PR.

**Files:**
- Create: `.changeset/readme-redesign.md`

**Acceptance Criteria:**
- [ ] Changeset file present with `patch` bump
- [ ] Branch pushed to origin
- [ ] PR open targeting `main`

**Verify:** `gh pr view` — confirms PR is open

**Steps:**

- [ ] **Step 1: Create the changeset**

```bash
cat > .changeset/readme-redesign.md << 'EOF'
---
"stitches": patch
---

Redesign README with hero layout, feature grid, 10 video slots, and collapsible feature reference

- Centred hero with app icon, live CI/version/licence/stars badges, and platform badges
- 6-cell feature highlights grid
- 10 collapsible video slots with embedded shot lists ready to fill once recordings are done
- Full feature reference collapsed into a <details> block — nothing removed
- Updated Getting Started with flutter pub get + ./run / ./run.ps1
- Changelog section linking to auto-generated CHANGELOG.md
EOF
```

- [ ] **Step 2: Commit the changeset**

```bash
git add .changeset/readme-redesign.md
git commit -m "chore: add changeset for readme redesign"
```

- [ ] **Step 3: Push and open PR**

```bash
git push -u origin scme0/feature/readme-redesign

gh pr create \
  --title "docs: redesign README with hero, badges, videos and feature grid" \
  --body "$(cat <<'EOF'
## Summary

- Centred hero with app icon, live CI/version/licence/stars badges, and platform badges
- 6-cell feature highlights grid for quick scanning
- 10 collapsible video slots — each has an embedded shot list; fill in the \`VIDEO_URL_HERE\` placeholders after recording
- Full feature reference preserved verbatim, collapsed into a \`<details>\` block
- Updated Getting Started: \`flutter pub get\` + \`./run\` / \`./run.ps1\`
- Changelog section linking to auto-generated \`CHANGELOG.md\`

## After merging

1. Record the 10 videos (shot lists are in each \`<details>\` block as HTML comments)
2. Upload each MP4 by dragging into a GitHub issue/PR comment box — copy the CDN URL
3. Replace the 10 \`VIDEO_URL_HERE\` placeholders in README.md with a follow-up PR
4. Set a GitHub social preview image: repo Settings → Social preview

🤖 Generated with [Claude Code](https://claude.ai/claude-code)
EOF
)"
```

---

## Self-Review

**Spec coverage:**
- ✅ Hero with icon, title, tagline, badge rows, footnotes — Task 1
- ✅ Feature highlights grid — Task 2
- ✅ 10 videos with shot lists in `<details>` blocks — Task 3
- ✅ Getting started with `./run` / `./run.ps1` — Task 4
- ✅ Full feature reference collapsed — Task 4
- ✅ Changelog section — Task 4
- ✅ Backlog unchanged — Task 4 (no-op)
- ✅ Changeset + PR — Task 5

**Notes:**
- `run` and `run.ps1` are already committed on this branch (committed before the plan was written) — Task 4 references them but does not need to create them
- The "two-column video layout" from the spec mockup is simplified to sequential `<details>` blocks — GitHub's table+details combo is unreliable on mobile; sequential blocks are universally supported
