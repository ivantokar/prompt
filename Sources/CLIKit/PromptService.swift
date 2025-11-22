import Foundation
import Rainbow

// MARK: - Log Level

enum LogLevel: Int, Comparable {
    case quiet = 0
    case normal = 1
    case verbose = 2

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Symbols

struct Symbols {
    static let success = "[✓]"
    static let error = "[✗]"
    static let warning = "[!]"
    static let info = "[i]"
    static let arrow = "→"
    static let bullet = "•"
    // Multi-select uses different style to avoid confusion with status
    static let checked = "◉"
    static let unchecked = "○"
}

// MARK: - Spinner

class Spinner {
    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private var frameIndex = 0
    private var isRunning = false
    private var message: String
    private var timer: DispatchSourceTimer?

    init(message: String) {
        self.message = message
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        frameIndex = 0

        // Hide cursor
        print("\u{001B}[?25l", terminator: "")

        timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        timer?.schedule(deadline: .now(), repeating: .milliseconds(80))
        timer?.setEventHandler { [weak self] in
            self?.render()
        }
        timer?.resume()
    }

    func stop(success: Bool = true, message: String? = nil) {
        guard isRunning else { return }
        isRunning = false
        timer?.cancel()
        timer = nil

        // Clear line and show result
        print("\r\u{001B}[K", terminator: "")
        let finalMessage = message ?? self.message
        if success {
            print("\(Symbols.success.green) \(finalMessage)")
        } else {
            print("\(Symbols.error.red) \(finalMessage)")
        }

        // Show cursor
        print("\u{001B}[?25h", terminator: "")
        fflush(stdout)
    }

    private func render() {
        let frame = frames[frameIndex % frames.count].cyan
        print("\r\u{001B}[K\(frame) \(message)", terminator: "")
        fflush(stdout)
        frameIndex += 1
    }

    func update(_ newMessage: String) {
        self.message = newMessage
    }
}

// MARK: - Box Style

enum BoxStyle {
    case single
    case double
    case rounded

    var chars: (tl: String, tr: String, bl: String, br: String, h: String, v: String) {
        switch self {
        case .single:
            return ("┌", "┐", "└", "┘", "─", "│")
        case .double:
            return ("╔", "╗", "╚", "╝", "═", "║")
        case .rounded:
            return ("╭", "╮", "╰", "╯", "─", "│")
        }
    }
}

// MARK: - Table

struct Table {
    var headers: [String]
    var rows: [[String]]
    var style: BoxStyle

    init(headers: [String] = [], rows: [[String]] = [], style: BoxStyle = .single) {
        self.headers = headers
        self.rows = rows
        self.style = style
    }

    func render() -> String {
        let c = style.chars
        var allRows = rows
        if !headers.isEmpty {
            allRows.insert(headers, at: 0)
        }

        guard !allRows.isEmpty else { return "" }

        // Calculate column widths
        let colCount = allRows.map { $0.count }.max() ?? 0
        var widths = [Int](repeating: 0, count: colCount)

        for row in allRows {
            for (i, cell) in row.enumerated() {
                widths[i] = max(widths[i], stripANSI(cell).count)
            }
        }

        var result = ""

        // Top border
        let topBorder = c.tl + widths.map { String(repeating: c.h, count: $0 + 2) }.joined(separator: c.h) + c.tr
        result += topBorder + "\n"

        // Rows
        for (rowIndex, row) in allRows.enumerated() {
            var line = c.v
            for (i, width) in widths.enumerated() {
                let cell = i < row.count ? row[i] : ""
                let padding = width - stripANSI(cell).count
                line += " \(cell)\(String(repeating: " ", count: padding)) " + c.v
            }
            result += line + "\n"

            // Header separator
            if rowIndex == 0 && !headers.isEmpty {
                let sep = c.v + widths.map { String(repeating: c.h, count: $0 + 2) }.joined(separator: c.h) + c.v
                result += sep + "\n"
            }
        }

        // Bottom border
        let bottomBorder = c.bl + widths.map { String(repeating: c.h, count: $0 + 2) }.joined(separator: c.h) + c.br
        result += bottomBorder

        return result
    }

