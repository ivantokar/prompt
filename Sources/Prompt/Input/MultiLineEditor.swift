import Foundation
import CoreFoundation
@_exported import Rainbow

/// Advanced multi-line text editor with file insertion support
public final class MultiLineEditor {
    private let terminal: TerminalController
    private let fileSearcher: FileSearcher
    private let terminalSize: TerminalSize

    private var lines: [String] = []
    private var futureLines: [String] = []
    private var currentLine = ""
    private var suggestions: [String] = []
    private var selectedSuggestion = 0
    private var cancelPressed = false
    private var message: String = ""
    private var placeholder: String? = nil
    private var renderedLineCount = 0
    private var renderedDynamicLineCount = 0
    private var isFirstRender = true
    private var cursorPosition = 0
    private var isRendering = false
    private var lastSearchQuery: String?
    private var searchInProgress = false
    private var linesAboveCursor = 0
    private var lastPasteSummary: String?
    private var pastePlaceholders: [String: String] = [:]
    private var pastePlaceholderCounter = 1

    private var headerLineCount: Int {
        return placeholder != nil ? 3 : 2
    }

    private var visibleLines: [String] {
        return lines + [currentLine] + futureLines
    }

    private var allLines: [String] {
        var result = lines
        if !futureLines.isEmpty || !currentLine.isEmpty {
            result.append(currentLine)
        }
        result.append(contentsOf: futureLines)
        return result
    }

    public init(fileSearcher: FileSearcher? = nil) {
        self.terminal = TerminalController()
        self.fileSearcher = fileSearcher ?? FindFileSearcher()
        self.terminalSize = TerminalSize.current
    }

    /// Run the editor and return the final text
    /// - Parameters:
    ///   - message: Prompt message to display
    ///   - placeholder: Optional placeholder text
    /// - Returns: Multi-line text or empty string if cancelled
    public func edit(message: String, placeholder: String? = nil) -> String {
        // Store message and placeholder for rendering
        self.message = message
        self.placeholder = placeholder

        // Reset state
        lines = []
        futureLines = []
        currentLine = ""
        cursorPosition = 0
        renderedDynamicLineCount = 0
        lastPasteSummary = nil
        pastePlaceholders = [:]
        pastePlaceholderCounter = 1

        // Enable raw mode
        terminal.enableRawMode()
        defer { terminal.disableRawMode() }

        // Initial render
        render()

        // Input loop
        while true {
            guard let char = terminal.readChar() else { continue }

            if handleInput(char) {
                break // Exit requested
            }
        }

        // Clean up - clear our rendered content
        clearRenderedContent(includeHeader: true)

        // Show what was entered
        let finalLines = allLines
        if !finalLines.isEmpty {
            print(message)
            let displayLimit = 5
            let linesToShow = min(finalLines.count, displayLimit)

            for i in 0..<linesToShow {
                let highlighted = highlightFileReferences(finalLines[i])
                print("  \(highlighted)")
            }

            if finalLines.count > displayLimit {
                let remaining = finalLines.count - displayLimit
                print("  \("... +\(remaining) more line\(remaining == 1 ? "" : "s")".dim)")
            }
            print("")
        } else {
            print("")
        }

        // Return result
        let placeholderResolved = finalLines.map { resolvePlaceholders(in: $0) }
        let processedLines = placeholderResolved.map { processFilePath($0) }
        return processedLines.joined(separator: "\n")
    }

    // MARK: - Input Handling

    private func handleInput(_ char: UInt8) -> Bool {
        switch char {
        case 27: // ESC
            return handleEscape()

        case 3: // Ctrl+C
            return handleCtrlC()

        case 4: // Ctrl+D - finish
            return true

        case 9: // Tab - autocomplete
            handleTab()

        case 10, 13: // Enter - autocomplete or new line
            if !suggestions.isEmpty {
                handleTab()
            } else {
                lastPasteSummary = nil
                insertNewLine()
            }

        case 32: // Space - finalize @file reference if present
            if currentLine.hasPrefix("@") && !currentLine.contains(" ") && currentLine.count > 1 {
                insertNewLine()
            } else {
                lastPasteSummary = nil
                insertCharacter(" ")
            }

        case 127: // Backspace
            lastPasteSummary = nil
            handleBackspace()

        default:
            if char >= 32 && char < 127 {
                lastPasteSummary = nil
                insertCharacter(Character(UnicodeScalar(char)))
                cancelPressed = false
            }
        }

        return false
    }

