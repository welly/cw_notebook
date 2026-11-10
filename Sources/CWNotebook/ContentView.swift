import SwiftUI

/// What's chosen in the sidebar.
enum Place: Hashable {
    case unfiled
    case folder(String)
    case trash

    var folderName: String? {
        if case .folder(let name) = self { return name }
        return nil
    }
}

struct ContentView: View {
    @Environment(NotebookStore.self) private var store
    @AppStorage(Prefs.showReference) private var showReference = false
    @AppStorage(Prefs.keepOnTop) private var keepOnTop = false
    @State private var place: Place? = .unfiled
    @State private var selection: Note.ID?
    @State private var search = ""
    @State private var confirmDelete: Note.ID?
    @State private var confirmEmptyTrash = false
    @State private var confirmDeleteFolder: String?
    @State private var folderPrompt: FolderPrompt?
    @State private var folderName = ""

    enum FolderPrompt: Equatable {
        case new
        case rename(String)
    }

    private var current: Place { place ?? .unfiled }
    private var inTrash: Bool { current == .trash }

    private var visibleNotes: [Note] {
        let base: [Note]
        switch current {
        case .unfiled: base = store.notes(in: nil)
        case .folder(let name): base = store.notes(in: name)
        case .trash: base = store.trashed
        }
        return base.filter { $0.matches(search) }
    }

    /// Searching looks in every folder (or just the Trash, when you're in it).
    private var isSearchingEverywhere: Bool { !search.isEmpty && !inTrash }

    private var listedNotes: [Note] {
        isSearchingEverywhere ? store.notes.filter { $0.matches(search) } : visibleNotes
    }

    private var placeTitle: String {
        switch current {
        case .unfiled: "Notes"
        case .folder(let name): name
        case .trash: "Trash"
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            noteList
        } detail: {
            detail
                .inspector(isPresented: $showReference) {
                    ReferencePanel()
                        .inspectorColumnWidth(min: 240, ideal: 280, max: 380)
                }
                .toolbar {
                    ToolbarItemGroup {
                        Button { newNote() } label: { Label("New Note", systemImage: "square.and.pencil") }
                            .help("New note (⌘N)")
                        UTCClockButton()
                        Toggle(isOn: $keepOnTop) {
                            Label("Keep on Top", systemImage: keepOnTop ? "pin.fill" : "pin")
                        }
                        .help(keepOnTop ? "Window stays above other apps (⌥⌘T)" : "Keep this window above other apps (⌥⌘T)")
                        Button { showReference.toggle() } label: { Label("Reference", systemImage: "book") }
                            .help("Prosigns, Q-codes and abbreviations (⌥⌘R)")
                    }
                }
        }
        .background(WindowLevel(floating: keepOnTop))
        .onReceive(NotificationCenter.default.publisher(for: .newNote)) { _ in newNote() }
        .onReceive(NotificationCenter.default.publisher(for: .newFolder)) { _ in startNewFolder() }
        .onChange(of: selection) { old, _ in discardIfBlank(old) }
        .onChange(of: place) {
            search = ""
            if let id = selection, visibleNotes.contains(where: { $0.id == id }) { return }
            selection = visibleNotes.first?.id
        }
        .onAppear { selection = selection ?? visibleNotes.first?.id }
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
        .confirmationDialog("Delete the folder “\(confirmDeleteFolder ?? "")”?", isPresented: Binding(
            get: { confirmDeleteFolder != nil }, set: { if !$0 { confirmDeleteFolder = nil } })
        ) {
            Button("Delete Folder", role: .destructive) {
                if let name = confirmDeleteFolder { deleteFolder(name) }
            }
        } message: {
            let count = store.notes(in: confirmDeleteFolder).count
            Text(count == 0 ? "The folder is empty."
                 : "Its \(count) \(count == 1 ? "note" : "notes") will be moved to the Trash, where you can restore them.")
        }
        .alert(folderPromptTitle, isPresented: Binding(
            get: { folderPrompt != nil }, set: { if !$0 { folderPrompt = nil } })
        ) {
            TextField("Folder name", text: $folderName)
            Button(folderPromptAction) { submitFolder() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $place) {
            Section {
                placeRow("Notes", icon: "note.text", place: .unfiled,
                         count: store.notes(in: nil).count, dropFolder: nil)
                ForEach(store.folders, id: \.self) { name in
                    placeRow(name, icon: "folder", place: .folder(name),
                             count: store.notes(in: name).count, dropFolder: name)
                        .contextMenu {
                            Button("Rename Folder…") { startRename(name) }
                            Button("Delete Folder…", role: .destructive) { confirmDeleteFolder = name }
                        }
                }
            }
            Section {
                Label("Trash", systemImage: "trash")
                    .badge(store.trashed.count)
                    .tag(Place.trash)
            }
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 280)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                if let error = store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange).lineLimit(3)
                }
                Button { startNewFolder() } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("Create a folder (⇧⌘N)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
    }

    /// A folder row that also accepts notes dragged onto it.
    private func placeRow(_ title: String, icon: String, place: Place, count: Int, dropFolder: String?) -> some View {
        Label(title, systemImage: icon)
            .badge(count)
            .tag(place)
            .dropDestination(for: String.self) { ids, _ in
                for id in ids { moveNote(id, to: dropFolder) }
                return !ids.isEmpty
            }
    }

