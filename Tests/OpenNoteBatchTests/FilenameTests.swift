import Foundation
import Testing
@testable import OpenNoteBatch

@Suite("Filenames")
struct FilenameTests {
    @Test func sanitizesInvalidCharacters() {
        #expect(Filename.safe("bad/name:with?chars.docx") == "bad_name:with_chars.docx")
    }

    @Test func emptyNameUsesFallback() {
        #expect(Filename.safe("...") == "Untitled")
    }

    @Test func uniquePathAddsCounter() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent("file.txt"))

        let unique = Filename.unique(in: directory, name: "file.txt")

        #expect(unique.lastPathComponent == "file (2).txt")
    }
}

