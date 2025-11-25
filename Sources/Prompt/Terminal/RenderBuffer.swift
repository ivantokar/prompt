import Foundation

/// Manages terminal rendering to prevent flicker
public final class RenderBuffer {
    private let terminal: TerminalController
    private var previousLines: [String] = []
    private var totalPreviousLines = 0

    public init(terminal: TerminalController) {
        self.terminal = terminal
    }

    /// Render new content, clearing previous render
    public func render(lines: [String]) {
        // If we have previous content, move cursor back to start and clear
        if totalPreviousLines > 0 {
            terminal.moveCursorUp(totalPreviousLines)
            terminal.moveCursorToStart()
            terminal.clearToEnd()
        }

        // Render new content
        for (index, line) in lines.enumerated() {
            if index > 0 {
                print("") // Newline for next line
            }
            print(line, terminator: "")
        }

        // Save state for next render
        previousLines = lines
        totalPreviousLines = lines.count

        terminal.flush()
    }

    /// Clear the buffer and screen
    public func clear() {
        if totalPreviousLines > 0 {
            terminal.moveCursorUp(totalPreviousLines)
            terminal.moveCursorToStart()
            terminal.clearToEnd()
        }
        previousLines = []
        totalPreviousLines = 0
    }
}
