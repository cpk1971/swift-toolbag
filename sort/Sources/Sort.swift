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

    @Flag(
        name: [.long, .customShort("i")],
        help: "ignore case in sort order"
    )
    var ignoreCase: Bool = false

    mutating func run() async throws {
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

        var transform: StringUnaryOperator = { $0 }
        
        // will build these iterably as we have more
        if(ignoreLeadingWhitespace) {
            transform = { $0.replacing(#/^ */#, with: "") }
        }

        if(ignoreCase) {
            transform = composeTransform(from: transform, and: { $0.lowercased() })
        }

        let predicate = 
            composePredicate(from: transform, and: reverseOrder ? (>) : (<))
        lines.sorted(by: predicate).forEach { print($0) }
    }
}

internal typealias StringUnaryOperator = (String) -> String
internal typealias StringPredicate = (String, String) -> Bool

internal func composePredicate(
        from transform: @escaping StringUnaryOperator, 
        and predicate: @escaping StringPredicate) -> StringPredicate {
    { predicate(transform($0), transform($1)) }
}

internal func composeTransform(
    from transform: @escaping StringUnaryOperator, 
    and otherTransform: @escaping StringUnaryOperator) -> StringUnaryOperator {
    
    { transform(otherTransform($0)) }
}