    private func handleEscape() -> Bool {
        // Try to read escape sequence
        if let seq = terminal.readEscapeSequence(), !seq.isEmpty {
            if seq == [91, 50, 48, 48, 126] { // [200~
                handlePaste()
                return false
            }

            if seq[0] == 91 { // [
                switch seq[1] {
                case 65: // Up arrow
                    if !suggestions.isEmpty {
                        selectedSuggestion = selectedSuggestion > 0 ? selectedSuggestion - 1 : suggestions.count - 1
                        render()
                    } else {
                        moveToPreviousLine()
                    }
                    return false

                case 66: // Down arrow
                    if !suggestions.isEmpty {
                        selectedSuggestion = selectedSuggestion < suggestions.count - 1 ? selectedSuggestion + 1 : 0
                        render()
                    } else {
                        moveToNextLine()
                    }
                    return false

                case 67: // Right arrow
                    if cursorPosition < currentLine.count {
                        cursorPosition += 1
                        render()
                    }
                    return false

                case 68: // Left arrow
                    if cursorPosition > 0 {
                        cursorPosition -= 1
                        render()
                    }
                    return false

                default:
                    break
                }
            }
            return false
        }

        // Just ESC pressed - cancel
        return true
    }

    private func handleCtrlC() -> Bool {
        if cancelPressed || (lines.isEmpty && futureLines.isEmpty && currentLine.isEmpty) {
            return true
        }
        cancelPressed = true
        return false
    }

    private func handleTab() {
        if !suggestions.isEmpty {
            if let atIndex = currentLine.lastIndex(of: "@") {
                let beforeAt = String(currentLine[..<atIndex])
                currentLine = beforeAt + "@" + suggestions[selectedSuggestion]
                cursorPosition = currentLine.count
                suggestions = []
                render()
            }
        }
    }

    private func handleBackspace() {
        if cursorPosition > 0 {
            let index = currentLine.index(currentLine.startIndex, offsetBy: cursorPosition - 1)
            currentLine.remove(at: index)
            cursorPosition -= 1
            updateSuggestions()
            render()
        } else if !lines.isEmpty {
            let previousLine = lines.removeLast()
            cursorPosition = previousLine.count
            currentLine = previousLine + currentLine
            updateSuggestions()
            render()
        }
    }

    private func insertNewLine(renderAfter: Bool = true) {
        let splitIndex = currentLine.index(currentLine.startIndex, offsetBy: cursorPosition)
        let before = String(currentLine[..<splitIndex])
        let after = String(currentLine[splitIndex...])

        lines.append(before)
        currentLine = after
        cursorPosition = 0
        suggestions = []
        updateSuggestions()
        if renderAfter {
            render()
        }
    }

    private func insertCharacter(_ char: Character, renderAfter: Bool = true) {
        let index = currentLine.index(currentLine.startIndex, offsetBy: min(cursorPosition, currentLine.count))
        currentLine.insert(char, at: index)
        cursorPosition += 1
        updateSuggestions()
        if renderAfter {
            render()
        }
    }

    private func moveToPreviousLine() {
        guard !lines.isEmpty else { return }
        futureLines.insert(currentLine, at: 0)
        currentLine = lines.removeLast()
        cursorPosition = min(cursorPosition, currentLine.count)
        updateSuggestions()
        render()
    }

    private func moveToNextLine() {
        guard !futureLines.isEmpty else { return }
        lines.append(currentLine)
        currentLine = futureLines.removeFirst()
        cursorPosition = min(cursorPosition, currentLine.count)
        updateSuggestions()
        render()
    }

    private func handlePaste() {
        let pastedText = terminal.readBracketedPaste()
        guard !pastedText.isEmpty else { return }

        let cleaned = normalizePastedText(pastedText)
        cancelPressed = false

        let lineCount = cleaned.split(separator: "\n", omittingEmptySubsequences: false).count
        if lineCount > 1 || cleaned.count > 200 {
            insertPlaceholder(for: cleaned, lineCount: lineCount, charCount: cleaned.count)
        } else {
            insertText(cleaned)
            lastPasteSummary = nil
        }
    }

    private func insertText(_ text: String) {
        guard !text.isEmpty else { return }
        var didInsert = false

        for scalar in text {
            if scalar == "\n" {
                insertNewLine(renderAfter: false)
            } else {
                insertCharacter(scalar, renderAfter: false)
            }
            didInsert = true
        }

        if didInsert {
            render()
        }
    }

    private func insertPlaceholder(for content: String, lineCount: Int, charCount: Int) {
        let id = pastePlaceholderCounter
        pastePlaceholderCounter += 1

        let lineLabel = lineCount == 1 ? "1 line" : "\(lineCount) lines"
        let charLabel = charCount == 1 ? "1 char" : "\(charCount) chars"
        let token = "[text \(lineLabel) · \(charLabel) · chunk #\(id)]"

        pastePlaceholders[token] = content
        insertText(token)
        lastPasteSummary = token
    }

    // MARK: - File Processing