    private func stripANSI(_ str: String) -> String {
        str.replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression)
    }
}

// MARK: - Error Formatter

struct ErrorFormatter {
    static let suggestions: [String: String] = [
        "permission denied": "Try running with sudo or check file permissions",
        "no such file": "Verify the path exists and is spelled correctly",
        "already exists": "Use --force to overwrite or choose a different name",
        "connection refused": "Check if the service is running",
        "timeout": "Check your network connection"
    ]

    static func format(_ error: Error, context: String? = nil) -> String {
        var result = "\(Symbols.error.red) \(error.localizedDescription)"

        if let context = context {
            result += "\n  Context: \(context.dim)"
        }

        // Find matching suggestion
        let lowercased = error.localizedDescription.lowercased()
        for (pattern, suggestion) in suggestions {
            if lowercased.contains(pattern) {
                result += "\n  \(Symbols.info.blue) \(suggestion)"
                break
            }
        }

        return result
    }
}

// MARK: - Path Formatter

struct PathFormatter {
    static func format(_ path: String) -> String {
        let components = path.split(separator: "/")
        guard !components.isEmpty else { return path }

        let last = String(components.last!)

        if components.count == 1 {
            return formatName(last)
        }

        let dir = components.dropLast().joined(separator: "/")
        return "\(dir.dim)/\(formatName(last))"
    }

    private static func formatName(_ name: String) -> String {
        // Check if directory (no extension or known dir names)
        let dirPatterns = ["src", "lib", "test", "docs", "config", "templates", "commands", "services", "models"]
        if !name.contains(".") || dirPatterns.contains(name.lowercased()) {
            return name.blue.bold
        }
        return name.cyan
    }

    static func directory(_ path: String) -> String {
        path.blue
    }

    static func file(_ path: String) -> String {
        path.cyan
    }
}

// MARK: - Prompt Service

struct PromptService {
    private let useColors: Bool
    var logLevel: LogLevel

    init(useColors: Bool = isatty(fileno(stdout)) != 0, logLevel: LogLevel = .normal) {
        self.useColors = useColors
        self.logLevel = logLevel
        Rainbow.enabled = useColors
    }

    // MARK: - Banner

    func banner() {
        guard logLevel >= .normal else { return }
        let o = "#E07850"  // Orange
        print("""

        \(" _|_  ".white)\("_  _  ".hex(o))\("_".white)
        \("  |_ ".white)\("(_ (_ ".hex(o))\("(_".white)   \("v2.2.0".dim)

        """)
    }

    // MARK: - Spinner

    func spinner(_ message: String) -> Spinner {
        Spinner(message: message)
    }

    func withSpinner<T>(_ message: String, task: () throws -> T) rethrows -> T {
        let s = Spinner(message: message)
        s.start()
        do {
            let result = try task()
            s.stop(success: true)
            return result
        } catch {
            s.stop(success: false, message: "\(message) failed")
            throw error
        }
    }

    // MARK: - Input Prompts

    func prompt(_ message: String, default defaultValue: String? = nil) -> String {
        if let defaultValue = defaultValue {
            print("\(message) [\(defaultValue.dim)]: ", terminator: "")
        } else {
            print("\(message): ", terminator: "")
        }

        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !input.isEmpty else {
            return defaultValue ?? ""
        }
        return input
    }

    func confirm(_ message: String, default defaultValue: Bool = true) -> Bool {
        let hint = defaultValue ? "Y/n" : "y/N"
        print("\(message) [\(hint.dim)]: ", terminator: "")

        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !input.isEmpty else {
            return defaultValue
        }
        return input == "y" || input == "yes"
    }

    func select(_ message: String, options: [String], default defaultIndex: Int = 0) -> Int {
        print(message)
        for (index, option) in options.enumerated() {
            let marker = index == defaultIndex ? Symbols.arrow : " "
            print("  \(marker) \(String(index + 1).bold). \(option)")
        }

        print("Enter number [\(defaultIndex + 1)]: ", terminator: "")

        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !input.isEmpty,
              let selected = Int(input),
              selected > 0 && selected <= options.count else {
            return defaultIndex
        }
        return selected - 1
    }

