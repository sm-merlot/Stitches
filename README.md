# StitchX

> Built with the assistance of AI tools (Claude Code / Anthropic Claude).

A cross-stitch pattern editor for macOS, iOS, and Android. StitchX lets you design and edit counted cross-stitch patterns using DMC thread colors, with a touch- and Apple Pencil-friendly canvas.

## Features

- **Pattern canvas** — draw full stitches, half stitches (forward `/` and backward `\`), quarter stitches, and backstitches on a scalable grid
- **DMC color palette** — searchable library of ~300 DMC thread colors; Anchor color support planned
- **Undo / redo** — full history stack; double-tap to undo on touch devices
- **File format** — patterns saved as `.stitchx` files (YAML internally)
- **Multi-platform** — macOS, iOS, Android; Apple Pencil double-tap toggles draw/erase mode
- **Zoom & pan** — pinch-to-zoom, scroll-wheel zoom, drag to pan; zoom range 0.1×–20×
- **Settings** — thread system toggle (DMC / Anchor), keep-screen-on option

## Tools

- full stitch
- half stitch (forward / backward)
- quarter stitch (any corner)
- backstitch (tap two grid intersections)
- navigate (pan without drawing)
- erase

## Getting Started

```bash
flutter run -d macos
```

Requires Flutter 3.41.4+.

## Roadmap

- **Phase 2** — Google Drive sync, reference image overlay, folder view
- **Phase 3** — PDF viewer, full keybinding system, Apple Pencil polish
- **Phase 4** — PDF → `.stitchx` scanning via Claude vision API, Proton Drive
