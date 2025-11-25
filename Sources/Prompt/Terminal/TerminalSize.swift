import Foundation

/// Terminal dimensions
public struct TerminalSize {
    public let rows: Int
    public let columns: Int

    public static var current: TerminalSize {
        var ws = winsize()
        _ = ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws)
        return TerminalSize(
            rows: Int(ws.ws_row),
            columns: Int(ws.ws_col)
        )
    }
}
