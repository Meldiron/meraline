import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @Bindable var preferences: Preferences
    /// Opens Settings › Permissions, which says whether Meraline may read the selection.
    let showPermissions: () -> Void
    @State private var loginItemStatus = SMAppService.mainApp.status
    @State private var loginItemError: String?

    var body: some View {
        Form {
            PaneHeader(pane: .general, summary: "Choose how Meraline opens and where its window appears.")

            Section {
                LabeledContent {
                    KeyboardShortcuts.Recorder(for: .togglePanel)
                } label: {
                    Text("Keyboard shortcut")
                    Text("ChatGPT, Gemini, and Raycast often use ⌥ Space too. If Meraline doesn’t open, pick another.")
                }
                Toggle("Open at login", isOn: launchAtLogin)
                    .tint(.meralinePink)
                Toggle("Show in menu bar", isOn: $preferences.showsMenuBarIcon)
                    .tint(.meralinePink)
            } footer: {
                if loginItemStatus == .requiresApproval {
                    HStack {
                        Text("Allow Meraline in Login Items to finish turning this on.")
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                            .buttonStyle(.link)
                    }
                } else if let loginItemError {
                    Text(loginItemError).foregroundStyle(.red)
                } else if !preferences.showsMenuBarIcon {
                    Text("To open Settings without the menu bar icon, open Meraline again from Finder or Spotlight.")
                }
            }

            Section {
                Picker("Open window", selection: $preferences.placement) {
                    ForEach(PanelPlacement.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Keep open when clicking elsewhere", isOn: $preferences.isPinned)
                    .tint(.meralinePink)
            } header: {
                Text("Window")
            }

            Section {
                Toggle(isOn: $preferences.hidesFromScreenSharing) {
                    Text("Hide from screen sharing")
                    Text("Asks macOS to leave the window out of screen sharing, recordings, and screenshots. Apps that capture the whole display, such as QuickTime, may still show it, so try yours before a call that matters.")
                }
                .tint(.meralinePink)
                Toggle(isOn: $preferences.forgetsChatsOnSleep) {
                    Text("Forget chats when the Mac sleeps")
                    Text("Also when its display turns off.")
                }
                .tint(.meralinePink)
                Toggle(isOn: $preferences.forgetsChatsOnLock) {
                    Text("Forget chats when the screen locks")
                    Text("Also when you switch to another user.")
                }
                .tint(.meralinePink)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Chats live only in memory and are never written to disk, so quitting Meraline, restarting, shutting down, or logging out forgets them. Forgetting takes the open chat and what’s typed in it, Recent Chats, torn-off answers, and the files agents worked on.")
            }

            Section {
                Toggle(isOn: $preferences.bringsSelection) {
                    Text("Bring the selection")
                    Text("When you press the shortcut, text you select in any app waits behind the cursor button above the window until you add it, and files and folders selected in Finder come along. When you ask an LLM, only photos come from Finder.")
                }
                .tint(.meralinePink)
            } header: {
                Text("Selection")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Most apps share their selection directly. In the few that don't, such as browsers or Zed, Meraline uses the app's own Copy command, or presses ⌘C in an app that describes nothing but its window, and then puts back what was on the clipboard.")
                    if preferences.bringsSelection && !SelectionAccess.shared.isGranted {
                        HStack {
                            Text("Reading the selection needs Accessibility access.")
                            Button("Open Permissions", action: showPermissions)
                                .buttonStyle(.link)
                        }
                    }
                }
            }

            Section {
                ForEach(ProviderKind.allCases) { kind in
                    let ready = preferences.readyProviders(for: kind)
                    Picker("Default \(kind.title)", selection: defaultProvider(for: kind)) {
                        if ready.isEmpty {
                            Text("None").tag(Provider?.none)
                        }
                        ForEach(ready) { provider in
                            Label(provider.name, systemImage: provider.symbol).tag(Provider?.some(provider))
                        }
                    }
                    .disabled(ready.isEmpty)
                }
            } header: {
                Text("Providers")
            } footer: {
                Text("Apple Intelligence, and Ollama running a model on this Mac, answer without your question leaving it.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loginItemStatus = SMAppService.mainApp.status
            SelectionAccess.shared.refresh()
        }
    }

    /// A mode's provider. Picking here leaves the panel in the mode it is in.
    private func defaultProvider(for kind: ProviderKind) -> Binding<Provider?> {
        Binding(
            get: { preferences.defaultProvider(for: kind) },
            set: { preferences.setDefaultProvider($0, for: kind) }
        )
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { loginItemStatus == .enabled || loginItemStatus == .requiresApproval },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    loginItemError = nil
                } catch {
                    loginItemError = error.localizedDescription
                }
                loginItemStatus = SMAppService.mainApp.status
            }
        )
    }
}

