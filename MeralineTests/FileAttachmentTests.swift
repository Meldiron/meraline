import Foundation
import Testing
@testable import Meraline

@MainActor
struct FileAttachmentTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "MeralineTests.files.\(UUID().uuidString)")

    private var workspaces: URL { folder.appending(path: "Workspaces") }

    /// A file with `contents` in the test's own folder.
    private func file(_ name: String, _ contents: String = "The secret word is periwinkle.") throws -> URL {
        let url = folder.appending(path: "Finder").appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }

    /// A session with a ready LLM and a ready agent, in LLM mode.
    private func session(_ model: ScriptedModel) -> (ChatSession, Preferences) {
        let preferences = GameTestSupport.preferences()
        preferences[.claudeCode] = ProviderSettings(model: "", baseURL: "/bin/echo", apiKey: "", isEnabled: true)
        preferences.mode = .llm
        return (ChatSession(preferences: preferences, workspaceRoot: workspaces) { model.stream($0) }, preferences)
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Runs git in `folder`, for building a repository to attach.
    private func git(_ arguments: String..., in folder: URL) async throws {
        let git = try #require(CommandLineClient.resolve("git"))
        _ = try await CommandLineClient.output(of: git, arguments: ["-C", folder.path] + arguments, timeout: .seconds(30))
    }

    /// Writes `files` (path and contents) under `root`, making folders as needed.
    private func write(_ files: [String: String], in root: URL) throws {
        for (path, contents) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
        }
    }

    /// Every file under `root`, by path, leaving out the insides of .git.
    private func listing(of root: URL) -> Set<String> {
        let items = FileManager.default.subpaths(atPath: root.path) ?? []
        return Set(items.filter { path in
            var isFolder: ObjCBool = false
            FileManager.default.fileExists(atPath: root.appending(path: path).path, isDirectory: &isFolder)
            return !isFolder.boolValue && !path.hasPrefix(".git/")
        })
    }

    @Test func namesStayUniqueWithinAChat() {
        #expect(FileAttachment.uniqueName(for: "report.pdf", avoiding: []) == "report.pdf")
        #expect(FileAttachment.uniqueName(for: "report.pdf", avoiding: ["Report.PDF"]) == "report 2.pdf")
        #expect(FileAttachment.uniqueName(for: "report.pdf", avoiding: ["report.pdf", "report 2.pdf"]) == "report 3.pdf")
        #expect(FileAttachment.uniqueName(for: "Makefile", avoiding: ["Makefile"]) == "Makefile 2")
        #expect(FileAttachment.uniqueName(for: "my.project", splittingExtension: false, avoiding: ["my.project"]) == "my.project 2")
    }

    @Test func attachmentsAreNamedByFormat() {
        func kinds(_ names: String...) -> String {
            FileAttachment.kinds(of: names.map { name in
                FileAttachment(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name.replacingOccurrences(of: "/", with: ""), isFolder: name.hasSuffix("/"))
            })
        }
        #expect(kinds("BQAAWvPPZuf3QHdhOjEwMDAwNTIwOTU0NTc1MkBtc2dyOjEwMDAwNTIwOTU0NTc1MkBtc2dyOjc1MDgxNzU5NTA3NTI3NzYyMzQA.pdf") == "PDF files")
        #expect(kinds("a.pdf", "b.PDF", "c.csv") == "PDF and CSV files")
        #expect(kinds("a.pdf", "b.csv", "c.txt") == "PDF, CSV, and TXT files")
        #expect(kinds("a.pdf", "b.csv", "c.txt", "d.zip") == "these files")
        #expect(kinds("a.pdf", "project/") == "PDF files and folders")
        #expect(kinds("project/", "other/") == "folders")
        #expect(kinds("Makefile") == "these files")
    }

    @Test func filesAndFoldersAreAttachedButNotAHomeOrADisk() throws {
        let url = try file("notes.txt")
        let attachment = try FileAttachment.make(from: url, avoiding: [])
        #expect(attachment.name == "notes.txt")
        #expect(!attachment.isFolder)
        let project = try FileAttachment.make(from: url.deletingLastPathComponent(), avoiding: [])
        #expect(project.name == "Finder")
        #expect(project.isFolder)
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(throws: AttachmentError.tooManyFiles(home.lastPathComponent)) { try FileAttachment.make(from: home, avoiding: []) }
        #expect(throws: AttachmentError.tooManyFiles("/")) { try FileAttachment.make(from: URL(fileURLWithPath: "/"), avoiding: []) }
        #expect(throws: AttachmentError.unreadableFile) { try FileAttachment.make(from: folder.appending(path: "gone.pdf"), avoiding: []) }
        cleanUp()
    }

    @Test func aRepositoryBringsWhatGitKeepsAndItsHistory() async throws {
        let project = folder.appending(path: "project")
        try write([
            ".gitignore": "build/\n*.log\n",
            "Sources/app.swift": "print(1)",
            "gone.txt": "soon deleted",
            "notes.md": "not added yet, not ignored",
            "build/output.bin": "ignored",
            "debug.log": "ignored"
        ], in: project)
        try await git("init", "-q", in: project)
        try await git("add", "Sources/app.swift", "gone.txt", in: project)
        try FileManager.default.removeItem(at: project.appending(path: "gone.txt"))

        let workspace = folder.appending(path: "Workspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try await FileAttachment.copy([try FileAttachment.make(from: project, avoiding: [])], into: workspace)
        let copy = workspace.appending(path: "project")
        #expect(listing(of: copy) == [".gitignore", "Sources/app.swift", "notes.md"])
        #expect(FileManager.default.fileExists(atPath: copy.appending(path: ".git/HEAD").path))

        // Part of a repository: its files, without the repository's history.
        try await FileAttachment.copy([try FileAttachment.make(from: project.appending(path: "Sources"), avoiding: [])], into: workspace)
        #expect(listing(of: workspace.appending(path: "Sources")) == ["app.swift"])
        #expect(!FileManager.default.fileExists(atPath: workspace.appending(path: "Sources/.git").path))
        cleanUp()
    }

    @Test func aFolderOutsideGitComesWholeUnlessItIsTooBig() async throws {
        let notes = folder.appending(path: "notes")
        try write(["a.txt": "a", "b/c.txt": "c"], in: notes)
        let attachment = try FileAttachment.make(from: notes, avoiding: [])
        let workspace = folder.appending(path: "Workspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try await FileAttachment.copy([attachment], into: workspace)
        #expect(listing(of: workspace.appending(path: "notes")) == ["a.txt", "b/c.txt"])
        await #expect(throws: AttachmentError.tooManyFiles("notes")) {
            try await FileAttachment.copy([attachment], into: workspace, limit: 2)
        }

        let project = folder.appending(path: "project")
        try write(["a.txt": "a", "b.txt": "b", "c.txt": "c"], in: project)
        try await git("init", "-q", in: project)
        await #expect(throws: AttachmentError.tooManyFiles("project")) {
            try await FileAttachment.copy([try FileAttachment.make(from: project, avoiding: [])], into: workspace, limit: 2)
        }
        cleanUp()
    }

    @Test func copiesReplaceWhatHasTheirName() async throws {
        let destination = folder.appending(path: "Workspace")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: destination.appending(path: "notes.txt"))
        let attachment = try FileAttachment.make(from: try file("notes.txt", "new"), avoiding: [])
        try await FileAttachment.copy([attachment], into: destination)
        #expect(try String(contentsOf: destination.appending(path: "notes.txt"), encoding: .utf8) == "new")
        cleanUp()
    }

    @Test func anLLMAsksYouToSwitchToAgentForAFile() async throws {
        let model = ScriptedModel(["It says periwinkle."])
        let (session, preferences) = session(model)
        let pdf = try file("report.pdf")
        session.attach(fileAt: pdf)
        session.attach(fileAt: pdf)
        #expect(session.draftFiles.map(\.name) == ["report.pdf"], "the same file is attached once")
        #expect(session.draftImages.isEmpty)
        #expect(session.failure == nil)
        #expect(session.fileNotice == "Only an agent can read PDF files. Switch to Agent to send it.")

        session.draft = "What does it say?"
        #expect(!session.canSend)
        session.send()
        #expect(model.requests.isEmpty)
        #expect(session.draftFiles.count == 1, "the file waits in the draft")

        preferences.mode = .agent
        #expect(session.fileNotice == nil)
        #expect(session.canSend)
        session.send()
        await GameTestSupport.settle(session)
        let request = try #require(model.requests.last)
        #expect(request.provider == .claudeCode)
        #expect(request.workspace != nil)
        #expect(request.messages.last?.files.map(\.url) == [pdf])
        #expect(session.turns.last?.files.map(\.name) == ["report.pdf"])
        #expect(session.draftFiles.isEmpty)

        // The chat has a report.pdf, so another one by that name gets a number.
        session.attach(fileAt: try file("report.pdf", "A second report."))
        #expect(session.draftFiles.map(\.name) == ["report 2.pdf"])
        session.removeAttachment(try #require(session.draftFiles.first).id)
        #expect(session.draftFiles.isEmpty)
        ChatWorkspace.removeAll(in: workspaces)
        cleanUp()
    }

    @Test func severalFilesAreNamedAsMany() throws {
        let (session, _) = session(ScriptedModel())
        session.attach(fileAt: try file("a.csv"))
        session.attach(fileAt: try file("b.csv"))
        #expect(session.fileNotice == "Only an agent can read CSV files. Switch to Agent to send them.")
        cleanUp()
    }

    @Test func aFolderWaitsForAnAgentLikeAFile() throws {
        let (session, _) = session(ScriptedModel())
        let project = try file("app.swift").deletingLastPathComponent()
        session.attach(fileAt: project)
        session.attach(fileAt: URL(fileURLWithPath: project.path + "/"))
        #expect(session.draftFiles.map(\.name) == ["Finder"], "the same folder is attached once")
        #expect(session.draftFiles.first?.isFolder == true)
        #expect(session.fileNotice == "Only an agent can read folders. Switch to Agent to send it.")

        session.attach(fileAt: FileManager.default.homeDirectoryForCurrentUser)
        #expect(session.draftFiles.count == 1)
        #expect(session.failure == AttachmentError.tooManyFiles(FileManager.default.homeDirectoryForCurrentUser.lastPathComponent).localizedDescription)
        cleanUp()
    }

    @Test func copyingIsNotATool() {
        var tools: [Activity] = []
        ChatSession.record(.copying("project"), in: &tools)
        #expect(tools.isEmpty)
        #expect(Activity.copying("project").title == "Copying “project”")
    }

    @Test func filesSitAGameOut() throws {
        let (session, _) = session(ScriptedModel())
        session.startGame(.rhymeDuel)
        session.attach(fileAt: try file("notes.txt"))
        #expect(session.draftFiles.isEmpty)
        #expect(session.nudge == Game.noImages)
        cleanUp()
    }

    @Test func theAgentIsToldWhereItsFilesAre() throws {
        let report = try FileAttachment.make(from: try file("report.pdf"), avoiding: [])
        let data = try FileAttachment.make(from: try file("data.csv"), avoiding: [])
        let project = try FileAttachment.make(from: report.url.deletingLastPathComponent(), avoiding: [])
        #expect(CommandLineClient.transcript(of: [ChatMessage(role: .user, text: "Summarize", files: [report, project])]) == """
        Summarize

        Attached, copied into the working directory:
        - report.pdf
        - Finder/
        """)
        let followUp = CommandLineClient.transcript(of: [
            ChatMessage(role: .user, text: "", files: [report, data]),
            ChatMessage(role: .assistant, text: "Got them."),
            ChatMessage(role: .user, text: "Which is longer?")
        ])
        #expect(followUp.contains("User: Attached, copied into the working directory:\n- report.pdf\n- data.csv"))
        #expect(followUp.hasSuffix("Which is longer?"))
        cleanUp()
    }

    @Test func anAgentFindsItsFilesInTheWorkspace() async throws {
        let workspace = folder.appending(path: "Workspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let report = try FileAttachment.make(from: try file("report.pdf"), avoiding: [])
        let project = try FileAttachment.make(from: report.url.deletingLastPathComponent(), avoiding: [])
        var request = ChatRequest(
            provider: .codex,
            settings: ProviderSettings(model: "", baseURL: "/bin/echo", apiKey: "", isEnabled: true),
            systemPrompt: "",
            messages: [ChatMessage(role: .user, text: "Summarize", files: [report, project])]
        )
        request.workspace = workspace
        // echo prints nothing codex would say, so the run ends empty; the copy is made before it starts.
        var activities: [Activity] = []
        do {
            for try await output in CommandLineClient.stream(request) {
                if case .activity(let activity) = output { activities.append(activity) }
            }
            Issue.record("echo gave an answer")
        } catch {
            #expect(error as? LLMError == .emptyResponse)
        }
        #expect(activities == [.copying("Finder"), .thinking])
        #expect(try String(contentsOf: workspace.appending(path: "report.pdf"), encoding: .utf8) == "The secret word is periwinkle.")
        #expect(FileManager.default.fileExists(atPath: workspace.appending(path: "Finder/report.pdf").path))
        cleanUp()
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MERALINE_CLI_E2E"] != nil))
    func installedAgentsReadAttachedFiles() async throws {
        let models: [Provider: String] = [.claudeCode: "", .codex: "", .opencode: "opencode/big-pickle"]
        let secret = try FileAttachment.make(from: try file("secret.txt"), avoiding: [])
        for provider in Provider.commandLineTools where CommandLineClient.resolve(provider.defaultBaseURL) != nil {
            let workspace = try ChatWorkspace.make(in: workspaces)
            var request = ChatRequest(
                provider: provider,
                settings: ProviderSettings(model: models[provider]!, baseURL: provider.defaultBaseURL, apiKey: "", isEnabled: true, effort: .low),
                systemPrompt: "Reply with exactly one lowercase word.",
                messages: [ChatMessage(role: .user, text: "What is the secret word in the attached file?", files: [secret])]
            )
            request.workspace = workspace.url
            var answer = ""
            for try await output in LLMClient.stream(request) {
                if case .text(let text) = output { answer += text }
            }
            #expect(answer.lowercased().contains("periwinkle"), "\(provider.name) answered: \(answer)")
        }
        ChatWorkspace.removeAll(in: workspaces)
        cleanUp()
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MERALINE_CLI_E2E"] != nil))
    func installedAgentsFindTheirWayAroundAFolder() async throws {
        let models: [Provider: String] = [.claudeCode: "", .codex: "", .opencode: "opencode/big-pickle"]
        let project = folder.appending(path: "garden")
        try write([
            "README.md": "A garden planner.",
            "Sources/Beds/Colors.swift": "// The secret word is periwinkle.\nlet border = \"blue\"",
            ".gitignore": "build/\n",
            "build/decoy.txt": "The secret word is marigold."
        ], in: project)
        try await git("init", "-q", in: project)
        let garden = try FileAttachment.make(from: project, avoiding: [])
        for provider in Provider.commandLineTools where CommandLineClient.resolve(provider.defaultBaseURL) != nil {
            let workspace = try ChatWorkspace.make(in: workspaces)
            var request = ChatRequest(
                provider: provider,
                settings: ProviderSettings(model: models[provider]!, baseURL: provider.defaultBaseURL, apiKey: "", isEnabled: true, effort: .low),
                systemPrompt: "Reply with exactly one lowercase word.",
                messages: [ChatMessage(role: .user, text: "Somewhere in this project a comment says what the secret word is. What is it?", files: [garden])]
            )
            request.workspace = workspace.url
            var answer = ""
            for try await output in LLMClient.stream(request) {
                if case .text(let text) = output { answer += text }
            }
            #expect(answer.lowercased().contains("periwinkle"), "\(provider.name) answered: \(answer)")
        }
        ChatWorkspace.removeAll(in: workspaces)
        cleanUp()
    }

    @Test func aChatOfFilesIsTitledAndCopiedByName() throws {
        let report = try FileAttachment.make(from: try file("report.pdf"), avoiding: [])
        var turn = ChatSession.Turn(question: "", images: [ImageAttachment(mediaType: "image/png", data: Data([1]))], files: [report])
        turn.answer = "A report."
        turn.isComplete = true
        #expect(ChatSession.PastChat(turns: [turn], date: .now).title == "report.pdf")
        #expect(ChatSession.markdown(for: [turn])?.hasPrefix("**You**\n\n_1 image, report.pdf attached_") == true)
        cleanUp()
    }
}