    /// Interactive multi-select with arrow keys
    func multiSelect(_ message: String, options: [String], defaults: [Bool]? = nil) -> [Int] {
        var selected = defaults ?? [Bool](repeating: false, count: options.count)
        if selected.count < options.count {
            selected += [Bool](repeating: false, count: options.count - selected.count)
        }
        var cursor = 0
        var firstRender = true

        // Enable raw mode for arrow key input
        var originalTermios = termios()
        tcgetattr(STDIN_FILENO, &originalTermios)
        var raw = originalTermios
        raw.c_lflag &= ~UInt(ICANON | ECHO)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)

        // Hide cursor
        print("\u{001B}[?25l", terminator: "")
        fflush(stdout)

        func render() {
            // On first render, just print. On subsequent renders, move up first.
            if !firstRender {
                // Move cursor up to overwrite previous output
                let linesToMove = options.count + 2
                print("\u{001B}[\(linesToMove)A\r", terminator: "")
            }
            firstRender = false

            print("\u{001B}[K\(message)")
            print("\u{001B}[K  \("(↑/↓ navigate, space toggle, enter confirm)".dim)")

            for (index, option) in options.enumerated() {
                let checkbox = selected[index] ? Symbols.checked.green : Symbols.unchecked
                let pointer = index == cursor ? Symbols.arrow.cyan : " "
                let text = index == cursor ? option.bold : option
                print("\u{001B}[K  \(pointer) \(checkbox) \(text)")
            }
            fflush(stdout)
        }

        render()

        while true {
            var c: UInt8 = 0
            read(STDIN_FILENO, &c, 1)

            if c == 27 { // Escape sequence
                var seq: [UInt8] = [0, 0]
                read(STDIN_FILENO, &seq[0], 1)
                read(STDIN_FILENO, &seq[1], 1)

                if seq[0] == 91 { // [
                    switch seq[1] {
                    case 65: // Up
                        cursor = cursor > 0 ? cursor - 1 : options.count - 1
                    case 66: // Down
                        cursor = cursor < options.count - 1 ? cursor + 1 : 0
                    default: break
                    }
                }
            } else if c == 32 { // Space
                selected[cursor].toggle()
            } else if c == 10 || c == 13 { // Enter
                break
            } else if c == 113 { // q
                break
            }

            render()
        }

