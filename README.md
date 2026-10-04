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

## Checks

`Tools/check.sh` runs the list-editing tests and renders a sample note to PNG
(light, dark, and with the caret revealing inline syntax). It needs only the
command line tools, so it runs on a Mac without Xcode.

## How notes behave

- **Placed**: pulled out and put somewhere on screen; translucent until hovered.
- **Stacked**: filed into the stack (right-click → Put in Stack), a small deck at
  the screen edge you can drag anywhere. Click it to search and pull a note out.
- **Kept** (eye): solid, and stays on screen even when your notes are hidden.
- The menu bar click shows or hides placed notes and the stack together.
- **Pinned to a desktop** (right-click): a placed note that stays on one desktop.

## Markdown

Headings, bullets (nested with Tab / Shift-Tab), numbered lists, checkboxes (click
to tick, ⌘↩ to make or tick one), quotes, `---` rules, fenced code, `code`,
**bold** (⌘B), *italic* (⌘I), ~~strike~~ (⌘⇧X), ==highlight==, links (⌘K) and bare
URLs. Return continues a list; Return on an empty item ends it. Backspace at the
start of an item removes its formatting.