    private func normalizePastedText(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        if normalized.contains("<") {
            normalized = replaceHTMLBreaks(in: normalized)
            normalized = stripHTMLTags(normalized)
            normalized = decodeHTMLEntities(normalized)
        }

        return normalized
    }

    private func replaceHTMLBreaks(in text: String) -> String {
        var result = text
        let replacements: [(pattern: String, replacement: String)] = [
            ("(?i)<br\\s*/?>", "\n"),
            ("(?i)</p>", "\n\n"),
            ("(?i)<p[^>]*>", ""),
            ("(?i)<li[^>]*>", "- "),
            ("(?i)</li>", "\n"),
            ("(?i)<h1[^>]*>", "# "),
            ("(?i)</h1>", "\n\n"),
            ("(?i)<h2[^>]*>", "## "),
            ("(?i)</h2>", "\n\n"),
            ("(?i)<h3[^>]*>", "### "),
            ("(?i)</h3>", "\n\n")
        ]

        for replacement in replacements {
            if let regex = try? NSRegularExpression(pattern: replacement.pattern) {
                let range = NSRange(location: 0, length: (result as NSString).length)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: replacement.replacement)
            }
        }

        return result
    }

    private func stripHTMLTags(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>") else {
            return text
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    private func decodeHTMLEntities(_ text: String) -> String {
        guard let cfString = CFXMLCreateStringByUnescapingEntities(nil, text as CFString, nil) else {
            return text
        }
        return cfString as String
    }

    private func resolvePlaceholders(in text: String) -> String {
        var resolved = text
        for (token, content) in pastePlaceholders {
            if resolved.contains(token) {
                resolved = resolved.replacingOccurrences(of: token, with: content)
            }
        }
        return resolved
    }

    private func updateSuggestions() {
        // Search for files if there's an @ symbol
        if let atIndex = currentLine.lastIndex(of: "@") {
            let afterAt = String(currentLine[currentLine.index(after: atIndex)...])
            if !afterAt.contains(" ") {
                // Skip if search already in progress
                if searchInProgress {
                    return
                }

                // Skip if this is the same query as last time
                if lastSearchQuery == afterAt {
                    return
                }

                // Only search if query is at least 1 character (or empty for initial list)
                // This prevents searching on just "@"
                if afterAt.isEmpty {
                    suggestions = []
                    return
                }

                lastSearchQuery = afterAt
                searchInProgress = true

                // Detect path prefix and extract search query
                let (searchPath, query) = extractPathAndQuery(from: afterAt)

                // Perform search (will be terminated by timeout if too slow)
                suggestions = fileSearcher.search(query: query, searchPath: searchPath)
                selectedSuggestion = 0
                searchInProgress = false
                return
            }
        }
        suggestions = []
        lastSearchQuery = nil
    }

    /// Extract search path and query from user input
    /// - Parameter input: The text after @ symbol
    /// - Returns: Tuple of (searchPath, query) where searchPath is nil for current directory
    private func extractPathAndQuery(from input: String) -> (String?, String) {
        // If no slash, just search in current directory
        guard input.contains("/") else {
            return (nil, input)
        }

        // Use NSString to handle path operations (tilde expansion, standardization)
        let nsInput = input as NSString
        let expandedPath = nsInput.expandingTildeInPath

        // Resolve relative paths (.., ., etc.) against current directory
        let currentDir = FileManager.default.currentDirectoryPath
        let fullPath: String
        if expandedPath.hasPrefix("/") {
            // Already absolute
            fullPath = expandedPath
        } else {
            // Relative path - combine with current directory
            fullPath = (currentDir as NSString).appendingPathComponent(expandedPath)
        }

        // Standardize path (resolves .., ., //)
        let standardized = (fullPath as NSString).standardizingPath

        // Extract directory and filename
        let directory = (standardized as NSString).deletingLastPathComponent
        let filename = (standardized as NSString).lastPathComponent

        // Return directory and filename as query
        return (directory, filename)
    }

    /// Highlight @filepath references with color
    private func highlightFileReferences(_ line: String) -> String {
        let pattern = "@([^\\s]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return line
        }

        let nsString = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsString.length))

        var result = line

        // Process in reverse to maintain string positions
        for match in matches.reversed() {
            let fullMatchRange = match.range
            let fileRef = nsString.substring(with: fullMatchRange)
            let before = nsString.substring(to: fullMatchRange.location)
            let after = nsString.substring(from: fullMatchRange.location + fullMatchRange.length)

            // Highlight with cyan color
            result = before + fileRef.cyan + after
        }

        return result
    }

    /// Convert @filepath to [filename] for display
    private func convertFilePathsToDisplay(_ line: String) -> String {
        let pattern = "@([^\\s]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return line
        }

        let nsString = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsString.length))

        var result = line

        // Process in reverse to maintain string positions
        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let filePathRange = match.range(at: 1)
            let filePath = nsString.substring(with: filePathRange)

            // Check if file exists
            let expandedPath = (filePath as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedPath) {
                let fullMatchRange = match.range
                let before = nsString.substring(to: fullMatchRange.location)
                let after = nsString.substring(from: fullMatchRange.location + fullMatchRange.length)
                let filename = (filePath as NSString).lastPathComponent
                result = before + "[\(filename)]" + after
            }
        }

        return result
    }

    /// Convert @filepath to actual file content for final output
    private func processFilePath(_ line: String) -> String {
        let pattern = "@([^\\s]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return line
        }

        let nsString = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsString.length))

        var result = line

        // Process in reverse to maintain string positions
        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let filePathRange = match.range(at: 1)
            let filePath = nsString.substring(with: filePathRange)

            // Try to read file
            let expandedPath = (filePath as NSString).expandingTildeInPath
            if let content = try? String(contentsOfFile: expandedPath, encoding: .utf8) {
                let fullMatchRange = match.range
                let before = nsString.substring(to: fullMatchRange.location)
                let after = nsString.substring(from: fullMatchRange.location + fullMatchRange.length)
                result = before + content + after
            }
        }

        return result
    }

    // MARK: - Rendering

    private func render() {
        guard !isRendering else { return }
        isRendering = true
        defer { isRendering = false }

        terminal.hideCursor()
        defer { terminal.showCursor() }

        let border = String(repeating: "─", count: terminalSize.columns)

        if isFirstRender {
            isFirstRender = false
            print(message)
            if let placeholder = placeholder {
                print("  \(placeholder.dim)")
            }
            print("")
            printDynamicContent(border: border)
        } else {
            clearRenderedContent()
            printDynamicContent(border: border)
        }
    }

    private func clearRenderedContent(includeHeader: Bool = false) {
        let totalLines = includeHeader ? renderedLineCount : renderedDynamicLineCount
        guard totalLines > 0 else { return }

        let headerLines = headerLineCount
        let linesAbove = includeHeader ? linesAboveCursor : max(0, linesAboveCursor - headerLines)

        terminal.moveCursorToStart()
        if linesAbove > 0 {
            terminal.moveCursorUp(linesAbove)
            terminal.moveCursorToStart()
        }

        for i in 0..<totalLines {
            terminal.clearLine()
            if i < totalLines - 1 {
                terminal.moveCursorDown(1)
                terminal.moveCursorToStart()
            }
        }

        if totalLines > 1 {
            terminal.moveCursorUp(totalLines - 1)
        }
        terminal.moveCursorToStart()
    }

    private func printDynamicContent(border: String) {
        let displayLines = visibleLines
        let currentLineIndex = lines.count
        var savedCursorColumn = 2 + min(cursorPosition, currentLine.count)

        print(border.dim)

        for (index, line) in displayLines.enumerated() {
            let highlighted = highlightFileReferences(line)
            if index == currentLineIndex {
                print(" \(highlighted)", terminator: "")
                terminal.flush()
                savedCursorColumn = 2 + min(cursorPosition, line.count)
                print("")
            } else {
                print(" \(highlighted)")
            }
        }

        print(border.dim)

        if !suggestions.isEmpty {
            for (index, suggestion) in suggestions.enumerated() {
                let isSelected = index == selectedSuggestion
                let marker = isSelected ? "→".cyan : " "
                let text = isSelected ? suggestion.cyan.bold : suggestion.dim
                print("  \(marker) \(text)")
            }
        }

        if let summary = lastPasteSummary {
            print("  \(summary)".dim)
        }

        let shortcuts = "Ctrl+D: finish │ Enter: new line │ ESC: cancel │ @: insert file │ Tab: autocomplete"
        print(shortcuts.dim, terminator: "")
        terminal.flush()

        let headerSize = headerLineCount
        let contentSize = 2 + displayLines.count
        let suggestionSize = suggestions.isEmpty ? 0 : suggestions.count
        let summarySize = lastPasteSummary == nil ? 0 : 1
        let footerSize = 1
        renderedDynamicLineCount = contentSize + suggestionSize + summarySize + footerSize
        renderedLineCount = headerSize + renderedDynamicLineCount

        let inputLineIndex = headerSize + 1 + currentLineIndex
        let totalLines = renderedLineCount - 1
        let linesToMoveUp = totalLines - inputLineIndex
        linesAboveCursor = inputLineIndex

        if linesToMoveUp > 0 {
            terminal.moveCursorUp(linesToMoveUp)
        }
        terminal.moveCursorToColumn(savedCursorColumn)
    }
}
