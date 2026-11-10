import SwiftUI

struct ContentView: View {
    @Environment(NotebookStore.self) private var store
    @AppStorage(Prefs.showReference) private var showReference = false
    @AppStorage(Prefs.uppercase) private var uppercase = true
    @State private var selection: Note.ID?
    @State private var search = ""

    private var visibleNotes: [Note] { store.notes.filter { $0.matches(search) } }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(visibleNotes) { note in
                    NoteRow(note: note)
                        .tag(note.id)
                        .contextMenu {
                            Button("Move to Trash", role: .destructive) { delete(note.id) }
                        }
                }
            }
            .overlay {
                if visibleNotes.isEmpty {
                    if search.isEmpty {
                        ContentUnavailableView("No notes", systemImage: "note.text",
                                               description: Text("Press ⌘N to start one."))
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
            .onDeleteCommand { if let id = selection { delete(id) } }
            .searchable(text: $search, placement: .sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 360)
            .safeAreaInset(edge: .bottom) { footer }
        } detail: {
            Group {
                if let id = selection, let note = store.note(id) {
                    NoteEditor(note: note).id(id)
                } else {
                    ContentUnavailableView("No note selected", systemImage: "note.text",
                                           description: Text("Pick a note, or press ⌘N to start one."))
                }
            }
            .inspector(isPresented: $showReference) {
                ReferencePanel()
                    .inspectorColumnWidth(min: 240, ideal: 280, max: 380)
            }
            .toolbar {
                ToolbarItemGroup {
                    Button { newNote() } label: { Label("New Note", systemImage: "square.and.pencil") }
                        .help("New note (⌘N)")
                    Button {
                        NotificationCenter.default.post(name: .insertText, object: Date().utcStamp)
                    } label: { Label("Insert UTC Time", systemImage: "clock") }
                        .help("Insert the current UTC time (⇧⌘T)")
                        .disabled(selection == nil)
                    Toggle(isOn: $uppercase) {
                        Label("Uppercase", systemImage: uppercase ? "capslock.fill" : "capslock")
                    }
                    .help(uppercase ? "Typing in capitals, no Caps Lock needed (⇧⌘U)" : "Type in capitals without Caps Lock (⇧⌘U)")
                    Button { showReference.toggle() } label: { Label("Reference", systemImage: "book") }
                        .help("Prosigns, Q-codes and abbreviations (⌥⌘R)")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newNote)) { _ in newNote() }
        .onChange(of: selection) { old, _ in
            // Like Apple Notes: a note you leave without typing anything isn't kept.
            if let old, let note = store.note(old), note.isBlank { store.delete(old) }
        }
        .onAppear { selection = selection ?? store.notes.first?.id }
    }

    @ViewBuilder private var footer: some View {
        if let error = store.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange).lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
    }

    private func newNote() {
        search = ""
        if let id = selection, let current = store.note(id), current.isBlank { return }
        selection = store.create().id
    }

    private func delete(_ id: Note.ID) {
        if selection == id { selection = nil }
        store.delete(id)
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title).fontWeight(.semibold).lineLimit(1)
            HStack(spacing: 6) {
                Text(note.modified, format: Calendar.current.isDateInToday(note.modified)
                     ? .dateTime.hour().minute() : .dateTime.day().month(.abbreviated).year(.twoDigits))
                    .monospacedDigit()
                Text(note.preview).lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

struct NoteEditor: View {
    @Environment(NotebookStore.self) private var store
    @AppStorage(Prefs.monospaced) private var monospaced = true
    @AppStorage(Prefs.uppercase) private var uppercase = true
    let id: Note.ID
    @State private var text: String

    init(note: Note) {
        id = note.id
        _text = State(initialValue: note.text)
    }

    var body: some View {
        PlainTextEditor(text: $text, monospaced: monospaced, uppercase: uppercase)
            .task(id: text) {
                guard (try? await Task.sleep(for: .milliseconds(400))) != nil else { return }
                store.save(id, text: text)
            }
            .onDisappear { store.save(id, text: text) }
    }
}
