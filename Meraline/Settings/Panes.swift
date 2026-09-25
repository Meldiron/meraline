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
                Toggle("Show in menu bar", isOn: $preferences.showsMenuBarIcon)
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

            Section("Window") {
                Picker("Open window", selection: $preferences.placement) {
                    ForEach(PanelPlacement.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Keep open when clicking elsewhere", isOn: $preferences.isPinned)
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
                Text("Chats live only in memory. Closing the window forgets the conversation.")
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

struct AnswersPane: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            PaneHeader(pane: .answers, summary: "Tell the model how to answer. These instructions are sent with every question.")

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
                }
                if provider.keyPolicy != .none {
                    SecureField(
                        provider.keyPolicy == .required ? "API key" : "API key (optional)",
                        text: binding(\.apiKey),
                        prompt: Text("Paste your key")
                    )
                }
                TextField("Model", text: binding(\.model), prompt: Text(modelPlaceholder))
                    .textInputSuggestions(provider.suggestedModels, id: \.self) { Text($0).textInputCompletion($0) }
                if provider.isCommandLine {
                    Picker("Reasoning effort", selection: binding(\.effort)) {
                        ForEach(ReasoningEffort.allCases) { Text($0.title).tag($0) }
                    }
                }
                if provider == .claudeCode {
                    Toggle(isOn: binding(\.allowsWebSearch)) {
                        Text("Allow web search")
                        Text("Lets Claude search and read web pages for current information. Answers take longer.")
                    }
                }
            } footer: {
                if let portal = provider.keyPortal {
                    Link(provider.keyPolicy == .none ? "Install \(provider.name)" : "Get an API key", destination: portal)
                }
            }

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
                Section {
                    Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
                    Toggle("Download and install updates automatically", isOn: $updater.downloadsAutomatically)
                        .disabled(!updater.checksAutomatically)
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
    let updater: Updater

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
        }
        .formStyle(.grouped)
    }
}

extension Bundle {
    var shortVersion: String { object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    var buildNumber: String { object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
}
