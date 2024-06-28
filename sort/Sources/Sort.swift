import ArgumentParser
import Foundation

@main
@available(macOS 15, *)
struct Sort : AsyncParsableCommand {
    @Argument(
        help: "A file to sort.  If omitted, sorts lines from stdin",
        completion: .file(),
        transform: URL.init(fileURLWithPath:))
    var inputFile: URL? = nil

    mutating func run() async throws {
        print("Your file: \(inputFile?.relativePath ?? "<stdin>")")
        try await sort()
    }

    var fileHandle: FileHandle {
        get throws {
            guard let inputFile else {
                return .standardInput
            }
            return try FileHandle(forReadingFrom: inputFile)
        }
    }

    mutating func sort() async throws {
        var lines: [String] = []
        for try await line in try fileHandle.bytes.lines {
            lines.append(line)
        }
        lines.sorted().forEach { print($0) }
    }
}