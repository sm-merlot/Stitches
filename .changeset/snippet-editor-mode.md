---
"stitches": patch
---

Fix several issues with the snippet editor and tighten up the title bar across all three editors.

**Snippet editor — now renders as an editor instead of a viewer.** The snippet editor wraps itself in a fresh `ProviderScope`, so it inherited `loadPattern`'s default `AppMode.view` — which hid the toolbar and swapped the right sidebar to the Colours-only stitch layout. It now calls `setMode(AppMode.edit)` after load so the toolbar and Palettes/Colours tabs render, and the block-mode toggle has moved from `actions` into the title row (flush against the name) to match the main/workspace editors.

**Slot-aligned palette symbols and stitch counts.** Symbols belong to the *slot*, not the thread, so every palette shares the primary palette's symbols at each slot index. Switching palettes in the snippet editor now only changes colours, not symbols — and stitch counts are remapped slot-by-slot so secondary palettes show identical numbers to the primary. A new `syncPaletteSymbolsToPrimary` helper is wired into palette init, add-palette, and swap-thread-colour so the invariant holds across all edit paths.

**`replaceThread` drift fixed.** When the snippet-editor Colours panel swaps a DMC on the primary palette, the change is now mirrored into `snippetPalettes[0]` and the (preserved) slot symbol is fanned back out to every secondary palette. Pattern, primary, and secondaries stay aligned mid-session instead of waiting for save to re-sync.

**Title bar polish across all three editors.** The pattern-name title in the main and workspace editors is now clamped to 280px with `TextOverflow.ellipsis`, so long names can't push the block-mode button off-screen. The snippet editor's name is a borderless always-on `TextField` (no more tap-to-edit `InkWell`), auto-sized to the text with the same 280px cap. A fixed 8×8 dirty-dot slot at the start of the snippet title row fades in/out without shifting the row, and the Save button is disabled when the snippet has no unsaved changes.
