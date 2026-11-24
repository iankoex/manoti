//
//  Loggable.swift
//  AppPackageExtensions
//

import Foundation
import OSLog

public enum LogLevel: String, Sendable {
    case debug
    case info
    case warning
    case error
}

nonisolated public protocol Loggable {
    var logCategory: String { get }
    func log(_ message: String, level: LogLevel)
}

nonisolated extension Loggable {
    public var logCategory: String {
        String(describing: Self.self)
    }

    public func log(_ message: String, level: LogLevel) {
        let logger = Logger(subsystem: "com.iankoex.manoti", category: logCategory)

        switch level {
            case .debug:
                logger.debug("\(message, privacy: .private)")
            case .info:
                logger.info("\(message, privacy: .private)")
            case .warning:
                logger.warning("\(message, privacy: .private)")
            case .error:
                logger.error("\(message, privacy: .private)")
        }
    }
}
