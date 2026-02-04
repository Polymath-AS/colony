import Foundation
import os

enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct Logger {
    static let shared = Logger()

    private let osLog = OSLog(subsystem: "com.colony.app", category: "Colony")
    private let minLevel: LogLevel

    init() {
        let envLevel = ProcessInfo.processInfo.environment["COLONY_LOG_LEVEL"]?.lowercased()
        switch envLevel {
        case "debug": minLevel = .debug
        case "info": minLevel = .info
        case "warning": minLevel = .warning
        case "error": minLevel = .error
        default: minLevel = .info
        }
    }

    func log(_ level: LogLevel, _ message: String, file: String = #file, line: Int = #line) {
        guard level >= minLevel else { return }

        let fileName = (file as NSString).lastPathComponent
        let prefix: String
        switch level {
        case .debug: prefix = "DEBUG"
        case .info: prefix = "INFO"
        case .warning: prefix = "WARN"
        case .error: prefix = "ERROR"
        }

        let formatted = "[\(prefix)] \(fileName):\(line) \(message)"
        print(formatted)

        let osLogType: OSLogType
        switch level {
        case .debug: osLogType = .debug
        case .info: osLogType = .info
        case .warning: osLogType = .default
        case .error: osLogType = .error
        }
        os_log("%{public}@", log: osLog, type: osLogType, formatted)
    }

    func debug(_ message: String, file: String = #file, line: Int = #line) {
        log(.debug, message, file: file, line: line)
    }

    func info(_ message: String, file: String = #file, line: Int = #line) {
        log(.info, message, file: file, line: line)
    }

    func warning(_ message: String, file: String = #file, line: Int = #line) {
        log(.warning, message, file: file, line: line)
    }

    func error(_ message: String, file: String = #file, line: Int = #line) {
        log(.error, message, file: file, line: line)
    }
}

let log = Logger.shared
