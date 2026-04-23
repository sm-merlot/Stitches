---
"stitches": patch
---

Fix thread colour mismatch when loading old files

When a `.stitchx` file was saved before a DMC colour update, threads stored the outdated hex. Now `Thread.fromYaml` looks up the DMC code in the canonical colour table and uses the current hex — so existing stitches and newly drawn ones always match. Falls back to the saved hex for unknown/custom codes.
