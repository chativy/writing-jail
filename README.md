# Writing Jail

Writing Jail is a kiosk-style Markdown editor for macOS. Choose a Markdown file,
start a focus session, and enter its duration. The app blocks app switching as
fully as macOS allows.

## Run

```sh
./scripts/build-app.sh
open "dist/Writing Jail.app"
```

## App Store Development

Generate the Xcode project and open the App Store-configured scheme:

```sh
xcodegen generate
open WritingJail.xcodeproj
```

The submission bundle uses `com.chativy.writingjail`, App Sandbox, user-selected
file access, and the team `Y5E45NE7R9`. App Store metadata, screenshots, privacy
answers, and remaining release steps are under [AppStore](AppStore).

To block system shortcuts such as Cmd-Tab and Mission Control, grant
Accessibility permission from **System Settings > Privacy & Security >
Accessibility**, then restart the app.

The permission dialog is not shown automatically. Use **Configure Input
Blocking** when you want to request it. Without permission, only the in-app
kiosk lock is applied.

## Controls

- File: a full file chooser opens before the editor. Use **Create New File…**
  from the options area, which is expanded by default, to name a new document.
  **Edit > New File…** and **Edit > Open File…** remain available while the
  editor is open.
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
- Emergency exit: hold Control-Option-Escape for 5 seconds

The selected Markdown file is saved directly. A recovery draft is also kept at
`~/Library/Application Support/WritingJail/draft.txt`.

macOS controls such as the power button, forced restart, and login screen
cannot be blocked by a regular app.

## License

Writing Jail is licensed under the Apache License 2.0. See [LICENSE](LICENSE).
