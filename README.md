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

- **Out**: on screen, translucent until hovered. The menu bar click puts them away.
- **Kept** (eye): solid, and stays on screen when the others are put away. Still draggable.
- **Stack**: put-away notes collect in a small deck at the screen edge (drag it
  anywhere). Click it to search the pile and bring one note back.
- **Pinned to a desktop** (right-click a note): stays on that desktop, and when put
  away fades where it sits instead of joining the stack.

## Markdown

Headings, bullets (nested with Tab / Shift-Tab), numbered lists, checkboxes (click
to tick, ⌘↩ to make or tick one), quotes, `---` rules, fenced code, `code`,
**bold** (⌘B), *italic* (⌘I), ~~strike~~ (⌘⇧X), ==highlight==, links (⌘K) and bare
URLs. Return continues a list; Return on an empty item ends it. Backspace at the
start of an item removes its formatting.
