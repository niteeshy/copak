import Foundation

public struct InstructionFileDetector: Sendable {
    private static let ignoredDirectoryNames: Set<String> = [
        ".git",
        "node_modules",
        ".build",
        "build",
        "Pods",
        "DerivedData",
        "vendor",
        ".venv",
        "venv",
        "env",
        ".gradle",
        "dist",
        ".next",
        ".swiftpm",
        "target"
    ]

    private static let maxInstructionFileCharacters = 25_000

    public init() {}

    public static func detect(at repoURL: URL) -> [InstructionFile] {
        InstructionFileDetector().detect(at: repoURL)
    }

    public func detect(at repoURL: URL) -> [InstructionFile] {
        var found: [InstructionFile] = []
        var seenPaths: Set<String> = []
        let fileManager = FileManager.default

        // 1. Root instruction files
        let rootFiles: [(path: String, scope: String)] = [
            ("AGENTS.md", "root"),
            ("CLAUDE.md", "root"),
            (".cursorrules", "root"),
            (".windsurfrules", "windsurf"),
            (".clinerules", "cline"),
            (".github/copilot-instructions.md", "github-copilot"),
            ("CONTRIBUTING.md", "root")
        ]

        for item in rootFiles {
            let fileURL = repoURL.appendingPathComponent(item.path)
            if fileManager.fileExists(atPath: fileURL.path) && !seenPaths.contains(item.path) {
                if let ingested = ingestInstructionFile(at: fileURL, relativePath: item.path, scope: item.scope) {
                    found.append(ingested)
                    seenPaths.insert(item.path)
                }
            }
        }

        // 2. .cursor/rules/*
        let cursorRulesURL = repoURL.appendingPathComponent(".cursor/rules")
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: cursorRulesURL.path, isDirectory: &isDir), isDir.boolValue {
            if let files = try? fileManager.contentsOfDirectory(atPath: cursorRulesURL.path) {
                for file in files.sorted() where !file.hasPrefix(".") {
                    let subURL = cursorRulesURL.appendingPathComponent(file)
                    let relPath = ".cursor/rules/\(file)"
                    guard !seenPaths.contains(relPath) else { continue }
                    let ruleName = (file as NSString).deletingPathExtension
                    let scope = "cursor-rule: \(ruleName)"
                    if let ingested = ingestInstructionFile(at: subURL, relativePath: relPath, scope: scope) {
                        found.append(ingested)
                        seenPaths.insert(relPath)
                    }
                }
            }
        }

        // 3. Hierarchical / nested AGENTS.md files
        let nestedAgents = scanForNestedAgents(in: repoURL, currentRelativePath: "", depth: 0)
        for (fileURL, relPath, scope) in nestedAgents {
            guard !seenPaths.contains(relPath) else { continue }
            if let ingested = ingestInstructionFile(at: fileURL, relativePath: relPath, scope: scope) {
                found.append(ingested)
                seenPaths.insert(relPath)
            }
        }

        return found
    }

    private func scanForNestedAgents(
        in currentURL: URL,
        currentRelativePath: String,
        depth: Int
    ) -> [(url: URL, relPath: String, scope: String)] {
        guard depth < 4 else { return [] }
        var results: [(url: URL, relPath: String, scope: String)] = []
        let fileManager = FileManager.default

        guard let contents = try? fileManager.contentsOfDirectory(atPath: currentURL.path) else {
            return []
        }

        for item in contents {
            if item.hasPrefix(".") && item != "AGENTS.md" { continue }
            if Self.ignoredDirectoryNames.contains(item) { continue }

            let itemURL = currentURL.appendingPathComponent(item)
            let itemRelPath = currentRelativePath.isEmpty ? item : "\(currentRelativePath)/\(item)"

            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    results.append(contentsOf: scanForNestedAgents(
                        in: itemURL,
                        currentRelativePath: itemRelPath,
                        depth: depth + 1
                    ))
                } else if item.caseInsensitiveCompare("AGENTS.md") == .orderedSame && !currentRelativePath.isEmpty {
                    let scope = currentRelativePath
                    results.append((url: itemURL, relPath: itemRelPath, scope: scope))
                }
            }
        }

        return results
    }

    private func ingestInstructionFile(at fileURL: URL, relativePath: String, scope: String) -> InstructionFile? {
        guard let rawContent = try? String(contentsOf: fileURL, encoding: .utf8),
              !rawContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let isTruncated: Bool
        let contentToStore: String

        if rawContent.count > Self.maxInstructionFileCharacters {
            isTruncated = true
            let prefix = String(rawContent.prefix(Self.maxInstructionFileCharacters))
            contentToStore = "\(prefix)\n\n... [Content truncated at \(Self.maxInstructionFileCharacters) characters]"
        } else {
            isTruncated = false
            contentToStore = rawContent
        }

        // Sanitize content to prevent sensitive tokens or credentials in instruction excerpts
        let sanitizedContent = SecretFilter.sanitizeText(contentToStore)
        let filename = (relativePath as NSString).lastPathComponent

        // Compute useful snippet (first 300 chars or first 4 lines)
        let lines = sanitizedContent.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let snippet = lines.prefix(5).joined(separator: "\n")

        return InstructionFile(
            path: relativePath,
            filename: filename,
            scope: scope,
            content: sanitizedContent,
            isTruncated: isTruncated,
            snippet: snippet.isEmpty ? nil : snippet
        )
    }
}

