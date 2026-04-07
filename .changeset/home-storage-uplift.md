---
"stitches": minor
---

Home screen uplift: rich recents list with thumbnails, unified local and Drive pickers, and workspace improvements.

- Recent files and folders shown on the home screen with pattern thumbnails; most-recently-opened appears on top in folder thumbnail strips
- Folder items show a stacked thumbnail strip drawn from their contents; Drive folder strips populate in the background at launch without requiring a workspace visit
- Files opened inside a workspace folder do not appear as standalone recent items — the folder entry is the canonical recent with its strip
- Local "Open" picker uses a single macOS NSOpenPanel to select either a file or folder with no separate buttons
- Google Drive picker unified into a single browser — navigate folders and tap a file to open it, or press "Open This Folder" to open as a workspace; no separate file/folder buttons
- macOS file-open channel now registered in `awakeFromNib` (FlutterViewController guaranteed available) fixing a `MissingPluginException` on first launch
- Workspace background thumbnail scan is now recursive (local and Drive), picking up files in subdirectories
- Type badges on recents thumbnails: cloud icon for Drive items, folder icon for folder workspaces
- New unsaved desktop patterns show a red "not saved" icon instead of a spinning sync indicator; navigate-away dialog clarifies the pattern hasn't been saved and offers "Save As…"
