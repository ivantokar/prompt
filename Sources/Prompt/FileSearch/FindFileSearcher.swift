import Foundation

/// File searcher using the `find` command
public final class FindFileSearcher: FileSearcher {
    private let searchPath: String
    private let maxDepth: Int
    private let timeout: TimeInterval
    private let maxResults: Int

    public init(
        searchPath: String? = nil,
        maxDepth: Int = 2,  // Reduced from 5 to 2 for better performance
        timeout: TimeInterval = 0.5,  // Reduced from 1.0 to 0.5
        maxResults: Int = 7
    ) {
        // Default to current directory
        self.searchPath = searchPath ?? FileManager.default.currentDirectoryPath
        self.maxDepth = maxDepth
        self.timeout = timeout
        self.maxResults = maxResults
    }

    public func search(query: String, searchPath overridePath: String? = nil) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/find")

        // Use override path if provided, otherwise use default
        let effectiveSearchPath = overridePath ?? searchPath

        // Build arguments - if query is empty, show common file types
        var arguments = [
            effectiveSearchPath,
            "-maxdepth", "\(maxDepth)",
            "-type", "f"
        ]

        // Add name filter only if query is not empty
        if !query.isEmpty {
            arguments.append(contentsOf: ["-name", "*\(query)*"])
        }

        // Exclude common heavy directories (improves performance significantly)
        arguments.append(contentsOf: [
            "-not", "-path", "*/.*",               // Hidden files/dirs
            "-not", "-path", "*/node_modules/*",   // Node.js
            "-not", "-path", "*/.git/*",           // Git
            "-not", "-path", "*/.build/*",         // Swift build
            "-not", "-path", "*/build/*",          // Generic build
            "-not", "-path", "*/dist/*",           // Distribution
            "-not", "-path", "*/target/*",         // Rust/Java
            "-not", "-path", "*/vendor/*",         // Dependencies
            "-not", "-path", "*/__pycache__/*",    // Python cache
            "-not", "-path", "*/venv/*",           // Python virtual env
            "-not", "-path", "*/.venv/*",          // Python virtual env
            "-not", "-path", "*/Library/*",        // macOS Library
            "-not", "-path", "*/DerivedData/*"     // Xcode
        ])

        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // Suppress errors

        do {
            try process.run()

            // Timeout handling
            let timedOut = DispatchSemaphore(value: 0)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    process.terminate()
                }
                timedOut.signal()
            }

            // Wait for completion or timeout
            process.waitUntilExit()
            timedOut.signal()

            // Read results
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }

            let files = output.split(separator: "\n").map(String.init)

            // Make paths relative for cleaner display
            return files
                .map { makeRelativePath($0) }
                .sorted { $0.count < $1.count } // Prefer shorter paths
                .prefix(maxResults)
                .map { $0 }

        } catch {
            return []
        }
    }

    private func makeRelativePath(_ path: String) -> String {
        let homeDir = NSHomeDirectory()

        // Convert to ~/path notation for home directory
        if path.hasPrefix(homeDir + "/") {
            return "~/" + String(path.dropFirst(homeDir.count + 1))
        } else if path == homeDir {
            return "~"
        }

        // Try current directory if not in home
        let currentDir = FileManager.default.currentDirectoryPath
        if path.hasPrefix(currentDir + "/") {
            return String(path.dropFirst(currentDir.count + 1))
        }

        return path
    }
}
