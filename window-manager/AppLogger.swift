//
//  AppLogger.swift
//  window-manager
//
//  Created by GitHub Copilot on 2026-04-14.
//

import Foundation
import OSLog

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "window-manager"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let accessibility = Logger(subsystem: subsystem, category: "accessibility")
    static let indicator = Logger(subsystem: subsystem, category: "indicator")

    static func debug(_ message: String, logger: Logger = app) {
#if DEBUG
        logger.debug("\(message, privacy: .public)")
#endif
    }

    static func info(_ message: String, logger: Logger = app) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String, logger: Logger = app) {
        logger.error("\(message, privacy: .public)")
    }
}