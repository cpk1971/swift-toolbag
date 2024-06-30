import ArgumentParser
import Darwin
import Foundation

@main
@available(macOS 15, *)
struct Sort : AsyncParsableCommand {
    @Argument(
        help: "A file to sort.  If omitted, sorts lines from stdin",
        completion: .file(),
        transform: URL.init(fileURLWithPath:))
    var inputFile: URL? = nil

    @Option(
        name: [.long, .customShort("m")],
        help: "Maximum in-memory usage in bytes--if exceeded, writes to temp files and merge sorts them")
    var maxStringMemory: Int?

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
        var lines: [String] = []
        var cacheFiles: [URL] = []
        var totalMem = 0

        let fileHandle = if let inputFile {
            try FileHandle(forReadingFrom: inputFile)
        } else {
            FileHandle.standardInput
        }

        let sortPredicate = sortPredicate()

        let cache: () -> () = {
            let tempFile = Sort.cacheLinesToFile(lines.sorted(by: sortPredicate))
            cacheFiles.append(tempFile)
        }


        try await Sort.processLines(from: fileHandle) { line in
            lines.append(line)
            totalMem += line.lengthOfBytes(using: String.Encoding.unicode)

            if let maxStringMemory {
                if totalMem > maxStringMemory {
                    cache()
                    lines.removeAll()
                    totalMem = 0
                }
            }
        }

        if cacheFiles.isEmpty {
            lines.sorted(by: sortPredicate).forEach { print($0) } 
        } else {
            cache()
            try await mergeAndPrint(cacheFiles: cacheFiles)
        }
    }

    private static func processLines(from fileHandle: FileHandle, onEachLine: (String) -> ()) async throws {
        for try await line: String in fileHandle.bytes.lines {
            onEachLine(line)
        }
    }

    private func sortPredicate() -> StringPredicate {
        var transform: StringUnaryOperator = { $0 }
        
        // will build these iterably as we have more
        if(ignoreLeadingWhitespace) {
            transform = { $0.replacing(#/^ */#, with: "") }
        }

        if(ignoreCase) {
            transform = composeTransform(from: transform, and: { $0.lowercased() })
        }

        return 
            composePredicate(from: transform, and: reverseOrder ? (>) : (<))
    }

    private static func cacheLinesToFile(_ lines: [String]) -> URL {
        let (tempFileName, fileHandle) = openTempFile()
        defer {
            try! fileHandle.close()
        }

        do {
            try lines.forEach {
                let data = ($0 + "\n").data(using: .unicode)!
                try fileHandle.write(contentsOf: data)
            }
        
            return tempFileName
        } catch {
            printStderr("Couldn't write temp file: \(error)")
            die(withExitCode: 1)
            fatalError("unreachable")
        }
    }

    private static func openTempFile() -> (fileName: URL, handle: FileHandle) {
        let tempFileName = URL.temporaryDirectory
            .appending(path:UUID().uuidString, directoryHint: .notDirectory)
        FileManager.default.createFile(atPath: tempFileName.relativePath, contents: nil)

        do {
            return  (tempFileName, try FileHandle(forWritingTo: tempFileName))
        } catch {
            printStderr("Couldn't create temp file: \(error)")
            die(withExitCode: 1)
            fatalError("unreachable")
        }
    }

    private mutating func mergeAndPrint(cacheFiles: [URL]) async throws {
        var cacheFiles = cacheFiles

        while (cacheFiles.count > 1) {
            let newCacheFile = await mergeCacheFile(cacheFiles.removeFirst(), with: cacheFiles.removeFirst())
            cacheFiles.append(newCacheFile)
        }

        let handle = try FileHandle(forReadingFrom:cacheFiles[0])
        try await Sort.processLines(from: handle) {
            print($0)
        }
    }

    private mutating func mergeCacheFile(_ file1: URL, with file2: URL) async -> URL {
        let (tempFileName, wh) = Sort.openTempFile() 

        do {
            let h1 = try FileHandle(forReadingFrom: file1)
            let h2 = try FileHandle(forReadingFrom: file2)
            let sortPredicate = sortPredicate()

            defer {
                try! h1.close()
                try! h2.close()
            }

            let write: (String) throws -> () = {
                let data = ($0 + "\n").data(using: .unicode)!
                try wh.write(contentsOf: data)
            }

            var i1 = h1.bytes.lines.makeAsyncIterator()
            var i2 = h2.bytes.lines.makeAsyncIterator()

            var line1: String? = try await i2.next()
            var line2: String? = try await i2.next()

            repeat {
                if line1 == .none && line2 != .none {
                    repeat {
                        try write(line2!)
                        line2 = try await i2.next() 
                    } while line2 != .none
                } else if line2 == .none && line1 != .none {
                    repeat {
                        try write(line1!)
                        line1 = try await i1.next()
                    } while line1 != .none
                } else if line1 != .none && line2 != .none {
                    if sortPredicate(line1!, line2!) {
                        try write(line1!)
                        line1 = try await i1.next()
                    } else {
                        try write(line2!)
                        line2 = try await i2.next()
                    }
                }
            } while line1 != .none && line2 != .none

            return tempFileName
        } catch {
            printStderr("couldn't merge \(file1.relativePath) with \(file2.relativePath): \(error)")
            die(withExitCode: 1)
            fatalError("unreachable")
        }
    }
}

// we have to use this because "exit" is shadowed in AsyncParsableCommand
internal func die(withExitCode code: Int32) {
    exit(code)
}

@available(macOS 15, *)
internal func printStderr(_ message: String) {
    let data = ("\n" + message + "\n").data(using: .utf8)!
    try! FileHandle.standardError.write(contentsOf: data)
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