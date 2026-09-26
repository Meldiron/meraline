import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @Bindable var preferences: Preferences
    @State private var loginItemStatus = SMAppService.mainApp.status
    @State private var loginItemError: String?

    var body: some View {
        Form {
            PaneHeader(pane: .general, summary: "Choose how Meraline opens and where its window appears.")

            Section {
                LabeledContent("Keyboard shortcut") {
                    KeyboardShortcuts.Recorder(for: .togglePanel)
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
                Picker("Start a new chat", selection: $preferences.idleReset) {
                    ForEach(IdleReset.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Window")
            } footer: {
                Text("When the window has been hidden this long, the chat moves to Recent Chats and your next question starts fresh.")
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
                Text("Chats live only in memory and are never written to disk. Quitting Meraline forgets them.")
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItemStatus = SMAppService.mainApp.status }
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
            PaneHeader(pane: .prompt, summary: "Tell the model how to answer. These instructions are sent with every question.")

            Section {
                TextEditor(text: $preferences.systemPrompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .labelsHidden()
            } header: {
                Text("Instructions")
            } footer: {
                HStack {
                    Spacer()
                    Button("Restore Default") { preferences.systemPrompt = Preferences.defaultSystemPrompt }
                        .disabled(preferences.systemPrompt == Preferences.defaultSystemPrompt)
                }
            }
        }
        .formStyle(.grouped)
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
            PaneHeader(pane: .softwareUpdate, summary: "Meraline \(Bundle.main.shortVersion)")

            if updater.isAvailable {
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
                    Picker("Update channel", selection: $updater.channel) {
                        ForEach(UpdateChannel.allCases) { Text($0.title).tag($0) }
                    }
                } footer: {
                    Text(updater.channel.summary)
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
                Section {
                    Label("This build of Meraline isn’t set up to receive updates.", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutPane: View {
    let preferences: Preferences
    let updater: Updater
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
        Diagnostics.copyToPasteboard(Diagnostics.report(preferences: preferences, updates: updater.status))
        Log.app.info("Diagnostics copied")
        withAnimation { copiedDiagnostics = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { copiedDiagnostics = false }
        }
    }
}

extension Bundle {
    var shortVersion: String { object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    var buildNumber: String { object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
}
