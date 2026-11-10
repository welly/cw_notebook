# CW Notebook

A simple macOS note taker for CW, in the style of Apple Notes, with a Morse/CW reference panel beside your notes.

## Using it

- **⌘N** starts a new note. Its first line becomes the title. A note you leave without typing anything is discarded.
- **⇧⌘T** inserts the current UTC time, e.g. `2026-11-10 2003Z`.
- **⌥⌘R** shows or hides the **Reference** panel: prosigns, Q-codes and common abbreviations, each with its meaning. Searching matches both signs and meanings (e.g. "slower" finds QRS).
- **⇧⌘U** toggles **Uppercase typing** (on by default). Everything you type or paste comes out in capitals with Caps Lock off, so the ⇪ indicator never appears.
- Prediction, autocorrect, spell check, text completion, smart quotes and dashes, and Writing Tools are all off in the editor.
- **⇧⌘M** switches between a monospaced and a regular font.
- Notes can be searched from the sidebar. Delete moves a note to the Trash.

## Where notes are stored

Each note is a plain `.md` text file in **iCloud Drive › CW Notebook**, so it syncs to your other Macs and opens in any text editor. If iCloud Drive is off, notes go to `~/Documents/CW Notebook` instead.

## Build

Needs macOS 15+ and the Xcode Command Line Tools.

```bash
./scripts/build-app.sh --install   # builds and copies to ~/Applications
```
