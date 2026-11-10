import Foundation
import Observation
import AppKit

/// Notes are plain `.md` files in iCloud Drive › CW Notebook (or ~/Documents if iCloud
/// Drive is off). Unfiled notes sit at the top level; each folder is a subfolder.
/// Deleted notes move to `Trash/`, under a subfolder named after the folder they came
/// from, so Restore can put them back. iCloud syncs it all between Macs; the store
/// polls the folder so changes made elsewhere show up here.
@Observable @MainActor
final class NotebookStore {
    private(set) var notes: [Note] = []
    private(set) var folders: [String] = []
    /// Notes in the Trash, most recently deleted first.
    private(set) var trashed: [Note] = []
    var lastError: String?

    let root: URL
    let usesICloud: Bool
    static let trashName = "Trash"
    var trashRoot: URL { root.appending(path: Self.trashName, directoryHint: .isDirectory) }

    @ObservationIgnored private var signature: [URL: Date] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let fm = FileManager.default

    init() {
        let iCloudDrive = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: iCloudDrive.path) {
            root = iCloudDrive.appending(path: "CW Notebook", directoryHint: .isDirectory)
            usesICloud = true
        } else {
            root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appending(path: "CW Notebook", directoryHint: .isDirectory)
            usesICloud = false
        }
        try? fm.createDirectory(at: trashRoot, withIntermediateDirectories: true)
        reloadIfChanged()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadIfChanged() }
        }
    }

    // MARK: Lookup

    func note(_ id: Note.ID) -> Note? { notes.first { $0.id == id } }
    func trashedNote(_ id: Note.ID) -> Note? { trashed.first { $0.id == id } }
    func notes(in folder: String?) -> [Note] { notes.filter { $0.folder == folder } }

    private func dir(_ folder: String?) -> URL {
        folder.map { root.appending(path: $0, directoryHint: .isDirectory) } ?? root
    }
    private func trashDir(_ folder: String?) -> URL {
        folder.map { trashRoot.appending(path: $0, directoryHint: .isDirectory) } ?? trashRoot
    }
    private func url(_ note: Note) -> URL { dir(note.folder).appending(path: "\(note.id).md") }
    private func trashURL(_ note: Note) -> URL { trashDir(note.folder).appending(path: "\(note.id).md") }

    // MARK: Notes

    func create(in folder: String?) -> Note {
        let note = Note(id: UUID().uuidString, text: "", modified: Date(), folder: folder)
        write(note.text, to: url(note))
        notes.insert(note, at: 0)
        return note
    }

    func save(_ id: Note.ID, text: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }), notes[i].text != text else { return }
        write(text, to: url(notes[i]))
        notes[i].text = text
        notes[i].modified = Date()
        notes.sort { $0.modified > $1.modified }
    }

    func move(_ id: Note.ID, to folder: String?) {
        guard let i = notes.firstIndex(where: { $0.id == id }), notes[i].folder != folder else { return }
        var moved = notes[i]
        moved.folder = folder
        try? fm.createDirectory(at: dir(folder), withIntermediateDirectories: true)
        guard move(url(notes[i]), to: url(moved)) else { return }
        notes[i] = moved
        signature = currentSignature()
    }

    /// For a new note left blank: removed outright rather than put in the Trash.
    func discard(_ id: Note.ID) {
        guard let note = note(id) else { return }
        remove(url(note))
        notes.removeAll { $0.id == id }
        signature = currentSignature()
    }

    // MARK: Trash

    func moveToTrash(_ id: Note.ID) {
        guard var note = note(id) else { return }
        try? fm.createDirectory(at: trashDir(note.folder), withIntermediateDirectories: true)
        guard move(url(note), to: trashURL(note)) else { return }
        // The file's date becomes the deletion date, so the Trash lists newest first.
        note.modified = Date()
        try? fm.setAttributes([.modificationDate: note.modified], ofItemAtPath: trashURL(note).path)
        notes.removeAll { $0.id == id }
        trashed.insert(note, at: 0)
        signature = currentSignature()
    }

    /// Puts the note back in the folder it came from, recreating the folder if needed.
    func restore(_ id: Note.ID) {
        guard let note = trashedNote(id) else { return }
        try? fm.createDirectory(at: dir(note.folder), withIntermediateDirectories: true)
        guard move(trashURL(note), to: url(note)) else { return }
        trashed.removeAll { $0.id == id }
        notes.append(note)
        notes.sort { $0.modified > $1.modified }
        if let f = note.folder, !folders.contains(f) { folders = sortedFolders(folders + [f]) }
        removeEmptyTrashFolders()
        signature = currentSignature()
    }

    func deletePermanently(_ id: Note.ID) {
        guard let note = trashedNote(id) else { return }
        remove(trashURL(note))
        trashed.removeAll { $0.id == id }
        removeEmptyTrashFolders()
        signature = currentSignature()
    }

    func emptyTrash() {
        for note in trashed { remove(trashURL(note)) }
        trashed.removeAll()
        removeEmptyTrashFolders()
        signature = currentSignature()
    }

    // MARK: Folders

    /// Returns an error message, or nil if the name is fine.
    func problem(withFolderName name: String, renaming old: String? = nil) -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return "Give the folder a name." }
        if n.contains("/") || n.contains(":") { return "Folder names can't contain / or :." }
        if n.hasPrefix(".") { return "Folder names can't start with a full stop." }
        if n.caseInsensitiveCompare(Self.trashName) == .orderedSame { return "“Trash” is already used by the app." }
        if n.caseInsensitiveCompare("Notes") == .orderedSame { return "“Notes” is already used by the app." }
        let clash = folders.contains { $0.caseInsensitiveCompare(n) == .orderedSame && $0 != old }
        if clash { return "There's already a folder called “\(n)”." }
        return nil
    }

    @discardableResult
    func createFolder(_ name: String) -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        if let problem = problem(withFolderName: n) { lastError = problem; return nil }
        do {
            try fm.createDirectory(at: dir(n), withIntermediateDirectories: true)
        } catch {
            lastError = "Couldn't create folder: \(error.localizedDescription)"
            return nil
        }
        lastError = nil
        folders = sortedFolders(folders + [n])
        signature = currentSignature()
        return n
    }

    @discardableResult
    func renameFolder(_ old: String, to name: String) -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard n != old else { return old }
        if let problem = problem(withFolderName: n, renaming: old) { lastError = problem; return nil }
        guard move(dir(old), to: dir(n)) else { return nil }
        for i in notes.indices where notes[i].folder == old { notes[i].folder = n }
        folders = sortedFolders(folders.map { $0 == old ? n : $0 })
        signature = currentSignature()
        return n
    }

    /// Moves the folder's notes to the Trash, then removes the folder.
    func deleteFolder(_ name: String) {
        for note in notes(in: name) { moveToTrash(note.id) }
        let leftovers = (try? fm.contentsOfDirectory(atPath: dir(name).path))?.filter { !$0.hasPrefix(".") } ?? []
        if leftovers.isEmpty {
            remove(dir(name))
        } else {
            // Something other than notes is in there: leave it for the macOS Trash instead.
            try? fm.trashItem(at: dir(name), resultingItemURL: nil)
        }
        folders.removeAll { $0 == name }
        signature = currentSignature()
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }

    private func sortedFolders(_ list: [String]) -> [String] {
        Array(Set(list)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func removeEmptyTrashFolders() {
        for sub in scan(trashRoot).subdirs {
            let rest = (try? fm.contentsOfDirectory(atPath: sub.path))?.filter { !$0.hasPrefix(".") } ?? []
            if rest.isEmpty { remove(sub) }
        }
    }

    // MARK: Files

    private func write(_ text: String, to url: URL) {
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { target in
            do { try text.write(to: target, atomically: true, encoding: .utf8) } catch { writeError = error }
        }
        if let error = coordError ?? writeError {
            lastError = "Couldn't save note: \(error.localizedDescription)"
        } else {
            lastError = nil
            signature = currentSignature()
        }
    }

    private func move(_ source: URL, to destination: URL) -> Bool {
        var coordError: NSError?
        var moveError: Error?
        NSFileCoordinator().coordinate(writingItemAt: source, options: .forMoving,
                                       writingItemAt: destination, options: .forReplacing,
                                       error: &coordError) { from, to in
            do {
                if self.fm.fileExists(atPath: to.path) { try self.fm.removeItem(at: to) }
                try self.fm.moveItem(at: from, to: to)
            } catch { moveError = error }
        }
        if let error = coordError ?? moveError {
            lastError = "Couldn't move: \(error.localizedDescription)"
            return false
        }
        lastError = nil
        return true
    }

    private func remove(_ url: URL) {
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordError) { target in
            try? self.fm.removeItem(at: target)
        }
    }

    /// Note files (with dates) and visible subfolders directly inside `dir`.
    private func scan(_ dir: URL) -> (files: [URL: Date], subdirs: [URL]) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return ([:], []) }
        var files: [URL: Date] = [:]
        var subdirs: [URL] = []
        for url in items {
            let name = url.lastPathComponent
            if name.hasPrefix(".") {
                if name.hasSuffix(".icloud") {
                    // In iCloud but not downloaded to this Mac yet: ask for it.
                    let real = dir.appending(path: String(name.dropFirst().dropLast(".icloud".count)))
                    try? fm.startDownloadingUbiquitousItem(at: real)
                }
                continue
            }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                subdirs.append(url)
            } else if ["md", "txt"].contains(url.pathExtension.lowercased()) {
                files[url] = values?.contentModificationDate ?? .distantPast
            }
        }
        return (files, subdirs)
    }

    /// Every note file plus every folder, so new or removed folders count as changes too.
    private func currentSignature() -> [URL: Date] {
        var sig: [URL: Date] = [:]
        func add(_ dir: URL, recurse: Bool) {
            let s = scan(dir)
            sig.merge(s.files) { a, _ in a }
            for sub in s.subdirs {
                sig[sub] = .distantPast
                if recurse { add(sub, recurse: false) }
            }
        }
        add(root, recurse: true)  // includes Trash and its subfolders
        return sig
    }

    func reloadIfChanged() {
        let sig = currentSignature()
        guard sig != signature else { return }
        signature = sig

        let top = scan(root)
        var loaded = load(top.files, folder: nil)
        var names: [String] = []
        for sub in top.subdirs where sub.lastPathComponent != Self.trashName {
            let name = sub.lastPathComponent
            names.append(name)
            loaded += load(scan(sub).files, folder: name)
        }
        notes = loaded.sorted { $0.modified > $1.modified }
        folders = sortedFolders(names)

        let trash = scan(trashRoot)
        var bin = load(trash.files, folder: nil)
        for sub in trash.subdirs { bin += load(scan(sub).files, folder: sub.lastPathComponent) }
        trashed = bin.sorted { $0.modified > $1.modified }
    }

    private func load(_ files: [URL: Date], folder: String?) -> [Note] {
        files.compactMap { url, date in
            var text: String?
            var err: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { target in
                text = try? String(contentsOf: target, encoding: .utf8)
            }
            guard let text else { return nil }
            return Note(id: url.deletingPathExtension().lastPathComponent, text: text, modified: date, folder: folder)
        }
    }
}
