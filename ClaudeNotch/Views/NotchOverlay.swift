import SwiftUI

struct NotchOverlay: View {
    var sessionManager: SessionManager
    var hookServer: HookServer
    var appState: AppState
    @State private var isExpanded = false
    @State private var isAutoExpanded = false // held open by auto-expand, not hover
    @AppStorage(Constants.UserDefaultsKeys.fitNotchToText) private var fitToText = false
    @AppStorage(Constants.UserDefaultsKeys.notchFontScale) private var fontScaleRaw = NotchFontScale.m.rawValue

    private var fontScale: NotchFontScale {
        NotchFontScale(rawValue: fontScaleRaw) ?? .m
    }

    private var sessions: [Session] {
        sessionManager.activeSessions
    }

    private var primarySession: Session? {
        sessions.first
    }

    /// Label for the most urgent attention-needed session when multiple are active
    private var urgentLabel: String? {
        if let s = sessions.first(where: { $0.state == .awaitingApproval }) {
            if s.currentTool == "AskUserQuestion" {
                return "\(s.projectName) has a question"
            }
            if s.currentTool == "ExitPlanMode" {
                return "\(s.projectName): review plan"
            }
            if let tool = s.currentTool {
                return "\(s.projectName): approve \(tool)?"
            }
            return "\(s.projectName) needs approval"
        }
        // Only show "finished" if no session is actively working
        if !sessions.contains(where: { $0.state == .working }),
           let s = sessions.first(where: { $0.state == .ready }) {
            return "\(s.projectName) finished"
        }
        return nil
    }

    private var displayState: SessionState {
        if sessions.contains(where: { $0.state == .awaitingApproval }) { return .awaitingApproval }
        if sessions.contains(where: { $0.state == .working }) { return .working }
        if sessions.contains(where: { $0.state == .ready }) { return .ready }
        if sessions.contains(where: { $0.state == .complete }) { return .complete }
        return .idle
    }

