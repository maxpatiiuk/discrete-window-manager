//
// Ensures the app is registered to launch at login and records registration status in logs.

import Foundation
import ServiceManagement

final class LoginItemRegistrar {
    func registerIfNeeded() {
        let service = SMAppService.mainApp

        switch service.status {
        case .enabled:
            AppLog.info("Launch at login is already enabled", logger: AppLog.loginItem)

        case .notRegistered, .requiresApproval:
            do {
                try service.register()
                AppLog.info("Registered app to launch at login", logger: AppLog.loginItem)
            } catch {
                AppLog.error(
                    "Failed to register launch at login: \(error.localizedDescription)",
                    logger: AppLog.loginItem
                )
            }

        case .notFound:
            AppLog.error("Launch at login service is unavailable", logger: AppLog.loginItem)

        @unknown default:
            AppLog.error("Launch at login service returned an unknown status", logger: AppLog.loginItem)
        }
    }
}