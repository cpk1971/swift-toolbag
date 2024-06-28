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

    @Flag(
        name: [.long, .customShort("b")],
        help: "leading whitespace doesn't affect sorting")
    var ignoreLeadingWhitespace = false

    @Flag(
        name: [.long, .short],
        help: "reverse sort order")
    var reverseOrder: Bool = false

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

        var transform = nop
        
        // will build these iterably as we have more
        if(ignoreLeadingWhitespace) {
            transform = compareIgnoreLeading
        }

        let direction: StringPredicate = reverseOrder ? (>) : (<)
        let predicate = composeFrom(transform: transform, predicate: direction)
        lines.sorted(by: predicate).forEach { print($0) }
    }
}

internal typealias StringUnaryOperator = (String) -> String
internal typealias StringPredicate = (String, String) -> Bool

internal func composeFrom(transform: @escaping StringUnaryOperator, predicate: @escaping StringPredicate) -> StringPredicate {
    { predicate(transform($0), transform($1)) }
}

internal func nop(_ a: String) -> String {
    a
}

@available(macOS 13.0, *)
internal func compareIgnoreLeading(_ a: String) -> String {
    a.replacing(#/^ */#, with: "")    
}