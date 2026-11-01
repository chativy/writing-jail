# macOS App Store Screenshots

The `macOS` directory contains five 2880×1800 PNG screenshots:

1. `01-editor-dark.png` — Dark mode editor
2. `02-editor-ivory.png` — Ivory mode editor
3. `03-file-chooser.png` — Full file chooser
4. `04-focus-dialog.png` — Focus duration dialog
5. `05-focus-fullscreen.png` — Full-screen focus mode with the enlarged
   introductory message

Raw window captures are kept in the ignored `raw/` directory for regeneration.
Run `scripts/render-appstore-screenshots.swift` from the repository root to
rebuild screenshots 01–04. Screenshot 05 is captured directly from the
full-screen focus window so the complete UI remains visible.
