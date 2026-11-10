import Foundation
import Observation
import AppKit

/// Notes are plain `.md` files in iCloud Drive › CW Notebook (or ~/Documents if iCloud
/// Drive is off). Deleted notes move to a `Trash` folder inside it, so they sync too.
/// iCloud syncs the folder between Macs; the store polls it so edits made elsewhere
/// show up here.
@Observable @MainActor
final class NotebookStore {
    private(set) var notes: [Note] = []
    /// Notes in the Trash, most recently deleted first.
    private(set) var trashed: [Note] = []
    var lastError: String?

    let folder: URL
    let usesICloud: Bool
    var trashFolder: URL { folder.appending(path: "Trash", directoryHint: .isDirectory) }

    @ObservationIgnored private var signature: [URL: Date] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let fm = FileManager.default

    init() {
        let iCloudDrive = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: iCloudDrive.path) {
            folder = iCloudDrive.appending(path: "CW Notebook", directoryHint: .isDirectory)
            usesICloud = true
        } else {
            folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appending(path: "CW Notebook", directoryHint: .isDirectory)
            usesICloud = false
        }
        try? fm.createDirectory(at: trashFolder, withIntermediateDirectories: true)
        reloadIfChanged()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadIfChanged() }
        }
    }

    func note(_ id: Note.ID) -> Note? { notes.first { $0.id == id } }
    func trashedNote(_ id: Note.ID) -> Note? { trashed.first { $0.id == id } }

    private func url(for id: Note.ID) -> URL { folder.appending(path: "\(id).md") }
    private func trashURL(for id: Note.ID) -> URL { trashFolder.appending(path: "\(id).md") }

    // MARK: Editing

    func create() -> Note {
        let note = Note(id: UUID().uuidString, text: "", modified: Date())
        write(note.text, to: url(for: note.id))
        notes.insert(note, at: 0)
        return note
    }

    func save(_ id: Note.ID, text: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }), notes[i].text != text else { return }
        write(text, to: url(for: id))
        notes[i].text = text
        notes[i].modified = Date()
        notes.sort { $0.modified > $1.modified }
    }

    // MARK: Trash

    func moveToTrash(_ id: Note.ID) {
        guard var note = note(id), move(url(for: id), to: trashURL(for: id)) else { return }
        // The file's date becomes the deletion date, so the Trash lists newest first.
        note.modified = Date()
        try? fm.setAttributes([.modificationDate: note.modified], ofItemAtPath: trashURL(for: id).path)
        notes.removeAll { $0.id == id }
        trashed.insert(note, at: 0)
        signature = currentSignature()
    }

    func restore(_ id: Note.ID) {
        guard let note = trashedNote(id), move(trashURL(for: id), to: url(for: id)) else { return }
        trashed.removeAll { $0.id == id }
        notes.append(note)
        notes.sort { $0.modified > $1.modified }
        signature = currentSignature()
    }

    func deletePermanently(_ id: Note.ID) {
        remove(trashURL(for: id))
        trashed.removeAll { $0.id == id }
        signature = currentSignature()
    }

    func emptyTrash() {
        for note in trashed { remove(trashURL(for: note.id)) }
        trashed.removeAll()
        signature = currentSignature()
    }

    /// For a new note left blank: removed outright rather than put in the Trash.
    func discard(_ id: Note.ID) {
        remove(url(for: id))
        notes.removeAll { $0.id == id }
        signature = currentSignature()
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([folder])
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
            lastError = "Couldn't move note: \(error.localizedDescription)"
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

    private func files(in dir: URL) -> [URL: Date] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return [:] }
        var result: [URL: Date] = [:]
        for url in items {
            let name = url.lastPathComponent
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                // In iCloud but not downloaded to this Mac yet: ask for it.
                let real = dir.appending(path: String(name.dropFirst().dropLast(".icloud".count)))
                try? fm.startDownloadingUbiquitousItem(at: real)
                continue
            }
            guard ["md", "txt"].contains(url.pathExtension.lowercased()) else { continue }
            result[url] = (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
        }
        return result
    }

    private func currentSignature() -> [URL: Date] {
        files(in: folder).merging(files(in: trashFolder)) { a, _ in a }
    }

    func reloadIfChanged() {
        let sig = currentSignature()
        guard sig != signature else { return }
        signature = sig
        notes = load(files(in: folder))
        trashed = load(files(in: trashFolder))
    }

    private func load(_ files: [URL: Date]) -> [Note] {
        files.compactMap { url, date in
            var text: String?
            var err: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { target in
                text = try? String(contentsOf: target, encoding: .utf8)
            }
            guard let text else { return nil }
            return Note(id: url.deletingPathExtension().lastPathComponent, text: text, modified: date)
        }
        .sorted { $0.modified > $1.modified }
    }
}