        // Restore terminal
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalTermios)
        print("\u{001B}[?25h", terminator: "") // Show cursor
        print("") // New line

        return selected.enumerated().compactMap { $0.element ? $0.offset : nil }
    }

    // MARK: - Status Messages

    func info(_ message: String) {
        guard logLevel >= .normal else { return }
        print("\(Symbols.info.blue) \(message)")
    }

    func success(_ message: String) {
        guard logLevel >= .normal else { return }
        print("\(Symbols.success.green) \(message)")
    }

    func warning(_ message: String) {
        guard logLevel >= .normal else { return }
        print("\(Symbols.warning.yellow) \(message)")
    }

    func error(_ message: String) {
        // Errors always show
        print("\(Symbols.error.red) \(message)")
    }

    func verbose(_ message: String) {
        guard logLevel >= .verbose else { return }
        print("  \(message.dim)")
    }

    // MARK: - Hierarchical Output

    func item(_ message: String, indent: Int = 0) {
        guard logLevel >= .normal else { return }
        let padding = String(repeating: "  ", count: indent)
        print("\(padding)\(Symbols.bullet) \(message)")
    }

    func itemSuccess(_ message: String, indent: Int = 1) {
        guard logLevel >= .normal else { return }
        let padding = String(repeating: "  ", count: indent)
        print("\(padding)\(Symbols.success.green) \(message)")
    }

    func itemError(_ message: String, indent: Int = 1) {
        let padding = String(repeating: "  ", count: indent)
        print("\(padding)\(Symbols.error.red) \(message)")
    }

    func itemWarning(_ message: String, indent: Int = 1) {
        guard logLevel >= .normal else { return }
        let padding = String(repeating: "  ", count: indent)
        print("\(padding)\(Symbols.warning.yellow) \(message)")
    }

    func itemSkipped(_ message: String, reason: String? = nil, indent: Int = 1) {
        guard logLevel >= .normal else { return }
        let padding = String(repeating: "  ", count: indent)
        if let reason = reason {
            print("\(padding)\(Symbols.warning.yellow) Skipped \(message) (\(reason.dim))")
        } else {
            print("\(padding)\(Symbols.warning.yellow) Skipped \(message)")
        }
    }

    // MARK: - Sections & Headers

    func step(_ number: Int, _ message: String) {
        guard logLevel >= .normal else { return }
        print("")
        print("[\(number)] ".cyan.bold + message)
    }

    func header(_ title: String) {
        guard logLevel >= .normal else { return }
        print("")
        print("  \(title.bold)")
        print("")
    }

    func section(_ title: String) {
        guard logLevel >= .normal else { return }
        print("")
        print("  \(title)")
    }

    // MARK: - Box & Panel

    func box(_ content: String, style: BoxStyle = .rounded, title: String? = nil) {
        guard logLevel >= .normal else { return }
        let c = style.chars
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let maxWidth = lines.map { stripANSI($0).count }.max() ?? 0

        // Top border
        var top = c.tl + String(repeating: c.h, count: maxWidth + 2) + c.tr
        if let title = title {
            let titleStr = " \(title) "
            let insertPos = 2
            let index = top.index(top.startIndex, offsetBy: insertPos)
            let endIndex = top.index(index, offsetBy: min(titleStr.count, maxWidth))
            top = String(top[..<index]) + titleStr.bold + String(top[endIndex...])
        }
        print(top)

        // Content
        for line in lines {
            let padding = maxWidth - stripANSI(line).count
            print("\(c.v) \(line)\(String(repeating: " ", count: padding)) \(c.v)")
        }

        // Bottom border
        print(c.bl + String(repeating: c.h, count: maxWidth + 2) + c.br)
    }

    func panel(_ title: String, items: [(String, String)]) {
        guard logLevel >= .normal else { return }
        var table = Table(style: .rounded)
        table.rows = items.map { [$0.0.bold, $0.1] }
        print("")
        if !title.isEmpty {
            print("  \(title.bold)")
        }
        print(table.render())
    }

    func divider(_ char: String = "─", length: Int = 40) {
        guard logLevel >= .normal else { return }
        print(String(repeating: char, count: length).dim)
    }

    // MARK: - Table

    func table(headers: [String], rows: [[String]], style: BoxStyle = .single) {
        guard logLevel >= .normal else { return }
        let t = Table(headers: headers, rows: rows, style: style)
        print(t.render())
    }

    // MARK: - Summary & Next Steps

    func summary(_ message: String) {
        print("")
        print("\(Symbols.success.green) \(message)")
    }

    func nextSteps(_ steps: [String]) {
        guard logLevel >= .normal else { return }
        print("")
        print("Next steps:".bold)
        for step in steps {
            print("  \(Symbols.arrow) \(step)")
        }
    }

    // MARK: - Progress

    func startOperation(_ message: String) {
        guard logLevel >= .normal else { return }
        print("\(message)...")
    }

    func completeOperation(_ message: String, duration: TimeInterval? = nil) {
        guard logLevel >= .normal else { return }
        print("")
        if let duration = duration {
            print("\(Symbols.success.green) \(message) in \(String(format: "%.1fs", duration))")
        } else {
            print("\(Symbols.success.green) \(message)")
        }
    }

    // MARK: - Paths

    func path(_ path: String) -> String {
        PathFormatter.format(path)
    }

    // MARK: - Errors

    func formatError(_ error: Error, context: String? = nil) -> String {
        ErrorFormatter.format(error, context: context)
    }

    // MARK: - Blank Lines

    func newline() {
        guard logLevel >= .normal else { return }
        print("")
    }

    // MARK: - Raw Output

    func output(_ text: String) {
        print(text)
    }

    // MARK: - Helpers

    private func stripANSI(_ str: String) -> String {
        str.replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression)
    }
}
