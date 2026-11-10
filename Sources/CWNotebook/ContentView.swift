import SwiftUI

struct ContentView: View {
    @Environment(NotebookStore.self) private var store
    @AppStorage(Prefs.showReference) private var showReference = false
    @State private var selection: Note.ID?
    @State private var search = ""
    @State private var showingTrash = false
    @State private var confirmDelete: Note.ID?
    @State private var confirmEmptyTrash = false

    private var visibleNotes: [Note] {
        (showingTrash ? store.trashed : store.notes).filter { $0.matches(search) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(visibleNotes) { note in
                    NoteRow(note: note)
                        .tag(note.id)
                        .contextMenu {
                            if showingTrash {
                                Button("Restore") { restore(note.id) }
                                Button("Delete Permanently…", role: .destructive) { confirmDelete = note.id }
                            } else {
                                Button("Move to Trash", role: .destructive) { moveToTrash(note.id) }
                            }
                        }
                }
            }
            .overlay { emptyState }
            .onDeleteCommand {
                guard let id = selection else { return }
                if showingTrash { confirmDelete = id } else { moveToTrash(id) }
            }
            .searchable(text: $search, placement: .sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 360)
            .safeAreaInset(edge: .top) { folderSwitch }
            .safeAreaInset(edge: .bottom) { footer }
        } detail: {
            Group {
                if showingTrash {
                    if let id = selection, let note = store.trashedNote(id) {
                        TrashedNoteView(note: note,
                                        onRestore: { restore(id) },
                                        onDelete: { confirmDelete = id })
                            .id(id)
                    } else {
                        ContentUnavailableView("Trash", systemImage: "trash",
                                               description: Text("Deleted notes stay here until you delete them permanently."))
                    }
                } else if let id = selection, let note = store.note(id) {
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
                        .disabled(selection == nil || showingTrash)
                    Button { showReference.toggle() } label: { Label("Reference", systemImage: "book") }
                        .help("Prosigns, Q-codes and abbreviations (⌥⌘R)")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newNote)) { _ in newNote() }
        .onChange(of: selection) { old, _ in discardIfBlank(old) }
        .onChange(of: showingTrash) {
            discardIfBlank(selection)
            selection = showingTrash ? store.trashed.first?.id : store.notes.first?.id
        }
        .onAppear { selection = selection ?? store.notes.first?.id }
        .confirmationDialog("Delete this note permanently?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let id = confirmDelete { deletePermanently(id) }
            }
        } message: {
            Text("You can't undo this.")
        }
        .confirmationDialog("Empty the Trash?", isPresented: $confirmEmptyTrash) {
            Button("Empty Trash", role: .destructive) {
                selection = nil
                store.emptyTrash()
            }
        } message: {
            Text("\(store.trashed.count) \(store.trashed.count == 1 ? "note" : "notes") will be deleted permanently. You can't undo this.")
        }
    }

    private var folderSwitch: some View {
        Picker("Folder", selection: $showingTrash) {
            Text("Notes").tag(false)
            Text(store.trashed.isEmpty ? "Trash" : "Trash (\(store.trashed.count))").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder private var emptyState: some View {
        if visibleNotes.isEmpty {
            if !search.isEmpty {
                ContentUnavailableView.search(text: search)
            } else if showingTrash {
                ContentUnavailableView("Trash is empty", systemImage: "trash")
            } else {
                ContentUnavailableView("No notes", systemImage: "note.text",
                                       description: Text("Press ⌘N to start one."))
            }
        }
    }

    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showingTrash, !store.trashed.isEmpty {
                Button("Empty Trash…", role: .destructive) { confirmEmptyTrash = true }
                    .frame(maxWidth: .infinity)
            }
            if let error = store.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange).lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(showingTrash || store.lastError != nil ? 10 : 0)
    }

    private func newNote() {
        search = ""
        showingTrash = false
        if let id = selection, let current = store.note(id), current.isBlank { return }
        selection = store.create().id
    }

    /// Like Apple Notes: a note you leave without typing anything isn't kept.
    private func discardIfBlank(_ id: Note.ID?) {
        if let id, let note = store.note(id), note.isBlank { store.discard(id) }
    }

    private func moveToTrash(_ id: Note.ID) {
        if selection == id { selection = nil }
        // Let the editor save its last keystrokes as it closes, then move the file.
        DispatchQueue.main.async { store.moveToTrash(id) }
    }

    private func restore(_ id: Note.ID) {
        if selection == id { selection = nil }
        store.restore(id)
    }

    private func deletePermanently(_ id: Note.ID) {
        if selection == id { selection = nil }
        store.deletePermanently(id)
        confirmDelete = nil
    }
}

/// Read-only view of a note in the Trash.
struct TrashedNoteView: View {
    @AppStorage(Prefs.monospaced) private var monospaced = true
    let note: Note
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let parts = Note.split(note.text)
        VStack(spacing: 0) {
            HStack {
                Label("In the Trash", systemImage: "trash")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restore", action: onRestore)
                    .buttonStyle(.borderedProminent)
                Button("Delete Permanently…", role: .destructive, action: onDelete)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
            Divider()
            Text(parts.title.isEmpty ? "Untitled" : parts.title)
                .font(monospaced ? .system(size: 20, weight: .semibold, design: .monospaced)
                                 : .system(size: 20, weight: .semibold))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 10)
            Divider().padding(.horizontal, 16)
            PlainTextEditor(text: .constant(parts.body), monospaced: monospaced,
                            focusOnAppear: false, editable: false)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title).fontWeight(.semibold).lineLimit(1)
            Text(note.modified, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                .monospacedDigit()
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

struct NoteEditor: View {
    @Environment(NotebookStore.self) private var store
    @AppStorage(Prefs.monospaced) private var monospaced = true
    let id: Note.ID
    @State private var title: String
    @State private var bodyText: String
    private let startInTitle: Bool

    init(note: Note) {
        id = note.id
        let parts = Note.split(note.text)
        _title = State(initialValue: parts.title)
        _bodyText = State(initialValue: parts.body)
        startInTitle = parts.title.isEmpty
    }

    private var fileText: String { Note.join(title: title, body: bodyText) }

    var body: some View {
        VStack(spacing: 0) {
            PlainTextField(text: $title, placeholder: "Title", monospaced: monospaced, focusOnAppear: startInTitle)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 10)
            Divider().padding(.horizontal, 16)
            PlainTextEditor(text: $bodyText, monospaced: monospaced, focusOnAppear: !startInTitle)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: fileText) {
            guard (try? await Task.sleep(for: .milliseconds(400))) != nil else { return }
            store.save(id, text: fileText)
        }
        .onDisappear { store.save(id, text: fileText) }
    }
}