    // MARK: Note list

    private var noteList: some View {
        List(selection: $selection) {
            ForEach(listedNotes) { note in
                NoteRow(note: note, showFolder: isSearchingEverywhere)
                    .tag(note.id)
                    .draggable(note.id)
                    .contextMenu { noteMenu(note) }
            }
        }
        .overlay { emptyState }
        .onDeleteCommand {
            guard let id = selection else { return }
            if inTrash { confirmDelete = id } else { moveToTrash(id) }
        }
        .searchable(text: $search, prompt: inTrash ? "Search Trash" : "Search all notes")
        .navigationTitle(isSearchingEverywhere ? "All Notes" : placeTitle)
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 360)
        .safeAreaInset(edge: .bottom) {
            if inTrash, !store.trashed.isEmpty {
                Button("Empty Trash…", role: .destructive) { confirmEmptyTrash = true }
                    .frame(maxWidth: .infinity)
                    .padding(10)
            }
        }
    }

    @ViewBuilder private func noteMenu(_ note: Note) -> some View {
        if inTrash {
            Button("Restore") { restore(note.id) }
            Button("Delete Permanently…", role: .destructive) { confirmDelete = note.id }
        } else {
            let targets = [nil] + store.folders.map(Optional.some)
            Menu("Move to") {
                ForEach(targets.filter { $0 != note.folder }, id: \.self) { folder in
                    Button(folder ?? "Notes") { moveNote(note.id, to: folder) }
                }
            }
            Divider()
            Button("Move to Trash", role: .destructive) { moveToTrash(note.id) }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if listedNotes.isEmpty {
            if !search.isEmpty {
                ContentUnavailableView.search(text: search)
            } else if inTrash {
                ContentUnavailableView("Trash is empty", systemImage: "trash")
            } else {
                ContentUnavailableView("No notes", systemImage: "note.text",
                                       description: Text("Press ⌘N to start one."))
            }
        }
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if inTrash {
            if let id = selection, let note = store.trashedNote(id) {
                TrashedNoteView(note: note, onRestore: { restore(id) }, onDelete: { confirmDelete = id })
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

    // MARK: Actions

    private func newNote() {
        search = ""
        if inTrash { place = .unfiled }
        if let id = selection, let current = store.note(id), current.isBlank { return }
        selection = store.create(in: current.folderName).id
    }

    /// Like Apple Notes: a note you leave without typing anything isn't kept.
    private func discardIfBlank(_ id: Note.ID?) {
        if let id, let note = store.note(id), note.isBlank { store.discard(id) }
    }

    private func moveNote(_ id: Note.ID, to folder: String?) {
        guard let note = store.note(id), note.folder != folder else { return }
        if selection == id { selection = nil }
        // Let the editor save its last keystrokes as it closes, then move the file.
        DispatchQueue.main.async { store.move(id, to: folder) }
    }

    private func moveToTrash(_ id: Note.ID) {
        if selection == id { selection = nil }
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

    private func deleteFolder(_ name: String) {
        if current == .folder(name) {
            selection = nil
            place = .unfiled
        }
        DispatchQueue.main.async { store.deleteFolder(name) }
        confirmDeleteFolder = nil
    }

    // MARK: Folder prompts

    private var folderPromptTitle: String {
        if case .rename = folderPrompt { return "Rename Folder" }
        return "New Folder"
    }

    private var folderPromptAction: String {
        if case .rename = folderPrompt { return "Rename" }
        return "Create"
    }

    private func startNewFolder() {
        folderName = ""
        folderPrompt = .new
    }

    private func startRename(_ name: String) {
        folderName = name
        folderPrompt = .rename(name)
    }

    private func submitFolder() {
        switch folderPrompt {
        case .new:
            if let name = store.createFolder(folderName) { place = .folder(name) }
        case .rename(let old):
            if let name = store.renameFolder(old, to: folderName), current == .folder(old) {
                place = .folder(name)
            }
        case nil:
            break
        }
        folderPrompt = nil
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
                Label(note.folder.map { "In the Trash · from \($0)" } ?? "In the Trash", systemImage: "trash")
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
    var showFolder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title).fontWeight(.semibold).lineLimit(1)
            HStack(spacing: 6) {
                Text(note.modified, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                    .monospacedDigit()
                if showFolder {
                    Label(note.folder ?? "Notes", systemImage: note.folder == nil ? "note.text" : "folder")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                }
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

/// Floats the window above other apps' windows when "Keep on Top" is on.
struct WindowLevel: NSViewRepresentable {
    var floating: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = floating ? .floating : .normal
            // Also show over full-screen apps such as an SDR or logger.
            if floating { window.collectionBehavior.insert(.fullScreenAuxiliary) }
            else { window.collectionBehavior.remove(.fullScreenAuxiliary) }
        }
    }
}

/// Live UTC time in the toolbar; click it to insert the time into the note.
struct UTCClockButton: View {
    var body: some View {
        Button {
            NotificationCenter.default.post(name: .insertText, object: Date().utcStamp)
        } label: {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Date.utcClockFormatter.string(from: context.date))
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .monospacedDigit()
                    .padding(.horizontal, 4)
            }
        }
        .help("Current UTC time. Click to insert it into the note (⇧⌘T)")
        .accessibilityLabel("Insert UTC time")
    }
}
