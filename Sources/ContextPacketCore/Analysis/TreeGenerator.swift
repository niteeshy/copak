import Foundation

public struct TreeGenerator: Sendable {
    private static let ignoredDirectoryNames: Set<String> = [
        ".git",
        "node_modules",
        "Pods",
        "DerivedData",
        ".build",
        "dist",
        "build",
        "out",
        ".next",
        ".nuxt",
        "coverage",
        "vendor",
        ".cache",
        "tmp",
        "temp",
        ".venv",
        "venv",
        "env",
        "__pycache__",
        ".idea",
        ".vscode",
        ".DS_Store"
    ]

    public init() {}

    public func generateCompactTree(
        at rootURL: URL,
        maxDepth: Int = 3,
        maxLines: Int = 65
    ) -> String {
        var lines: [String] = []
        let rootName = rootURL.lastPathComponent

        lines.append("\(rootName)/")
        var currentLineCount = 1

        func traverse(url: URL, depth: Int, prefix: String) {
            guard depth <= maxDepth, currentLineCount < maxLines else { return }

            let fileManager = FileManager.default
            guard let enumerator = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            let sortedItems = enumerator.sorted { $0.lastPathComponent < $1.lastPathComponent }

            for (index, itemURL) in sortedItems.enumerated() {
                if currentLineCount >= maxLines {
                    lines.append("\(prefix)└── ... [truncated]")
                    currentLineCount += 1
                    break
                }

                let name = itemURL.lastPathComponent

                // Filter junk directories and secret files
                if Self.ignoredDirectoryNames.contains(name) || SecretFilter.isSecretFile(path: name) {
                    continue
                }

                let isLast = index == sortedItems.count - 1
                let connector = isLast ? "└── " : "├── "
                let childPrefix = prefix + (isLast ? "    " : "│   ")

                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    lines.append("\(prefix)\(connector)\(name)/")
                    currentLineCount += 1
                    traverse(url: itemURL, depth: depth + 1, prefix: childPrefix)
                } else {
                    lines.append("\(prefix)\(connector)\(name)")
                    currentLineCount += 1
                }
            }
        }

        traverse(url: rootURL, depth: 1, prefix: "")
        return lines.joined(separator: "\n")
    }
}
