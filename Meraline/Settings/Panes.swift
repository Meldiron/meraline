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
                Picker("Default provider", selection: $preferences.provider) {
                    if preferences.readyProviders.isEmpty {
                        Text("None").tag(Provider?.none)
                    }
                    ForEach(preferences.readyProviders) { provider in
                        Label(provider.name, systemImage: provider.symbol).tag(Provider?.some(provider))
                    }
                }
                .disabled(preferences.readyProviders.isEmpty)
            } header: {
                Text("Provider")
            } footer: {
                Text("Chats live only in memory and are never written to disk. Quitting Meraline forgets them.")
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItemStatus = SMAppService.mainApp.status }
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
                if settings.isReady(for: provider) && preferences.activeProvider != provider {
                    LabeledContent("Default provider") {
                        Button("Use \(provider.name)") { preferences.provider = provider }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings) { test = .idle }
    }

    private var onDeviceModelIsAvailable: Bool { AppleIntelligenceClient.isAvailable }

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
                for try await _ in LLMClient.stream(request) {}
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
