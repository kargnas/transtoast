import Foundation

/// Decides whether the app may ask the user to star the GitHub repo, per
/// distribution-channel policy. Kept platform-light and side-effect free so the
/// rules are unit-testable; the CCTrans shell gathers the platform facts.
public enum GitHubStarPromptPolicy {
    public enum InstallChannel: Equatable, Sendable {
        /// Mac App Store build. Sandboxed, so spawning the user's `gh` CLI cannot
        /// reach its config/keychain, and App Review treats out-of-StoreKit
        /// rating/engagement prompts as a rejection risk. Never prompts.
        case macAppStore
        /// Cloned repo: dev runs (run-dev.zsh, bare SwiftPM binary) or any launch
        /// that can resolve the workspace root. scripts/install-app.zsh already
        /// asks in the terminal at install time, so the app stays silent here.
        case devWorkspace
        /// Brew cask, GitHub DMG download, or a local install-app.zsh copy in
        /// /Applications. Homebrew only forbids interactivity during `brew
        /// install`; a runtime prompt inside the app is the app's own UX, so this
        /// channel may ask (once).
        case standalone
    }

    public static func channel(
        bundlePathHasAppSuffix: Bool,
        hasMacAppStoreReceipt: Bool,
        isAppSandboxed: Bool,
        hasWorkspaceRoot: Bool
    ) -> InstallChannel {
        // MAS detection wins first: an App Store build also has an .app suffix
        // and no workspace root, so the later checks would misread it.
        if hasMacAppStoreReceipt || isAppSandboxed {
            return .macAppStore
        }
        if !bundlePathHasAppSuffix || hasWorkspaceRoot {
            return .devWorkspace
        }
        return .standalone
    }

    public static func shouldPrompt(
        channel: InstallChannel,
        alreadyHandled: Bool,
        hasCompletedInitialSetup: Bool
    ) -> Bool {
        // hasCompletedInitialSetup keeps the prompt off the first launch, where
        // the local-model setup window is already competing for attention.
        channel == .standalone && !alreadyHandled && hasCompletedInitialSetup
    }
}
