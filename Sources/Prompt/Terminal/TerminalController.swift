import Foundation
import Darwin

/// Controls terminal state and ANSI escape sequences
public final class TerminalController {
    private var originalTermios: termios?
    private var isRawMode = false
    private var isBracketedPasteEnabled = false

    // MARK: - Terminal Mode

    /// Enable raw mode for character-by-character input
    public func enableRawMode() {
        guard !isRawMode else { return }

        var raw = termios()
        tcgetattr(STDIN_FILENO, &raw)
        originalTermios = raw

        raw.c_lflag &= ~UInt(ICANON | ECHO)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        enableBracketedPasteMode()
        isRawMode = true
    }

    /// Restore original terminal mode
    public func disableRawMode() {
        guard isRawMode, var original = originalTermios else { return }
        disableBracketedPasteMode()
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        isRawMode = false
    }

    deinit {
        disableRawMode()
    }

    // MARK: - Cursor Control

    /// Hide the cursor
    public func hideCursor() {
        print("\u{001B}[?25l", terminator: "")
        flush()
    }

    /// Show the cursor
    public func showCursor() {
        print("\u{001B}[?25h", terminator: "")
        flush()
    }

    /// Move cursor up by n lines
    public func moveCursorUp(_ lines: Int) {
        guard lines > 0 else { return }
        print("\u{001B}[\(lines)A", terminator: "")
        flush()
    }

    /// Move cursor down by n lines
    public func moveCursorDown(_ lines: Int) {
        guard lines > 0 else { return }
        print("\u{001B}[\(lines)B", terminator: "")
        flush()
    }

    /// Move cursor to column (1-indexed)
    public func moveCursorToColumn(_ column: Int) {
        // Use absolute horizontal positioning (1-indexed)
        print("\u{001B}[\(column)G", terminator: "")
        flush()
    }

    /// Move cursor to start of line
    public func moveCursorToStart() {
        print("\r", terminator: "")
        flush()
    }

    // MARK: - Clear Operations

    /// Clear from cursor to end of screen
    public func clearToEnd() {
        print("\u{001B}[J", terminator: "")
        flush()
    }

    /// Clear current line from cursor to end
    public func clearLineToEnd() {
        print("\u{001B}[K", terminator: "")
        flush()
    }

    /// Clear entire current line
    public func clearLine() {
        print("\u{001B}[2K", terminator: "")
        flush()
    }

    // MARK: - Input

    /// Read a single character (requires raw mode)
    public func readChar() -> UInt8? {
        var c: UInt8 = 0
        guard read(STDIN_FILENO, &c, 1) == 1 else { return nil }
        return c
    }

    /// Read an escape sequence (for arrow keys, etc.)
    public func readEscapeSequence() -> [UInt8]? {
        var seq: [UInt8] = []

        while true {
            var byte: UInt8 = 0
            guard read(STDIN_FILENO, &byte, 1) == 1 else { break }
            seq.append(byte)

            // If the sequence does not start with '[' we can stop
            if seq.count == 1 && seq[0] != 91 { // 91 == '['
                break
            }

            // Arrow keys send ESC [ A/B/C/D with no trailing '~'
            if seq.count == 2, let second = seq.last, (65...68).contains(Int(second)) {
                break
            }

            // Other sequences (like bracketed paste) end with '~'
            if byte == 126 { // '~'
                break
            }

            if !hasPendingInput() {
                break
            }
        }

        return seq.isEmpty ? nil : seq
    }

    /// Read text until the bracketed paste closing sequence (ESC [ 201 ~)
    public func readBracketedPaste() -> String {
        var data = Data()

        while true {
            var byte: UInt8 = 0
            guard read(STDIN_FILENO, &byte, 1) == 1 else { break }

            if byte == 27 { // ESC
                if let seq = readEscapeSequence() {
                    if seq == [91, 50, 48, 49, 126] { // [201~
                        break
                    }
                    data.append(27)
                    data.append(contentsOf: seq)
                }
            } else {
                data.append(byte)
            }
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Non-blocking check for pending stdin input
    public func hasPendingInput(timeoutMilliseconds: Int32 = 0) -> Bool {
        var fds = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let result = poll(&fds, 1, timeoutMilliseconds)
        return result > 0 && (fds.revents & Int16(POLLIN)) != 0
    }

    // MARK: - Output

    /// Flush stdout
    public func flush() {
        fflush(stdout)
    }

    /// Print without newline and flush
    public func write(_ text: String) {
        print(text, terminator: "")
        flush()
    }

    /// Print with newline
    public func writeLine(_ text: String) {
        print(text)
        flush()
    }
}

// MARK: - Bracketed Paste

private extension TerminalController {
    func enableBracketedPasteMode() {
        guard !isBracketedPasteEnabled else { return }
        print("\u{001B}[?2004h", terminator: "")
        flush()
        isBracketedPasteEnabled = true
    }

    func disableBracketedPasteMode() {
        guard isBracketedPasteEnabled else { return }
        print("\u{001B}[?2004l", terminator: "")
        flush()
        isBracketedPasteEnabled = false
    }
}
