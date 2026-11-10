import Foundation
import Observation
import AppKit

/// Notes are plain `.md` files in iCloud Drive › CW Notebook (or ~/Documents if iCloud
/// Drive is off). iCloud syncs the folder between Macs; the store polls it so edits
/// made elsewhere show up here.
@Observable @MainActor
final class NotebookStore {
    private(set) var notes: [Note] = []
    var lastError: String?

    let folder: URL
    let usesICloud: Bool

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
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        reloadIfChanged()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadIfChanged() }
        }
    }

    func note(_ id: Note.ID) -> Note? { notes.first { $0.id == id } }

    private func url(for id: Note.ID) -> URL { folder.appending(path: "\(id).md") }

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

    /// Moves the file to the Trash so it can be recovered.
    func delete(_ id: Note.ID) {
        let u = url(for: id)
        do { try fm.trashItem(at: u, resultingItemURL: nil) } catch { try? fm.removeItem(at: u) }
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

    private func currentSignature() -> [URL: Date] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return [:] }
        var result: [URL: Date] = [:]
        for url in items {
            let name = url.lastPathComponent
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                // In iCloud but not downloaded to this Mac yet: ask for it.
                let real = folder.appending(path: String(name.dropFirst().dropLast(".icloud".count)))
                try? fm.startDownloadingUbiquitousItem(at: real)
                continue
            }
            guard ["md", "txt"].contains(url.pathExtension.lowercased()) else { continue }
            result[url] = (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
        }
        return result
    }

    func reloadIfChanged() {
        let sig = currentSignature()
        guard sig != signature else { return }
        signature = sig
        notes = sig.compactMap { url, date in
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
