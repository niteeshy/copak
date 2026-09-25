import Foundation

public struct ProjectDetector: Sendable {
    public init() {}

    public func detect(at repoURL: URL) -> ProjectMetadata {
        let fileManager = FileManager.default
        let items = (try? fileManager.contentsOfDirectory(atPath: repoURL.path)) ?? []
        let itemSet = Set(items)

        // 1. Swift / Apple
        if itemSet.contains("Package.swift") || items.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
            var configs: [String] = []
            if itemSet.contains("Package.swift") { configs.append("Package.swift") }
            for item in items where item.hasSuffix(".xcodeproj") || item.hasSuffix(".xcworkspace") {
                configs.append(item)
            }

            return ProjectMetadata(
                ecosystem: "Swift",
                language: "Swift",
                framework: configs.contains(where: { $0.contains("Package.swift") }) ? "SwiftPM" : "Xcode",
                packageManager: "Swift Package Manager",
                applicationType: "macOS / iOS / CLI",
                buildSystem: "swift build / xcodebuild",
                detectedConfigFiles: configs,
                scripts: ["build": "swift build", "test": "swift test"],
                topDependencies: []
            )
        }

        // 2. JavaScript / TypeScript / Node
        if itemSet.contains("package.json") {
            return parseNodeProject(at: repoURL, itemSet: itemSet)
        }

        // 3. Rust
        if itemSet.contains("Cargo.toml") {
            return ProjectMetadata(
                ecosystem: "Rust",
                language: "Rust",
                framework: "Cargo",
                packageManager: "cargo",
                applicationType: "CLI / Systems / WebAssembly",
                buildSystem: "cargo build",
                detectedConfigFiles: ["Cargo.toml"],
                scripts: ["build": "cargo build", "test": "cargo test", "run": "cargo run"],
                topDependencies: []
            )
        }

        // 4. Go
        if itemSet.contains("go.mod") {
            return ProjectMetadata(
                ecosystem: "Go",
                language: "Go",
                framework: "Go Modules",
                packageManager: "go",
                applicationType: "Backend / CLI / Microservice",
                buildSystem: "go build",
                detectedConfigFiles: ["go.mod"],
                scripts: ["build": "go build ./...", "test": "go test ./..."],
                topDependencies: []
            )
        }

        // 5. Python
        if itemSet.contains("pyproject.toml") || itemSet.contains("requirements.txt") || itemSet.contains("setup.py") {
            var configs: [String] = []
            if itemSet.contains("pyproject.toml") { configs.append("pyproject.toml") }
            if itemSet.contains("requirements.txt") { configs.append("requirements.txt") }
            if itemSet.contains("setup.py") { configs.append("setup.py") }

            return ProjectMetadata(
                ecosystem: "Python",
                language: "Python",
                framework: itemSet.contains("pyproject.toml") ? "Modern Python" : "Pip / Virtualenv",
                packageManager: itemSet.contains("poetry.lock") ? "Poetry" : (itemSet.contains("Pipfile") ? "Pipenv" : "pip"),
                applicationType: "Application / Library",
                buildSystem: "python",
                detectedConfigFiles: configs,
                scripts: ["run": "python main.py"],
                topDependencies: []
            )
        }

        // Fallback: Generic
        var genericConfigs: [String] = []
        for file in ["Makefile", "Dockerfile", "docker-compose.yml", "CMakeLists.txt"] {
            if itemSet.contains(file) {
                genericConfigs.append(file)
            }
        }

        return ProjectMetadata(
            ecosystem: "Generic",
            language: nil,
            framework: nil,
            packageManager: nil,
            applicationType: "Software Project",
            buildSystem: genericConfigs.first,
            detectedConfigFiles: genericConfigs,
            scripts: [:],
            topDependencies: []
        )
    }

    private func parseNodeProject(at repoURL: URL, itemSet: Set<String>) -> ProjectMetadata {
        let packageJsonURL = repoURL.appendingPathComponent("package.json")
        var scripts: [String: String] = [:]
        var topDeps: [String] = []
        var detectedFramework: String? = nil

        if let data = try? Data(contentsOf: packageJsonURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let scriptsDict = json["scripts"] as? [String: String] {
                scripts = scriptsDict
            }

            var allDeps: [String] = []
            if let deps = json["dependencies"] as? [String: String] {
                allDeps.append(contentsOf: deps.keys)
            }
            if let devDeps = json["devDependencies"] as? [String: String] {
                allDeps.append(contentsOf: devDeps.keys)
            }

            topDeps = Array(allDeps.prefix(10))

            // Identify prominent frameworks
            if allDeps.contains("next") {
                detectedFramework = "Next.js"
            } else if allDeps.contains("react") {
                detectedFramework = "React"
            } else if allDeps.contains("vue") {
                detectedFramework = "Vue"
            } else if allDeps.contains("svelte") || allDeps.contains("@sveltejs/kit") {
                detectedFramework = "Svelte"
            } else if allDeps.contains("express") {
                detectedFramework = "Express"
            } else if allDeps.contains("vite") {
                detectedFramework = "Vite"
            }
        }

        let isTypeScript = itemSet.contains("tsconfig.json")
        let packageManager = itemSet.contains("pnpm-lock.yaml") ? "pnpm" :
                             (itemSet.contains("yarn.lock") ? "yarn" :
                             (itemSet.contains("bun.lockb") || itemSet.contains("bun.lock") ? "bun" : "npm"))

        var configs = ["package.json"]
        if isTypeScript { configs.append("tsconfig.json") }
        if itemSet.contains("vite.config.ts") || itemSet.contains("vite.config.js") { configs.append("vite.config") }
        if itemSet.contains("next.config.js") || itemSet.contains("next.config.mjs") || itemSet.contains("next.config.ts") { configs.append("next.config") }

        return ProjectMetadata(
            ecosystem: isTypeScript ? "TypeScript / Node" : "JavaScript / Node",
            language: isTypeScript ? "TypeScript" : "JavaScript",
            framework: detectedFramework ?? (isTypeScript ? "TypeScript" : "Node.js"),
            packageManager: packageManager,
            applicationType: (detectedFramework != nil) ? "Web Application" : "Node.js Application",
            buildSystem: packageManager,
            detectedConfigFiles: configs,
            scripts: scripts,
            topDependencies: topDeps
        )
    }
}
