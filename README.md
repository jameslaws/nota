# Nota

Sticky notes for the Mac menu bar. Each note is a floating, translucent sheet of
paper saved as a plain markdown file in iCloud Drive (`iCloud Drive/Nota`), so the
notes outlive the app and can be read anywhere.

- Click the menu bar icon to show or hide your notes; right-click for the menu.
- Markdown renders as you type; the line holding the caret shows the raw syntax.
- `nota://new?text=…` makes a note (used by Loqui and Shortcuts); `nota://toggle` shows or hides them.

## Build

macOS 26, Xcode 26. The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen), but the generated project is
committed so a plain `xcodebuild` works:

```sh
xcodebuild -project Nota.xcodeproj -target Nota -configuration Release build
```
