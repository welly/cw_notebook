# CW Notebook

A simple macOS note taker for CW, in the style of Apple Notes, with a Morse/CW reference panel beside your notes.

## Using it

- **⌘N** starts a new note. Type the title at the top, then Return or Tab to move into the body. The file keeps the title as its first line (`# Title`). A note you leave without typing anything is discarded.
- **⌘B / ⌘I / ⌘U** toggle bold, italic and underline (also in the Format menu). They're saved in the file as Markdown: `**bold**`, `*italic*`, `<u>underline</u>`. Pasted text always comes in plain.
- **⇧⌘T** inserts the current UTC time, e.g. `2026-11-10 2003Z`.
- **⌥⌘R** shows or hides the **Reference** panel: prosigns, Q-codes and common abbreviations, each with its meaning. Searching matches both signs and meanings (e.g. "slower" finds QRS). Click an entry to insert it at the cursor in your note.
- Everything you type or paste comes out in capitals with Caps Lock off, so the ⇪ indicator never appears.
- Prediction, autocorrect, spell check, text completion, smart quotes and dashes, and Writing Tools are all off in the editor.
- **⇧⌘M** switches between a monospaced and a regular font.
- **Folders**: the sidebar lists **Notes** (unfiled), your folders, and **Trash**. **⇧⌘N** or **New Folder** creates one; right-click a folder to rename or delete it (its notes go to the Trash). Drag a note onto a folder, or right-click it and use **Move to**, to file it.
- Search looks across all folders (each result shows its folder). In the Trash, it searches just the Trash.
- **⌥⌘T** or the pin button keeps the window on top of other apps, e.g. beside your logger or SDR.
- **Trash**: deleting a note moves it to the app's Trash, stored in `CW Notebook/Trash` in iCloud Drive so it syncs too. Restore puts a note back in the folder it came from. From there you can **Restore** a note, **Delete Permanently**, or **Empty Trash**; both permanent options ask first. A new note left blank is simply discarded.

## Where notes are stored

Each note is a plain `.md` text file in **iCloud Drive › CW Notebook**, with each folder as a subfolder, so it syncs to your other Macs and opens in any text editor. If iCloud Drive is off, notes go to `~/Documents/CW Notebook` instead.

## Build

Needs macOS 15+ and the Xcode Command Line Tools.

```bash
./scripts/build-app.sh --install   # builds and copies to ~/Applications
```

The app icon is drawn by `scripts/make-icon.swift`; run `swift scripts/make-icon.swift` to regenerate `Resources/AppIcon.icns`.
