//
//  NotesStore.swift
//  Classic
//
//  Plain-text notes stored as files in <Documents>/Notes/, just like the
//  "Notes" folder on a disk-mode iPod. The folder is exposed in the Files app
//  (UIFileSharingEnabled), so users can drop their own .txt files in.
//

import UIKit

struct Note: Equatable {
    let url: URL
    /// Filename without extension.
    var title: String { url.deletingPathExtension().lastPathComponent }
}

enum NotesStore {

    static let allowedExtensions: Set<String> = ["txt", "text", "md"]
    private static let seededKey = "classic.notes.seeded"
    private static let maxTitleLength = 40

    // MARK: - Locations

    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return docs.appendingPathComponent("Notes", isDirectory: true)
    }

    @discardableResult
    static func ensureDirectory() -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: directory.path, isDirectory: &isDir) {
            if isDir.boolValue { return true }
            // A stray file named "Notes" — move it aside so the folder can exist.
            try? fm.moveItem(at: directory, to: directory.deletingLastPathComponent().appendingPathComponent("Notes (file)"))
        }
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            return true
        } catch {
            print("NotesStore: could not create Notes folder: \(error)")
            return false
        }
    }

    /// Writes the Welcome note on the very first launch.
    static func seedIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: seededKey) else { return }
        guard ensureDirectory() else { return }
        let url = directory.appendingPathComponent("Welcome.txt")
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try welcomeText.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("NotesStore: could not write Welcome note: \(error)")
                return
            }
        }
        defaults.set(true, forKey: seededKey)
    }

    private static let welcomeText = """
    Welcome

    Notes lets you carry short pieces of text around with your iPod: lyrics, directions, shopping lists, a few pages of a story.

    Reading
    Choose a note from the Notes menu and press the center button. Turn the click wheel to scroll through the text. Press Next or Previous to jump a whole page. Press Menu to go back.

    Adding notes from your computer or iPhone
    Notes are plain text files. Open the Files app and go to On My iPhone > Classic > Notes, then copy any .txt file into that folder. It shows up in the Notes menu straight away, named after the file.

    Creating notes
    Choose "New Note" at the top of the Notes menu and type with the keyboard. The first line of the note becomes its name. Tap Save when you're done.

    Editing and deleting
    While reading a note, press the center button to open its menu. Choose Edit to change the text, or Delete to remove the note.
    """

    // MARK: - Listing & reading

    /// All readable notes, sorted case-insensitively by title.
    static func allNotes() -> [Note] {
        seedIfNeeded()
        guard ensureDirectory() else { return [] }
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])
        } catch {
            print("NotesStore: could not list Notes folder: \(error)")
            return []
        }
        let notes = urls.compactMap { url -> Note? in
            guard allowedExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            guard isFile, readText(at: url) != nil else { return nil }
            return Note(url: url)
        }
        return notes.sorted {
            let r = $0.title.localizedCaseInsensitiveCompare($1.title)
            if r == .orderedSame { return $0.url.lastPathComponent < $1.url.lastPathComponent }
            return r == .orderedAscending
        }
    }

    static func read(_ note: Note) -> String? {
        return readText(at: note.url)
    }

    /// Tolerant decoding: UTF-8 first, then whatever Foundation can detect,
    /// then a few common legacy encodings.
    static func readText(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        var text: String?
        if let s = String(data: data, encoding: .utf8) {
            text = s
        } else {
            var used: String.Encoding = .utf8
            if let s = try? String(contentsOf: url, usedEncoding: &used) {
                text = s
            } else {
                for enc in [String.Encoding.utf16, .windowsCP1252, .isoLatin1, .macOSRoman] {
                    if let s = String(data: data, encoding: enc) { text = s; break }
                }
            }
        }
        guard var result = text else { return nil }
        if result.hasPrefix("\u{FEFF}") { result.removeFirst() }
        return result
    }

    // MARK: - Writing

    /// Creates a new note named after its first line. Returns nil for blank text or on failure.
    static func create(text: String) -> Note? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard ensureDirectory() else { return nil }
        let url = uniqueURL(for: title(fromText: text), ext: "txt", excluding: nil)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return Note(url: url)
        } catch {
            print("NotesStore: could not create note: \(error)")
            return nil
        }
    }

    /// Overwrites a note. If the first line changed, the file is renamed to match.
    /// Returns the (possibly renamed) note, or nil if the write failed.
    static func update(_ note: Note, oldText: String, newText: String) -> Note? {
        let fm = FileManager.default
        do {
            try newText.write(to: note.url, atomically: true, encoding: .utf8)
        } catch {
            print("NotesStore: could not save note: \(error)")
            return nil
        }
        let oldTitle = title(fromText: oldText)
        let newTitle = title(fromText: newText)
        // Keep the filename if the note was emptied or its first line is unchanged.
        guard !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              newTitle != oldTitle, newTitle != note.title else { return note }

        var ext = note.url.pathExtension
        if ext.isEmpty { ext = "txt" }
        let target = uniqueURL(for: newTitle, ext: ext, excluding: note.url)
        do {
            if target.lastPathComponent.lowercased() == note.url.lastPathComponent.lowercased() {
                // Case-only rename: go via a temporary name for case-insensitive volumes.
                let temp = directory.appendingPathComponent(".rename-\(UUID().uuidString).\(ext)")
                try fm.moveItem(at: note.url, to: temp)
                do {
                    try fm.moveItem(at: temp, to: target)
                } catch {
                    try? fm.moveItem(at: temp, to: note.url)
                    throw error
                }
            } else {
                try fm.moveItem(at: note.url, to: target)
            }
            return Note(url: target)
        } catch {
            print("NotesStore: could not rename note: \(error)")
            return note
        }
    }

    @discardableResult
    static func delete(_ note: Note) -> Bool {
        do {
            try FileManager.default.removeItem(at: note.url)
            return true
        } catch {
            print("NotesStore: could not delete note: \(error)")
            return false
        }
    }

    // MARK: - Naming

    /// A filesystem-safe title from the first non-blank line of the text.
    static func title(fromText text: String) -> String {
        let firstLine = text
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        return sanitise(firstLine)
    }

    static func sanitise(_ raw: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        var s = String(String.UnicodeScalarView(raw.unicodeScalars.map { illegal.contains($0) ? "-" : $0 }))
        s = s.trimmingCharacters(in: .whitespaces)
        while s.hasPrefix(".") { s.removeFirst() }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.count > maxTitleLength {
            s = String(s.prefix(maxTitleLength)).trimmingCharacters(in: .whitespaces)
        }
        return s.isEmpty ? "Untitled" : s
    }

    /// "Title.ext", or "Title 2.ext", "Title 3.ext"… avoiding any existing file
    /// (case-insensitively) other than `excluding`.
    private static func uniqueURL(for title: String, ext: String, excluding: URL?) -> URL {
        let existing = Set(((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.lowercased() != excluding?.lastPathComponent.lowercased() }
            .map { $0.lowercased() })
        var n = 1
        while true {
            let name = n == 1 ? "\(title).\(ext)" : "\(title) \(n).\(ext)"
            if !existing.contains(name.lowercased()) {
                return directory.appendingPathComponent(name)
            }
            n += 1
        }
    }
}
