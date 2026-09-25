import Foundation

public struct TodoScanner: Sendable {
    private static let targetMarkers = ["TODO", "FIXME", "HACK", "XXX"]
    private static let maxFileSize = 1_000_000 // 1 MB limit

    public init() {}

    public func scan(
        at repoURL: URL,
        changedFiles: [String],
        maxCount: Int = 25
    ) -> [TodoItem] {
        var foundTodos: [TodoItem] = []
        var scannedPaths = Set<String>()

        // 1. Scan changed files first (prioritized)
        for relativePath in changedFiles {
            guard foundTodos.count < maxCount else { break }
            let fileURL = repoURL.appendingPathComponent(relativePath).standardizedFileURL
            scannedPaths.insert(fileURL.path)
            let items = scanFile(at: fileURL, relativePath: relativePath, isInsideChangedFile: true)
            foundTodos.append(contentsOf: items)
        }

        if foundTodos.count >= maxCount {
            return Array(foundTodos.prefix(maxCount))
        }

        // 2. Scan other source files if budget remains
        let standardizedRepoURL = repoURL.standardizedFileURL
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: standardizedRepoURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return foundTodos
        }

        for case let fileURL as URL in enumerator {
            guard foundTodos.count < maxCount else { break }

            let standardizedFile = fileURL.standardizedFileURL
            if scannedPaths.contains(standardizedFile.path) {
                continue
            }
            scannedPaths.insert(standardizedFile.path)

            let relativePath = standardizedFile.path.replacingOccurrences(of: standardizedRepoURL.path + "/", with: "")

            // Skip ignored directories
            if relativePath.contains("/.") ||
               relativePath.contains("node_modules/") ||
               relativePath.contains(".build/") ||
               relativePath.contains("DerivedData/") ||
               relativePath.contains("vendor/") ||
               SecretFilter.isSecretFile(path: relativePath) {
                continue
            }

            // Check file extension
            let ext = fileURL.pathExtension.lowercased()
            let validExtensions: Set<String> = [
                "swift", "ts", "tsx", "js", "jsx", "py", "rs", "go",
                "c", "cpp", "h", "hpp", "java", "kt", "rb", "php", "md"
            ]
            guard validExtensions.contains(ext) else { continue }

            let items = scanFile(at: fileURL, relativePath: relativePath, isInsideChangedFile: false)
            foundTodos.append(contentsOf: items)
        }

        return Array(foundTodos.prefix(maxCount))
    }

    private func scanFile(at fileURL: URL, relativePath: String, isInsideChangedFile: Bool) -> [TodoItem] {
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? Int,
              size <= Self.maxFileSize else {
            return []
        }

        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }

        var results: [TodoItem] = []
        let lines = content.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            for marker in Self.targetMarkers {
                if let range = line.range(of: marker) {
                    // Extract comment remainder
                    let commentRemainder = String(line[range.upperBound...])
                        .trimmingCharacters(in: CharacterSet(charactersIn: ": -*#//\t"))
                    let cleanComment = commentRemainder.isEmpty ? line.trimmingCharacters(in: .whitespaces) : commentRemainder

                    results.append(TodoItem(
                        file: relativePath,
                        line: index + 1,
                        kind: marker,
                        comment: cleanComment,
                        isInsideChangedFile: isInsideChangedFile
                    ))
                    break
                }
            }
        }

        return results
    }
}
