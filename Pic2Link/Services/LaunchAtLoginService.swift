import Foundation
import ServiceManagement

enum LaunchAtLoginError: LocalizedError {
    case unsupportedStatus(SMAppService.Status)
    case missingBundleIdentifier
    case missingBundlePath

    var errorDescription: String? {
        switch self {
        case .unsupportedStatus(.requiresApproval):
            return L10n.tr("launchAtLogin.requiresApproval")
        case .unsupportedStatus(.notFound):
            return L10n.tr("launchAtLogin.notFound")
        case .unsupportedStatus:
            return L10n.tr("launchAtLogin.updateFailed")
        case .missingBundleIdentifier:
            return L10n.tr("launchAtLogin.missingIdentifier")
        case .missingBundlePath:
            return L10n.tr("launchAtLogin.missingPath")
        }
    }
}

final class LaunchAtLoginService {
    static let shared = LaunchAtLoginService()

    private init() {}

    func sync(isEnabled: Bool) throws {
        if isEnabled {
            if try syncWithSMAppService(isEnabled: true) {
                try removeLegacyLaunchAgentIfNeeded()
                return
            }
            try installLaunchAgent()
        } else {
            _ = try? syncWithSMAppService(isEnabled: false)
            try removeLegacyLaunchAgentIfNeeded()
        }
    }

    private func syncWithSMAppService(isEnabled: Bool) throws -> Bool {
        let service = SMAppService.mainApp

        switch (isEnabled, service.status) {
        case (true, .enabled):
            return true
        case (false, .notRegistered), (false, .notFound):
            return false
        case (true, .notFound), (true, .requiresApproval):
            return false
        case (false, .requiresApproval):
            return false
        case (true, _):
            try service.register()
            return true
        case (false, _):
            try service.unregister()
            return true
        }
    }

    private func installLaunchAgent() throws {
        let plistURL = try launchAgentPlistURL()
        let plist = try launchAgentPlist()
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)

        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: plistURL, options: .atomic)
        try loadLaunchAgent(at: plistURL)
    }

    private func removeLegacyLaunchAgentIfNeeded() throws {
        let plistURL = try launchAgentPlistURL()
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return }
        try unloadLaunchAgent(at: plistURL)
        try? FileManager.default.removeItem(at: plistURL)
    }

    private func launchAgentPlist() throws -> [String: Any] {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            throw LaunchAtLoginError.missingBundleIdentifier
        }
        let bundlePath = Bundle.main.bundleURL.path
        guard !bundlePath.isEmpty else {
            throw LaunchAtLoginError.missingBundlePath
        }

        return [
            "Label": launchAgentLabel(bundleIdentifier: bundleIdentifier),
            "ProgramArguments": ["/usr/bin/open", bundlePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive"
        ]
    }

    private func launchAgentPlistURL() throws -> URL {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            throw LaunchAtLoginError.missingBundleIdentifier
        }
        let libraryDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)

        return libraryDirectory.appendingPathComponent("\(launchAgentLabel(bundleIdentifier: bundleIdentifier)).plist")
    }

    private func launchAgentLabel(bundleIdentifier: String) -> String {
        "\(bundleIdentifier).launch-at-login"
    }

    private func loadLaunchAgent(at plistURL: URL) throws {
        try runLaunchctl(arguments: ["bootstrap", "gui/\(uid())", plistURL.path], ignoreExitCodes: [0, 5])
        try runLaunchctl(arguments: ["enable", "gui/\(uid())/\(try launchAgentLabel())"], ignoreExitCodes: [0])
        try runLaunchctl(arguments: ["kickstart", "-k", "gui/\(uid())/\(try launchAgentLabel())"], ignoreExitCodes: [0])
    }

    private func unloadLaunchAgent(at plistURL: URL) throws {
        try runLaunchctl(arguments: ["bootout", "gui/\(uid())", plistURL.path], ignoreExitCodes: [0, 3, 5])
        try runLaunchctl(arguments: ["disable", "gui/\(uid())/\(try launchAgentLabel())"], ignoreExitCodes: [0, 113])
    }

    private func launchAgentLabel() throws -> String {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            throw LaunchAtLoginError.missingBundleIdentifier
        }
        return launchAgentLabel(bundleIdentifier: bundleIdentifier)
    }

    private func runLaunchctl(arguments: [String], ignoreExitCodes: Set<Int32>) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw error
        }

        guard ignoreExitCodes.contains(process.terminationStatus) else {
            throw NSError(
                domain: "LaunchAtLoginService",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: L10n.tr("launchAtLogin.launchctlFailed", process.terminationStatus)]
            )
        }
    }

    private func uid() -> String {
        String(getuid())
    }
}