struct PromptPane: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            PaneHeader(pane: .prompt, summary: "Tell the models how to answer, and keep the prompts you use most a click away. LLMs and agents each have their own instructions, and each game plays by its own.")

            Section {
                Picker("Language", selection: $preferences.language) {
                    ForEach(AnswerLanguage.allCases) { Text($0.title).tag($0) }
                }
            } footer: {
                Text("LLMs and agents answer in it, unless you ask for another, as for a translation, and the games are played in it. Meraline adds a line saying so after the instructions below.")
            }

            ForEach(ProviderKind.allCases) { kind in
                Section {
                    editor(for: .chat(kind))
                } header: {
                    Text(kind.pluralTitle)
                } footer: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(kind == .llm
                            ? "Sent with every question to Apple Intelligence and the other LLMs."
                            : "Sent with every question to Claude Code, Codex, and OpenCode, with a word from Meraline on handing files over to you.")
                        Spacer()
                        restoreButton(for: .chat(kind))
                    }
                }
            }

            PresetsSection(preferences: preferences)

            Section {
                ForEach(Game.allCases) { game in
                    disclosure(for: .game(game), symbol: game.symbol)
                }
            } header: {
                Text("Games")
            } footer: {
                Text("A game sends its own instructions instead of the LLMs’ or the agents’. It reads the model’s moves in the format they ask for, such as “OK: ” or the “ | ” before a hidden answer, so keep those as they are.")
            }

            Section {
                disclosure(for: .toolReason, symbol: "questionmark.bubble")
            } header: {
                Text("Agent Tools")
            } footer: {
                Text("When Claude Code asks before it writes a file, runs a command, or uses a skill, Why? has it say in one line why it wants to. A click on a tool under a finished answer has the agent that used it say why it did.")
            }
        }
        .formStyle(.grouped)
    }

    private func editor(for prompt: SystemPrompt, minHeight: CGFloat = 140) -> some View {
        TextEditor(text: $preferences[prompt: prompt])
            .font(.body)
            .scrollContentBackground(.hidden)
            .frame(minHeight: minHeight)
            .labelsHidden()
    }

    private func restoreButton(for prompt: SystemPrompt) -> some View {
        Button("Restore Default") { preferences[prompt: prompt] = prompt.standard }
            .disabled(!preferences.isChanged(prompt))
    }

    /// A prompt folded under its title, which says when it was changed.
    private func disclosure(for prompt: SystemPrompt, symbol: String) -> some View {
        DisclosureGroup {
            editor(for: prompt, minHeight: 220)
            HStack {
                Spacer()
                restoreButton(for: prompt)
            }
        } label: {
            HStack {
                Label {
                    Text(prompt.title)
                } icon: {
                    Image(systemName: symbol).frame(width: 22)
                }
                Spacer()
                if preferences.isChanged(prompt) {
                    Text("Changed").foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ProviderPane: View {
    let provider: Provider
    let preferences: Preferences
    @State private var test = ConnectionTest.idle

    private enum ConnectionTest: Equatable {
        case idle
        case running
        case succeeded
        case failed(String)
    }

    private var settings: ProviderSettings { preferences[provider] }
    private var registry: MCPServerRegistry { .shared }

    private var modelPlaceholder: String {
        if provider.isCommandLine { return "Default" }
        return provider == .custom ? "Model identifier" : provider.defaultModel
    }

    var body: some View {
        Form {
            PaneHeader(pane: .provider(provider), summary: provider.summary)

            Section {
                if provider.keyPolicy != .required {
                    Toggle("Use \(provider.name)", isOn: binding(\.isEnabled))
                        .tint(.meralinePink)
                        .disabled(provider.isOnDevice && !onDeviceModelIsAvailable && !settings.isEnabled)
                }
                if provider.keyPolicy != .none {
                    SecureField(
                        provider.keyPolicy == .required ? "API key" : "API key (optional)",
                        text: binding(\.apiKey),
                        prompt: Text("Paste your key")
                    )
                }
                if !provider.isOnDevice {
                    TextField("Model", text: binding(\.model), prompt: Text(modelPlaceholder))
                        .textInputSuggestions(provider.suggestedModels, id: \.self) { Text($0).textInputCompletion($0) }
                }
                if provider.isCommandLine {
                    Picker("Reasoning effort", selection: binding(\.effort)) {
                        ForEach(ReasoningEffort.allCases) { Text($0.title).tag($0) }
                    }
                }
                if provider.supportsWebSearch {
                    Toggle(isOn: binding(\.allowsWebSearch)) {
                        Text("Allow web search")
                        Text(provider == .claudeCode
                            ? "Lets Claude search and read web pages for current information. Answers take longer."
                            : "Lets Codex search the web for current information. Answers take longer.")
                    }
                    .tint(.meralinePink)
                }
                if provider.supportsMCP {
                    Toggle(isOn: binding(\.allowsMCP)) {
                        Text("Allow MCP servers")
                        Text("Lets \(provider.name) use the MCP servers set up in it. Each tool it calls shows up while it answers and under the answer.")
                    }
                    .tint(.meralinePink)
                }
            } footer: {
                if provider.isOnDevice {
                    Text("Answers are generated on this Mac and never leave it. The model is small: good for quick facts, rewrites, and summaries, with room for only a few follow-ups.")
                } else if let portal = provider.keyPortal {
                    Link(provider.keyPolicy == .none ? "Install \(provider.name)" : "Get an API key", destination: portal)
                }
            }

            if provider.isOnDevice {
                Section("Availability") {
                    LabeledContent {
                        availabilityStatus
                    } label: {
                        Text("Apple Intelligence")
                        if case .unavailable(let reason) = AppleIntelligenceClient.availability {
                            Text(AppleIntelligenceClient.explanation(for: reason))
                        } else {
                            Text("Ready on this Mac")
                        }
                    }
                }
            } else {
                Section {
                    TextField(
                        provider.isCommandLine ? "Command" : "Server address",
                        text: binding(\.baseURL),
                        prompt: Text(provider.defaultBaseURL)
                    )
                    if provider.isCommandLine {
                        LabeledContent("Location") {
                            if let path = CommandLineClient.resolve(settings.baseURL)?.path {
                                Text(path).textSelection(.enabled)
                            } else {
                                Text("Not found").foregroundStyle(.red)
                            }
                        }
                    }
                } header: {
                    Text(provider.isCommandLine ? "Command" : "Connection")
                } footer: {
                    if settings.baseURL != provider.defaultBaseURL && !provider.defaultBaseURL.isEmpty {
                        HStack {
                            Spacer()
                            Button("Restore Default") { update(\.baseURL, provider.defaultBaseURL) }
                        }
                    }
                }
            }

            if provider.supportsMCP {
                Section {
                    mcpServers
                } header: {
                    Text("MCP Servers")
                } footer: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Meraline asks \(provider.name) for this list and never changes its setup. Add a server with “\(settings.baseURL.trimmed) mcp add”, and turn one off here to keep it out of your questions.")
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if registry.refreshing.contains(provider) {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Refresh") { registry.refresh(provider, preferences: preferences) }
                                .disabled(!settings.isReady(for: provider))
                        }
                    }
                }
            }

            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        testStatus
                        Button("Test Connection", action: runTest)
                            .disabled(!settings.isReady(for: provider) || test == .running)
                    }
                } label: {
                    Text("Status")
                    Text(settings.isReady(for: provider) ? "Ready to answer" : "Not set up")
                }
                if settings.isReady(for: provider) && preferences.defaultProvider(for: provider.kind) != provider {
                    LabeledContent("Default \(provider.kind.title)") {
                        Button("Use \(provider.name)") { preferences.provider = provider }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings) { test = .idle }
        .task(id: provider) {
            if provider.supportsMCP, !registry.hasListed(provider), settings.isReady(for: provider) {
                registry.refresh(provider, preferences: preferences)
            }
        }
    }

    private var onDeviceModelIsAvailable: Bool { AppleIntelligenceClient.isAvailable }

    /// One toggle per server the agent listed, or what stands in its place: the wait for the list, why
    /// it failed, or how to add a first server.
    @ViewBuilder
    private var mcpServers: some View {
        if let servers = registry.servers[provider], !servers.isEmpty {
            ForEach(servers) { server in
                Toggle(isOn: serverBinding(server)) {
                    Text(server.name)
                    Text(server.target.isEmpty ? server.status.title : "\(server.status.title) · \(server.target)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .tint(.meralinePink)
                .disabled(!settings.allowsMCP || !server.status.isUsable)
            }
        } else if registry.refreshing.contains(provider) {
            LabeledContent {
                ProgressView().controlSize(.small)
            } label: {
                Text("Asking \(provider.name) for its servers…")
            }
        } else if let failure = registry.failures[provider] {
            LabeledContent {
                Button("Try Again") { registry.refresh(provider, preferences: preferences) }
            } label: {
                Text("Couldn’t list the servers")
                Text(failure)
            }
        } else if !settings.isReady(for: provider) {
            Text("Turn on \(provider.name) to see its MCP servers.")
                .foregroundStyle(.secondary)
        } else {
            LabeledContent {
                if let portal = provider.mcpPortal {
                    Link("Learn More", destination: portal)
                }
            } label: {
                Text("No MCP servers")
                Text("\(provider.name) has none set up yet.")
            }
        }
    }

    private func serverBinding(_ server: MCPServer) -> Binding<Bool> {
        Binding(
            get: { server.status.isUsable && !preferences[provider].disabledMCPServers.contains(server.name) },
            set: { isOn in
                var updated = preferences[provider]
                if isOn {
                    updated.disabledMCPServers.remove(server.name)
                } else {
                    updated.disabledMCPServers.insert(server.name)
                }
                preferences[provider] = updated
                Log.settings.info("\(provider.name) MCP server \(isOn ? "on" : "off"): \(server.name)")
            }
        )
    }

    @ViewBuilder
    private var availabilityStatus: some View {
        if onDeviceModelIsAvailable {
            Label("Available", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            HStack(spacing: 8) {
                Label("Not available", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Button("Open System Settings") {
                    let pane = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!
                    NSWorkspace.shared.open(pane)
                }
            }
        }
    }

    @ViewBuilder
    private var testStatus: some View {
        switch test {
        case .idle:
            EmptyView()
        case .running:
            ProgressView().controlSize(.small)
        case .succeeded:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label("Failed", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .help(message)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<ProviderSettings, Value>) -> Binding<Value> {
        Binding(get: { preferences[provider][keyPath: keyPath] }, set: { update(keyPath, $0) })
    }

    private func update<Value>(_ keyPath: WritableKeyPath<ProviderSettings, Value>, _ value: Value) {
        var updated = preferences[provider]
        updated[keyPath: keyPath] = value
        preferences[provider] = updated
    }

    private func runTest() {
        test = .running
        let request = ChatRequest(
            provider: provider,
            settings: settings,
            systemPrompt: "Reply with a single word.",
            messages: [ChatMessage(role: .user, text: "Say ready.")]
        )
        Task {
            do {
                for try await output in LLMClient.stream(request) {
                    if case .prompt(_, let responder?) = output { responder(.deny) }
                }
                test = .succeeded
            } catch {
                test = .failed(error.localizedDescription)
            }
        }
    }
}

struct SoftwareUpdatePane: View {
    @Bindable var updater: Updater

    var body: some View {
        Form {
            if updater.isAvailable {
                PaneHeader(pane: .softwareUpdate) {
                    ChannelChip(version: updater.currentVersion)
                }
                if let staged = updater.stagedUpdate {
                    Section {
                        LabeledContent {
                            Button("Restart to Update", action: updater.installStagedUpdate)
                        } label: {
                            Text("Meraline \(staged.version) is ready")
                            Text("It installs when you quit Meraline, or right now.")
                        }
                    }
                } else if let available = updater.availableUpdate {
                    Section {
                        LabeledContent {
                            Button("Update…", action: updater.checkForUpdates)
                        } label: {
                            Text("Meraline \(available.version) is available")
                        }
                    }
                }
                Section {
                    Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
                        .tint(.meralinePink)
                    Toggle("Download and install updates automatically", isOn: $updater.downloadsAutomatically)
                        .tint(.meralinePink)
                        .disabled(!updater.checksAutomatically)
                }
                Section {
                    Toggle(isOn: getsBetas) {
                        Text("Get beta updates")
                        Text(updater.channel.summary)
                    }
                    .tint(.meralinePink)
                } footer: {
                    if updater.isLeavingBeta {
                        Text("This beta stays until a stable release newer than \(updater.currentVersion) comes out.")
                    }
                }
                Section {
                    LabeledContent("Last checked") {
                        if let lastCheck = updater.lastCheck {
                            Text(lastCheck, format: .relative(presentation: .named))
                        } else {
                            Text("Never")
                        }
                    }
                    LabeledContent("Check for new versions") {
                        Button("Check Now", action: updater.checkForUpdates)
                            .disabled(!updater.canCheckForUpdates)
                    }
                }
            } else {
                PaneHeader(pane: .softwareUpdate, summary: "Meraline \(updater.currentVersion)")
                Section {
                    Label("This build of Meraline isn’t set up to receive updates.", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Stable or Beta as one switch: on follows the beta feed, off the stable one.
    private var getsBetas: Binding<Bool> {
        Binding { updater.channel == .beta } set: { updater.channel = $0 ? .beta : .stable }
    }
}

struct AboutPane: View {
    let preferences: Preferences
    let updater: Updater
    let session: ChatSession
    @State private var copiedDiagnostics = false

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                    Text("Meraline")
                        .font(.largeTitle.weight(.semibold))
                    Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Quick, ephemeral chats with the AI model of your choice.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                    if updater.isAvailable {
                        Button("Check for Updates…", action: updater.checkForUpdates)
                            .disabled(!updater.canCheckForUpdates)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } footer: {
                if let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String {
                    Text(copyright).frame(maxWidth: .infinity)
                }
            }

            Section {
                if let notes = Bundle.main.releaseNotesURL(for: Bundle.main.shortVersion) {
                    LabeledContent("Release notes") {
                        Link("What’s new in \(Bundle.main.shortVersion)", destination: notes)
                    }
                }
                LabeledContent {
                    HStack(spacing: 8) {
                        if copiedDiagnostics {
                            Label("Copied", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .transition(.opacity)
                        }
                        Button("Copy Diagnostics", action: copyDiagnostics)
                    }
                } label: {
                    Text("Diagnostics")
                    Text("Versions, provider setup, and recent events. No keys, questions, or answers.")
                }
                if let issue = Bundle.main.newIssueURL {
                    LabeledContent("Found a bug?") {
                        Link("Report It on GitHub", destination: issue)
                    }
                }
            } header: {
                Text("Support")
            }
        }
        .formStyle(.grouped)
    }

    private func copyDiagnostics() {
        Task {
            let storage = await Diagnostics.storage(of: session)
            Diagnostics.copyToPasteboard(Diagnostics.report(preferences: preferences, updates: updater.status, storage: storage))
            Log.app.info("Diagnostics copied")
            withAnimation { copiedDiagnostics = true }
            try? await Task.sleep(for: .seconds(2))
            withAnimation { copiedDiagnostics = false }
        }
    }
}

extension Bundle {
    var shortVersion: String { object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    var buildNumber: String { object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
}
