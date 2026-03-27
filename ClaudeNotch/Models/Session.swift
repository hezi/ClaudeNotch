import Foundation

enum SessionState: String, CaseIterable {
    case idle
    case working
    case awaitingApproval
    case ready       // Claude finished responding, waiting for next prompt
    case complete
}

@Observable
final class Session: Identifiable {
    let id: String
    var cwd: String
    var state: SessionState
    var lastActivity: Date
    var currentTool: String?
    var toolCount: Int = 0
    var startTime: Date

    /// Human-readable description of what the pending tool wants to do
    var pendingToolSummary: String?

    /// For ExitPlanMode: preview of the plan content and path to the file
    var pendingPlanPreview: String?
    var pendingPlanPath: String?

    /// Optional display name from --resume flag
    var name: String?

    /// Terminal info for navigation
    var tty: String?
    var terminalBundleId: String?
    var processPID: Int?

    /// Throttle enrichment retries
    var lastEnrichmentAttempt: Date?

    var projectName: String {
        var path = cwd
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            path = "~" + path.dropFirst(home.count)
        }
        let maxLength = 30
        if path.count > maxLength {
            path = "…" + path.suffix(maxLength - 1)
        }
        if let name {
            return "\(path) (\(name))"
        }
        return path
    }

    var elapsed: TimeInterval {
        Date().timeIntervalSince(startTime)
    }

    var elapsedFormatted: String {
        let total = Int(elapsed)
        let minutes = total / 60
        let seconds = total % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    init(id: String, cwd: String) {
        self.id = id
        self.cwd = cwd
        self.state = .idle
        self.lastActivity = Date()
        self.startTime = Date()
    }
}
