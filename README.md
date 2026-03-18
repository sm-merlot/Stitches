# StitchX

> Built with the assistance of AI tools (Claude Code / Anthropic Claude).

A cross-stitch pattern editor for macOS, iOS, and Android. StitchX lets you design and edit counted cross-stitch patterns using DMC thread colors, with a touch- and Apple Pencil-friendly canvas.

## Features

- **Pattern canvas** — draw full stitches, half stitches (forward `/` and backward `\`), quarter stitches, and backstitches on a scalable grid
- **DMC / Anchor color palette** — searchable library of ~300 DMC thread colors with Anchor cross-reference
- **Undo / redo** — full history stack; double-tap to undo on touch devices
- **File format** — patterns saved as `.stitchx` files (YAML internally)
- **Multi-platform** — macOS, iOS, Android; Apple Pencil double-tap toggles draw/erase mode
- **Zoom & pan** — pinch-to-zoom, scroll-wheel zoom, drag to pan; zoom range 0.1×–20×
- **Keyboard shortcuts** — full shortcut set on desktop (undo, redo, tool switching, modes)
- **Folder workspace** — open a local or Google Drive folder as a workspace with a file tree sidebar
- **Google Drive sync** — connect a Google Drive account; patterns auto-save and sync in the background
- **Reference image overlay** — import a photo as a semi-transparent overlay on the canvas to trace from
- **Stitch mode** — simplified read-only view for stitching from a finished pattern; keep-screen-on option
- **PDF export** — export patterns as printable PDFs
- **Recent files** — quick access to recently opened files and folders, including Drive items

## Tools

- Full stitch
- Half stitch (forward / backward)
- Quarter stitch (any corner)
- Half-cell cross / petit point
- Backstitch (tap two grid intersections)
- Navigate (pan without drawing)
- Erase
- Color picker (sample a stitch's thread)
- Selection (copy, cut, paste, delete regions)

## Getting Started

```bash
flutter run -d macos
```

Requires Flutter 3.41.4+.

## Roadmap

- **Phase 3** — PDF viewer, full keybinding system, Apple Pencil polish
- **Phase 4** — PDF → `.stitchx` scanning via Claude vision API, Proton Drive
