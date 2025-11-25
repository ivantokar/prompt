import Foundation

public enum LogLevel: Int, Comparable {
    case quiet = 0
    case normal = 1
    case verbose = 2

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
