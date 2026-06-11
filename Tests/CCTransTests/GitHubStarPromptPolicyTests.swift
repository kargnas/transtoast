import CCTransCore
import Foundation
import Testing

@Test func macAppStoreReceiptWinsOverEveryOtherSignal() {
    // A MAS build also has an .app suffix and no workspace root, so the
    // receipt/sandbox signals must take precedence.
    #expect(GitHubStarPromptPolicy.channel(
        bundlePathHasAppSuffix: true,
        hasMacAppStoreReceipt: true,
        isAppSandboxed: false,
        hasWorkspaceRoot: false
    ) == .macAppStore)
    #expect(GitHubStarPromptPolicy.channel(
        bundlePathHasAppSuffix: true,
        hasMacAppStoreReceipt: false,
        isAppSandboxed: true,
        hasWorkspaceRoot: true
    ) == .macAppStore)
}

@Test func workspaceOrBareBinaryRunsAreDevWorkspace() {
    // run-dev.zsh launches the bundle with --workspace-root inside the repo.
    #expect(GitHubStarPromptPolicy.channel(
        bundlePathHasAppSuffix: true,
        hasMacAppStoreReceipt: false,
        isAppSandboxed: false,
        hasWorkspaceRoot: true
    ) == .devWorkspace)
    // Bare SwiftPM debug binary outside an .app bundle.
    #expect(GitHubStarPromptPolicy.channel(
        bundlePathHasAppSuffix: false,
        hasMacAppStoreReceipt: false,
        isAppSandboxed: false,
        hasWorkspaceRoot: false
    ) == .devWorkspace)
}

@Test func brewAndDMGInstallsAreStandalone() {
    // Brew cask and the GitHub DMG both land a plain .app in /Applications:
    // no receipt, no sandbox, no resolvable workspace root.
    #expect(GitHubStarPromptPolicy.channel(
        bundlePathHasAppSuffix: true,
        hasMacAppStoreReceipt: false,
        isAppSandboxed: false,
        hasWorkspaceRoot: false
    ) == .standalone)
}

@Test func promptsOnlyOnStandaloneUnhandledAfterSetup() {
    #expect(GitHubStarPromptPolicy.shouldPrompt(
        channel: .standalone,
        alreadyHandled: false,
        hasCompletedInitialSetup: true
    ))

    // install-app.zsh (clone channel) marks handled via `defaults write`.
    #expect(!GitHubStarPromptPolicy.shouldPrompt(
        channel: .standalone,
        alreadyHandled: true,
        hasCompletedInitialSetup: true
    ))
    // First launch is owned by the local-model setup window.
    #expect(!GitHubStarPromptPolicy.shouldPrompt(
        channel: .standalone,
        alreadyHandled: false,
        hasCompletedInitialSetup: false
    ))
    #expect(!GitHubStarPromptPolicy.shouldPrompt(
        channel: .macAppStore,
        alreadyHandled: false,
        hasCompletedInitialSetup: true
    ))
    #expect(!GitHubStarPromptPolicy.shouldPrompt(
        channel: .devWorkspace,
        alreadyHandled: false,
        hasCompletedInitialSetup: true
    ))
}
