import SwiftUI

extension Notification.Name {
    static let newNote = Notification.Name("CWNotebook.newNote")
    static let newFolder = Notification.Name("CWNotebook.newFolder")
    /// `object` is the String to insert at the cursor of the open note.
    static let insertText = Notification.Name("CWNotebook.insertText")
    static let focusBody = Notification.Name("CWNotebook.focusBody")
    /// `object` is a FormatCommand.
    static let toggleFormat = Notification.Name("CWNotebook.toggleFormat")
}

enum Prefs {
    static let monospaced = "monospaced"
    static let showReference = "showReference"
    static let keepOnTop = "keepOnTop"
}

@main
struct CWNotebookApp: App {
    @State private var store = NotebookStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 720, minHeight: 460)
        }
        .commands { NotebookCommands(store: store) }
    }
}

struct NotebookCommands: Commands {
    let store: NotebookStore
    @AppStorage(Prefs.monospaced) private var monospaced = true
    @AppStorage(Prefs.showReference) private var showReference = false
    @AppStorage(Prefs.keepOnTop) private var keepOnTop = false

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") { NotificationCenter.default.post(name: .newNote, object: nil) }
                .keyboardShortcut("n")
            Button("New Folder") { NotificationCenter.default.post(name: .newFolder, object: nil) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Insert UTC Time") {
                NotificationCenter.default.post(name: .insertText, object: Date().utcStamp)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
        }
        CommandMenu("Format") {
            Button("Bold") { NotificationCenter.default.post(name: .toggleFormat, object: FormatCommand.bold) }
                .keyboardShortcut("b")
            Button("Italic") { NotificationCenter.default.post(name: .toggleFormat, object: FormatCommand.italic) }
                .keyboardShortcut("i")
            Button("Underline") { NotificationCenter.default.post(name: .toggleFormat, object: FormatCommand.underline) }
                .keyboardShortcut("u")
        }
        CommandGroup(after: .toolbar) {
            Toggle("Monospaced Font", isOn: $monospaced)
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Toggle("Show Reference", isOn: $showReference)
                .keyboardShortcut("r", modifiers: [.command, .option])
            Toggle("Keep Window on Top", isOn: $keepOnTop)
                .keyboardShortcut("t", modifiers: [.command, .option])
            Divider()
            Button("Show Notes Folder in Finder") { store.revealInFinder() }
        }
    }
}