    var body: some View {
        VStack(spacing: 0) {
            notchContent
                .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notchContent: some View {
        VStack(spacing: 0) {
            collapsedBar

            if isExpanded && !sessions.isEmpty {
                expandedDetail
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: isExpanded ? 340 : (fitToText ? nil : notchWidth))
        .fixedSize(horizontal: fitToText && !isExpanded, vertical: false)
        .background(
            RoundedRectangle(cornerRadius: isExpanded ? 20 : 18, style: .continuous)
                .fill(.black)
                .shadow(color: stateGlow.opacity(0.4), radius: isExpanded ? 16 : 8)
        )
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 20 : 18, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering in
            guard !sessions.isEmpty else {
                isExpanded = false
                isAutoExpanded = false
                return
            }
            if hovering {
                isExpanded = true
                isAutoExpanded = false // user took over, no longer auto
            } else if !isAutoExpanded {
                isExpanded = false
            }
        }
        .animation(.smooth(duration: 0.35), value: isExpanded)
        .animation(.smooth(duration: 0.3), value: displayState)
        .animation(.smooth(duration: 0.3), value: sessions.count)
        .onChange(of: appState.shouldAutoExpand) { _, shouldExpand in
            if shouldExpand && !sessions.isEmpty {
                isExpanded = true
                isAutoExpanded = true
                appState.shouldAutoExpand = false
            }
        }
        // Collapse auto-expand when there's no longer an approval pending
        .onChange(of: displayState) { _, newState in
            if isAutoExpanded && newState != .awaitingApproval {
                isAutoExpanded = false
                isExpanded = false
            }
        }
    }

    // MARK: - Collapsed bar

    private var collapsedBar: some View {
        HStack(spacing: 8) {
            if let session = primarySession {
                stateIndicator(for: session.state)
                    .frame(width: 10, height: 10)

                Group {
                    if sessions.count > 1, let urgent = urgentLabel {
                        Text(urgent)
                    } else if sessions.count > 1 {
                        Text("\(session.projectName): \(stateText(for: session).lowercased())")
                    } else {
                        Text(stateText(for: session))
                    }
                }
                .font(scaledFont(size: fontScale.bodySize, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
            } else {
                Image(systemName: "terminal.fill")
                    .font(scaledFont(size: fontScale.detailSize))
                    .foregroundStyle(.white.opacity(0.35))
                Text("Claude Notch")
                    .font(scaledFont(size: fontScale.bodySize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: fontScale.barHeight)
    }

    // MARK: - Expanded detail

    private var expandedDetail: some View {
        VStack(spacing: 4) {
            ForEach(sessions, id: \.id) { session in
                if session.state == .awaitingApproval && session.currentTool == "AskUserQuestion" {
                    questionRow(session)
                } else if session.state == .awaitingApproval && session.currentTool == "ExitPlanMode" {
                    planReviewRow(session)
                } else if session.state == .awaitingApproval {
                    approvalRow(session)
                } else {
                    sessionRow(session)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 10)
    }

    private func sessionRow(_ session: Session) -> some View {
        Button {
            TerminalActivator.activate(session: session)
        } label: {
            HStack(spacing: 8) {
                stateIndicator(for: session.state)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.projectName)
                        .font(scaledFont(size: fontScale.bodySize, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(stateDetail(for: session))
                        .font(scaledFont(size: fontScale.detailSize))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "arrow.up.forward.app")
                    .font(scaledFont(size: fontScale.detailSize))
                    .foregroundStyle(.white.opacity(0.25))

                Text(session.elapsedFormatted)
                    .font(scaledFont(size: fontScale.monoSize, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Approval Row (rich detail)

    private func approvalRow(_ session: Session) -> some View {
        let hasPending = hookServer.pendingDecisions[session.id] != nil
        let pending = hookServer.pendingDecisions[session.id]
        // Use pending's info if available (more accurate), fall back to session
        let toolName = pending?.toolName ?? session.currentTool
        let summary = pending?.toolSummary ?? session.pendingToolSummary

        return VStack(alignment: .leading, spacing: 6) {
            // Header: project + tool (tappable to navigate)
            Button { TerminalActivator.activate(session: session) } label: {
                HStack(spacing: 6) {
                    PulseView(color: .yellow)
                        .frame(width: 8, height: 8)

                    Text(session.projectName)
                        .font(scaledFont(size: fontScale.bodySize, weight: .semibold))
                        .foregroundStyle(.white)

                    Image(systemName: "arrow.up.forward.app")
                        .font(scaledFont(size: fontScale.badgeSize))
                        .foregroundStyle(.white.opacity(0.25))

                    Spacer()

                if let toolName {
                    Text(toolName)
                        .font(scaledFont(size: fontScale.badgeSize, weight: .medium, design: .monospaced))
                        .foregroundStyle(.yellow.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(.yellow.opacity(0.15))
                        )
                }
                }
            }
            .buttonStyle(.plain)

            // Tool summary (command, file path, URL, etc.)
            if let summary {
                toolSummaryView(summary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.white.opacity(0.04))
                    )
            }

            // Decision buttons or fallback hint
            if hasPending {
                HStack(spacing: 6) {
                    Button {
                        hookServer.allowPermission(sessionId: session.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(scaledFont(size: fontScale.badgeSize, weight: .bold))
                            Text("Allow")
                                .font(scaledFont(size: fontScale.monoSize, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(.green.opacity(0.7))
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        hookServer.allowAlwaysPermission(sessionId: session.id)
                    } label: {
                        Text("Always")
                            .font(scaledFont(size: fontScale.monoSize, weight: .medium))
                            .foregroundStyle(.green.opacity(0.8))
                    }
                    .buttonStyle(.plain)

                    Button {
                        hookServer.denyPermission(sessionId: session.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(scaledFont(size: fontScale.badgeSize, weight: .bold))
                            Text("Deny")
                                .font(scaledFont(size: fontScale.monoSize, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(.red.opacity(0.5))
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        hookServer.dismissPermission(sessionId: session.id)
                    } label: {
                        Text("Skip")
                            .font(scaledFont(size: fontScale.badgeSize, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Waiting for approval in terminal")
                    .font(scaledFont(size: fontScale.badgeSize, weight: .medium))
                    .foregroundStyle(.yellow.opacity(0.6))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.yellow.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.yellow.opacity(0.15), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Question Row (AskUserQuestion)

    private func questionRow(_ session: Session) -> some View {
        let pending = hookServer.pendingDecisions[session.id]
        let question = pending?.toolSummary ?? session.pendingToolSummary

        return VStack(alignment: .leading, spacing: 6) {
            // Header
            Button { TerminalActivator.activate(session: session) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.bubble.fill")
                        .font(scaledFont(size: fontScale.monoSize))
                        .foregroundStyle(.blue)

                    Text(session.projectName)
                        .font(scaledFont(size: fontScale.bodySize, weight: .semibold))
                        .foregroundStyle(.white)

                    Image(systemName: "arrow.up.forward.app")
                        .font(scaledFont(size: fontScale.badgeSize))
                        .foregroundStyle(.white.opacity(0.25))

                    Spacer()

                    Text("Question")
                        .font(scaledFont(size: fontScale.badgeSize, weight: .medium, design: .monospaced))
                        .foregroundStyle(.blue.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(.blue.opacity(0.15))
                        )
                }
            }
            .buttonStyle(.plain)

            // Question text
            if let question {
                Text(question)
                    .font(scaledFont(size: fontScale.monoSize))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(4)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.white.opacity(0.04))
                    )
            }

            // Navigate to terminal to answer
            Button {
                TerminalActivator.activate(session: session)
                hookServer.dismissPermission(sessionId: session.id)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(scaledFont(size: fontScale.badgeSize, weight: .bold))
                    Text("Answer in Terminal")
                        .font(scaledFont(size: fontScale.monoSize, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(.blue.opacity(0.7))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.blue.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.blue.opacity(0.15), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Plan Review Row

    private func planReviewRow(_ session: Session) -> some View {
        let hasPending = hookServer.pendingDecisions[session.id] != nil

        return VStack(alignment: .leading, spacing: 6) {
            // Header
            Button { TerminalActivator.activate(session: session) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(scaledFont(size: fontScale.detailSize))
                        .foregroundStyle(.blue)

                    Text(session.projectName)
                        .font(scaledFont(size: fontScale.bodySize, weight: .semibold))
                        .foregroundStyle(.white)

                    Image(systemName: "arrow.up.forward.app")
                        .font(scaledFont(size: fontScale.badgeSize))
                        .foregroundStyle(.white.opacity(0.25))

                    Spacer()

                    Text("Plan Review")
                        .font(scaledFont(size: fontScale.badgeSize, weight: .medium))
                        .foregroundStyle(.blue.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(.blue.opacity(0.15))
                        )
                }
            }
            .buttonStyle(.plain)

            // Plan preview
            if let preview = session.pendingPlanPreview {
                Text(preview)
                    .font(scaledFont(size: fontScale.detailSize))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(5)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(.white.opacity(0.04))
                    )
            }

            // Actions
            if hasPending {
                HStack(spacing: 8) {
                    Button {
                        hookServer.allowPermission(sessionId: session.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(scaledFont(size: fontScale.badgeSize, weight: .bold))
                            Text("Approve")
                                .font(scaledFont(size: fontScale.monoSize, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.green.opacity(0.7)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        hookServer.denyPermission(sessionId: session.id, message: "Plan rejected from Claude Notch")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(scaledFont(size: fontScale.badgeSize, weight: .bold))
                            Text("Reject")
                                .font(scaledFont(size: fontScale.monoSize, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.red.opacity(0.5)))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Open plan file
                    if session.pendingPlanPath != nil {
                        Button {
                            if let path = session.pendingPlanPath {
                                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(scaledFont(size: fontScale.detailSize))
                                Text("Open")
                                    .font(scaledFont(size: fontScale.badgeSize, weight: .medium))
                            }
                            .foregroundStyle(.blue.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.blue.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.blue.opacity(0.15), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Tool Summary (with clickable URLs)

    @ViewBuilder
    private func toolSummaryView(_ summary: String) -> some View {
        if let url = URL(string: summary), url.scheme?.hasPrefix("http") == true {
            Button { NSWorkspace.shared.open(url) } label: {
                HStack(spacing: 4) {
                    Text(summary)
                        .font(scaledFont(size: fontScale.monoSize, design: .monospaced))
                        .foregroundStyle(.blue.opacity(0.9))
                        .lineLimit(2)
                        .underline()
                    Image(systemName: "arrow.up.right")
                        .font(scaledFont(size: fontScale.badgeSize))
                        .foregroundStyle(.blue.opacity(0.6))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.white.opacity(0.04))
                )
            }
            .buttonStyle(.plain)
        } else {
            Text(summary)
                .font(scaledFont(size: fontScale.monoSize, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(3)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.white.opacity(0.04))
                )
        }
    }

    // MARK: - State Visuals

    @ViewBuilder
    private func stateIndicator(for state: SessionState) -> some View {
        switch state {
        case .idle:
            Circle().fill(.gray)
        case .working:
            SpinnerView(color: .green)
        case .awaitingApproval:
            PulseView(color: .yellow)
        case .ready:
            PulseView(color: .red)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .font(scaledFont(size: fontScale.monoSize))
                .foregroundStyle(.green)
        }
    }

    private func stateText(for session: Session) -> String {
        switch session.state {
        case .idle: "Idle"
        case .working:
            if let tool = session.currentTool {
                "Running \(tool)..."
            } else {
                "Working..."
            }
        case .awaitingApproval:
            if let tool = session.currentTool {
                "Approve \(tool)?"
            } else {
                "Needs approval"
            }
        case .ready: "Finished"
        case .complete: "Complete"
        }
    }

    private func stateDetail(for session: Session) -> String {
        switch session.state {
        case .idle: "Waiting"
        case .working:
            if let tool = session.currentTool {
                "\(tool) — \(session.toolCount) tools"
            } else {
                "\(session.toolCount) tool calls"
            }
        case .awaitingApproval:
            session.pendingToolSummary ?? "Waiting for approval"
        case .ready: "Ready for next prompt"
        case .complete: "\(session.toolCount) tool calls completed"
        }
    }

    // MARK: - Layout

    private var notchWidth: CGFloat {
        guard let session = primarySession else { return 160 }
        if session.state == .awaitingApproval { return 220 }
        return 200
    }

    /// Returns a font respecting the user's scale preference.
    /// When scale is `.system`, uses SwiftUI's dynamic body/caption styles.
    private func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        if fontScale == .system {
            // Map to semantic styles based on the size role
            switch weight {
            case .semibold, .bold: return .subheadline.weight(weight)
            case .medium: return .caption.weight(weight)
            default: return .caption2
            }
        }
        return .system(size: size, weight: weight, design: design)
    }

    private var stateGlow: Color {
        switch displayState {
        case .idle: .clear
        case .working: .green
        case .awaitingApproval: .yellow
        case .ready: .red
        case .complete: .green
        }
    }
}

// MARK: - Spinner (orange rotating arc)

struct SpinnerView: View {
    var color: Color = .green
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(color, lineWidth: 1.5)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Pulse (breathing dot)

struct PulseView: View {
    var color: Color = .orange
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(color)
            .overlay(
                Circle()
                    .fill(color.opacity(0.3))
                    .scaleEffect(scale)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    scale = 1.8
                }
            }
    }
}
