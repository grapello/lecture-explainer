//
//  SettingsView.swift
//  Lexia
//

import SwiftUI

/// The API key, model choice, and a "test connection" request that streams a
/// short answer: a way to check the key and see streaming work before
/// whole lectures are sent (roadmap step 6).
struct SettingsView: View {
    // @AppStorage reads and writes UserDefaults. Fine for preferences like these;
    // the API key itself goes to the Keychain (see KeychainStore for why).
    @AppStorage("claudeModel") private var model = ClaudeModel.opus
    @AppStorage("claudeEffort") private var effort = ClaudeEffort.high

    @State private var savedKey = KeychainStore.read()
    @State private var keyInput = ""
    @State private var keyError: String?

    @State private var testPrompt = "In two sentences: what does a wave function describe?"
    @State private var testOutput = ""
    @State private var testError: String?
    // The running request. Cancelling this Task is how Stop works.
    @State private var testTask: Task<Void, Never>?

    var body: some View {
        Form {
            apiKeySection

            Section {
                Picker("Model", selection: $model) {
                    ForEach(ClaudeModel.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Effort", selection: $effort) {
                    ForEach(ClaudeEffort.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
            } header: {
                Text("Model")
            } footer: {
                Text("Effort sets how much Claude thinks before answering. Higher is better for derivations but slower and uses more tokens.")
            }

            testSection
        }
        .navigationTitle("Settings")
        .onDisappear { testTask?.cancel() }
    }

    // MARK: - API key

    @ViewBuilder private var apiKeySection: some View {
        Section {
            if let savedKey {
                // Show only the end of the key, enough to recognise which one it is.
                LabeledContent("Saved key", value: "…" + savedKey.suffix(4))
                Button("Remove Key", role: .destructive) {
                    try? KeychainStore.delete()
                    self.savedKey = nil
                }
            } else {
                SecureField("sk-ant-…", text: $keyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save Key") { saveKey() }
                    .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let keyError {
                Text(keyError).foregroundStyle(.red)
            }
        } header: {
            Text("Anthropic API Key")
        } footer: {
            Text("Create a key in the Anthropic Console (console.anthropic.com). It is stored in this iPhone's Keychain only and is sent nowhere except to the Anthropic API. API use is billed to your Anthropic account, separately from a Claude subscription.")
        }
    }

    private func saveKey() {
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try KeychainStore.save(key)
            savedKey = key
            keyInput = ""
            keyError = nil
        } catch {
            keyError = error.localizedDescription
        }
    }

    // MARK: - Test request

    @ViewBuilder private var testSection: some View {
        Section {
            TextField("Prompt", text: $testPrompt, axis: .vertical)
            if savedKey == nil {
                // A greyed-out button is easy to miss on iOS; say why it isn't there.
                Text("Save an API key above to send a test request.")
                    .foregroundStyle(.secondary)
            } else if testTask == nil {
                Button("Send Test Request", systemImage: "paperplane") { runTest() }
                    .disabled(testPrompt.isEmpty)
            } else {
                Button("Stop", systemImage: "stop.circle", role: .destructive) { testTask?.cancel() }
            }
            if testTask != nil && testOutput.isEmpty {
                // Opus 5.5 thinks before it writes; the first words can take a few seconds.
                HStack {
                    ProgressView()
                    Text("Thinking…").foregroundStyle(.secondary)
                }
            }
            if !testOutput.isEmpty {
                Text(testOutput)
                    .textSelection(.enabled)
            }
            if let testError {
                Text(testError).foregroundStyle(.red)
            }
        } header: {
            Text("Test Connection")
        } footer: {
            Text("Sends one short request with your key and shows the answer as it streams in. Uses a few hundred tokens.")
        }
    }

    private func runTest() {
        testOutput = ""
        testError = nil
        let request = ClaudeRequest(model: model, effort: effort,
                                    system: "Answer briefly and clearly.",
                                    userText: testPrompt, maxTokens: 4_000)
        testTask = Task {
            do {
                let client = try ClaudeClient.fromKeychain()
                // Each piece is appended as it arrives, so the text grows on screen.
                for try await piece in client.stream(request) {
                    testOutput += piece
                }
            } catch is CancellationError {
                testError = "Stopped."
            } catch {
                testError = error.localizedDescription
            }
            testTask = nil
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
