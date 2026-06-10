import TransToastCore
import Foundation

struct CredentialsProvider {
    func credentials() -> TranslatorCredentials {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let bundleURL = Bundle.main.bundleURL
        // `open TransToast.app` does not preserve the project root as cwd, so dev builds also
        // check paths around the app bundle before falling back to the user config file.
        let paths = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env.local"),
            bundleURL.deletingLastPathComponent().appendingPathComponent(".env.local"),
            bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".env.local"),
            home.appendingPathComponent(".config/transtoast/.env"),
        ]
        let environment = EnvLoader.mergedEnvironment(dotenv: EnvLoader.load(paths: paths))
        return TranslatorCredentials(
            openRouterAPIKey: environment["OPENROUTER_API_KEY"],
            huggingFaceToken: environment["HF_TOKEN"]
        )
    }
}
