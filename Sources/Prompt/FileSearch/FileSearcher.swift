import Foundation

/// Protocol for file search implementations
public protocol FileSearcher {
    /// Search for files matching the given query
    /// - Parameters:
    ///   - query: Search string to match against filenames
    ///   - searchPath: Optional custom search path to override default
    /// - Returns: Array of matching file paths
    func search(query: String, searchPath: String?) -> [String]
}
