import SwiftUI
import UniformTypeIdentifiers

struct MeetingTextFile: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.text = text
    }
    var utf8File: FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        utf8File
    }
}
