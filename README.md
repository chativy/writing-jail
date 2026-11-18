# Writing Jail

Writing Jail is a focused Markdown editor for macOS, designed for the moments
when the next sentence needs your full attention. For people who love to write
or simply have to write, it removes distractions and creates a place to focus
entirely on your words.

Open an existing Markdown file or create a new one, choose a timed focus
session, and work in a clean full-screen editor. During the session, Writing
Jail uses standard macOS presentation controls to keep the writing surface in
front while keeping every document local and saving automatically every 30
seconds.

## Run

```sh
./scripts/build-app.sh
open "dist/Writing Jail.app"
```

## Xcode Development

Generate the Xcode project and open the application scheme:

```sh
xcodegen generate
open WritingJail.xcodeproj
```

The application bundle uses `com.chativy.writingjail`, App Sandbox, and
user-selected file access.

Writing Jail does not request Accessibility or Input Monitoring permission and
does not intercept keyboard events.

## Controls

- File: a full file chooser opens before the editor. Use **Create New File…**
  from the options area, which is expanded by default, to name a new document.
  **Edit > New File…** and **Edit > Open File…** remain available while the
  editor is open. Use **Edit > Default File Name Format…** to customize new
  names with `{date}`, `{time}`, `{datetime}`, `{yyyy}`, `{MM}`, `{dd}`,
  `{HH}`, `{mm}`, and `{ss}` tokens. The `.md` extension is added automatically.
- Duration: click **Start Focus** and choose minutes from the dropdown. The
  default is `5min`. Options use 5-minute intervals through `1hour`,
  10-minute intervals above one hour, and whole-hour intervals from
  `2hours`. Sessions of 30 minutes or longer require confirmation.
- Secondary display: when a secondary display is connected, use
  **View > Secondary Display** to mirror the editor, show the system wallpaper,
  show a custom image, or fill every secondary display with a solid color.
- Theme: use the top-right button to switch between Dark and Ivory modes
- Cursor: keeps four lines of space below the active line while scrolling
- Auto-save: every 30 seconds, plus when a session starts or ends
- Text size: Cmd-Plus and Cmd-Minus
- Editing: Cmd-A/C/V/X/Z and Shift-Cmd-Z
- Focus mode continues until the selected timer reaches zero

The selected Markdown file is saved directly. A recovery draft is also kept at
`~/Library/Application Support/WritingJail/draft.txt`.

macOS system controls such as the power button, forced restart, login, and
other system-level application switching remain outside the control of a
regular app.

## License

Writing Jail is licensed under the Apache License 2.0. See [LICENSE](LICENSE).
