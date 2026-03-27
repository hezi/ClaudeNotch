import Foundation
import Network
import os

private let logger = Logger(subsystem: "com.claudenotch", category: "HookServer")

/// Represents a pending permission decision — the connection is held open until resolved
struct PendingDecision: Identifiable {
    let id: String  // session_id
    let toolName: String
    let toolInput: JSONValue?
    let toolSummary: String?
    let connection: NWConnection
    let receivedAt: Date

    var age: TimeInterval { Date().timeIntervalSince(receivedAt) }
}

@Observable
@MainActor
final class HookServer {
    private var listener: NWListener?
    private(set) var isRunning = false
    private(set) var port: UInt16

    var onEvent: ((HookPayload) -> Void)?
    /// Called when a permission decision is made (allow/deny/dismiss) with (sessionId, wasAllowed)
    var onDecision: ((String, Bool) -> Void)?

    /// Currently pending permission decisions waiting for user input
    private(set) var pendingDecisions: [String: PendingDecision] = [:]

    init(port: UInt16 = Constants.defaultPort) {
        self.port = port
    }

    func start() {
        stop()

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            logger.error("Failed to create listener: \(error.localizedDescription)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    logger.info("Hook server listening on port \(self?.port ?? 0)")
                    self?.isRunning = true
                case .failed(let error):
                    logger.error("Listener failed: \(error.localizedDescription)")
                    self?.isRunning = false
                case .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        // Release any pending connections
        for (_, pending) in pendingDecisions {
            sendEmptyResponse(pending.connection)
        }
        pendingDecisions.removeAll()

        listener?.cancel()
        listener = nil
        isRunning = false
    }

    func restart(on newPort: UInt16) {
        port = newPort
        start()
    }

    // MARK: - Permission Decision API

    /// Allow a pending permission request
    func allowPermission(sessionId: String) {
        guard let pending = pendingDecisions.removeValue(forKey: sessionId) else { return }

        let decision = """
        {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
        """
        let response = HTTPParser.okResponse(body: decision)
        pending.connection.send(content: response, completion: .contentProcessed { _ in
            pending.connection.cancel()
        })
        logger.info("Allowed permission for session \(sessionId)")
        onDecision?(sessionId, true)
    }

    /// Allow and add a permanent rule so this tool/command is never asked again
    func allowAlwaysPermission(sessionId: String) {
        guard let pending = pendingDecisions.removeValue(forKey: sessionId) else { return }

        // Build the decision using Codable for reliable JSON
        struct Rule: Encodable {
            let toolName: String
            let ruleContent: String?
        }
        struct PermUpdate: Encodable {
            let type = "addRules"
            let rules: [Rule]
            let behavior = "allow"
            let destination = "projectSettings"
        }
        struct Decision: Encodable {
            let behavior = "allow"
            let updatedPermissions: [PermUpdate]
        }
        struct HookOutput: Encodable {
            let hookEventName = "PermissionRequest"
            let decision: Decision
        }
        struct Response: Encodable {
            let hookSpecificOutput: HookOutput
        }

        // Extract rule content from tool_input
        var ruleContent: String?
        if let toolInput = pending.toolInput, case .object(let obj) = toolInput {
            if case .string(let cmd) = obj["command"] {
                ruleContent = cmd
            } else if case .string(let path) = obj["file_path"] {
                ruleContent = path
            }
        }

        let rule = Rule(toolName: pending.toolName, ruleContent: ruleContent)
        let resp = Response(
            hookSpecificOutput: HookOutput(
                decision: Decision(
                    updatedPermissions: [PermUpdate(rules: [rule])]
                )
            )
        )

        let body: String
        if let data = try? JSONEncoder().encode(resp), let json = String(data: data, encoding: .utf8) {
            body = json
        } else {
            // Fallback to simple allow
            body = "{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"allow\"}}}"
        }

        logger.info("Always-allow response: \(body)")

        let response = HTTPParser.okResponse(body: body)
        pending.connection.send(content: response, completion: .contentProcessed { _ in
            pending.connection.cancel()
        })
        logger.info("Always-allowed \(pending.toolName) for session \(sessionId)")
        onDecision?(sessionId, true)
    }

    /// Deny a pending permission request
    func denyPermission(sessionId: String, message: String = "Denied from Claude Notch") {
        guard let pending = pendingDecisions.removeValue(forKey: sessionId) else { return }

        let escapedMessage = message.replacingOccurrences(of: "\"", with: "\\\"")
        let decision = """
        {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"\(escapedMessage)"}}}
        """
        let response = HTTPParser.okResponse(body: decision)
        pending.connection.send(content: response, completion: .contentProcessed { _ in
            pending.connection.cancel()
        })
        logger.info("Denied permission for session \(sessionId)")
        onDecision?(sessionId, false)
    }

    /// Dismiss — let the normal Claude Code permission dialog handle it
    func dismissPermission(sessionId: String) {
        guard let pending = pendingDecisions.removeValue(forKey: sessionId) else { return }
        sendEmptyResponse(pending.connection)
        logger.info("Dismissed permission for session \(sessionId) (falling through to CLI)")
        onDecision?(sessionId, false)
    }

    var hasPendingDecisions: Bool {
        !pendingDecisions.isEmpty
    }

    // MARK: - Connection Handling

    private nonisolated func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))

        var buffer = Data()

        func receiveMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let data {
                    buffer.append(data)
                }

                if let request = HTTPParser.parse(buffer) {
                    self.processRequest(request, connection: connection)
                    return
                }

                if isComplete || error != nil {
                    self.sendEmptyResponse(connection)
                    return
                }

                receiveMore()
            }
        }

        receiveMore()
    }

    private nonisolated func processRequest(_ request: HTTPRequest, connection: NWConnection) {
        guard request.method == "POST",
              request.path.hasPrefix("/hook/"),
              !request.body.isEmpty else {
            sendEmptyResponse(connection)
            return
        }

        let payload: HookPayload
        do {
            payload = try JSONDecoder().decode(HookPayload.self, from: request.body)
        } catch {
            logger.error("Failed to decode hook payload: \(error.localizedDescription)")
            sendEmptyResponse(connection)
            return
        }

        // For PermissionRequest: hold the connection open for user decision
        if request.path == "/hook/PermissionRequest" {
            let summary = SessionManager.extractToolSummary(
                toolName: payload.tool_name,
                toolInput: payload.tool_input
            )

            let pending = PendingDecision(
                id: payload.session_id,
                toolName: payload.tool_name ?? "Unknown",
                toolInput: payload.tool_input,
                toolSummary: summary,
                connection: connection,
                receivedAt: Date()
            )

            Task { @MainActor [weak self] in
                guard let self else { return }
                // Replace any existing pending decision for this session
                if let old = pendingDecisions[payload.session_id] {
                    sendEmptyResponse(old.connection)
                }
                pendingDecisions[payload.session_id] = pending
                onEvent?(payload)
            }
            return
        }

        // For all other events: respond immediately
        sendEmptyResponse(connection)

        Task { @MainActor [weak self] in
            self?.onEvent?(payload)
        }
    }

    private nonisolated func sendEmptyResponse(_ connection: NWConnection) {
        let response = HTTPParser.okResponse()
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
