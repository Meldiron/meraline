import Foundation

/// Something an agent stopped to ask before going on: leave to use a tool, or a question of its own.
/// Claude Code asks over stdin and stdout in print mode; OpenCode's run mode turns its own asks down and
/// says so, which shows up here already settled.
nonisolated struct AgentPrompt: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Leave to use a tool, with what it would be used on: a file name, a command, a URL.
        case permission(Activity, detail: String?)
        /// A question with choices. Several questions can come at once.
        case question([Question])
    }

    /// How the prompt was settled, once it was.
    enum Resolution: Equatable, Sendable {
        case allowed
        case denied
        case answered([String: String])
        /// The agent's non-interactive mode turned it down before Meraline could ask.
        case declinedByAgent
    }

    struct Question: Identifiable, Equatable, Sendable {
        var header = ""
        var text: String
        var options: [Option] = []
        var multiSelect = false

        var id: String { text }

        struct Option: Identifiable, Equatable, Sendable {
            var label: String
            var detail: String?

            var id: String { label }
        }
    }

    let id: String
    let kind: Kind
    /// The tool's input as the agent sent it, echoed back when the prompt is allowed.
    var input = Data()
    var resolution: Resolution?

    var isPending: Bool { resolution == nil }

    /// The line Claude Code reads on stdin to learn how the prompt was settled.
    func claudeCodeResponse(_ answer: AgentAnswer) throws -> Data {
        var input = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] ?? [:]
        let response: [String: Any]
        switch answer {
        case .allow:
            response = ["behavior": "allow", "updatedInput": input]
        case .answers(let answers):
            input["answers"] = answers
            response = ["behavior": "allow", "updatedInput": input]
        case .deny:
            response = ["behavior": "deny", "message": "The person asking declined."]
        }
        let line: [String: Any] = [
            "type": "control_response",
            "response": ["subtype": "success", "request_id": id, "response": response]
        ]
        var data = try JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])
        data.append(0x0A)
        return data
    }
}

nonisolated enum AgentAnswer: Equatable, Sendable {
    case allow
    case deny
    /// Each question's answer by the question's text; several picks are joined with commas.
    case answers([String: String])

    var resolution: AgentPrompt.Resolution {
        switch self {
        case .allow: .allowed
        case .deny: .denied
        case .answers(let answers): .answered(answers)
        }
    }
}

/// Carries an answer back to the agent that asked. Two responders are equal only when they are one.
nonisolated final class AgentPromptResponder: Sendable, Equatable {
    private let respond: @Sendable (AgentAnswer) -> Void

    init(_ respond: @escaping @Sendable (AgentAnswer) -> Void) {
        self.respond = respond
    }

    func callAsFunction(_ answer: AgentAnswer) {
        respond(answer)
    }

    static func == (lhs: AgentPromptResponder, rhs: AgentPromptResponder) -> Bool { lhs === rhs }
}

nonisolated extension AgentPrompt.Kind {
    /// For the log: the tool by name, never what it would be used on.
    var logDescription: String {
        switch self {
        case .permission(let activity, _): "for leave to \(activity.request)"
        case .question(let questions): questions.count == 1 ? "a question" : "\(questions.count) questions"
        }
    }
}
