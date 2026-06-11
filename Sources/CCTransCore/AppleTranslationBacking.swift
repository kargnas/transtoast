import Foundation

/// Performs a translation through Apple's Translation framework.
///
/// Lives behind a protocol because `TranslationSession` can only be obtained
/// via SwiftUI's `.translationTask` modifier, which needs a hosted view inside
/// the running app — something this platform-light core target must not know
/// about. The CCTrans shell registers its implementation when constructing
/// `TranslationService`; headless contexts (one-shot CLI paths, tests) pass
/// nothing and get a clear error instead of a hang.
public protocol AppleTranslationBacking: Sendable {
    /// - Parameters:
    ///   - sourceLanguageCode: BCP-47 code, or nil to let Apple detect.
    ///   - targetLanguageCode: BCP-47 code; never nil because the resolver
    ///     always produces a concrete target.
    func translate(text: String, sourceLanguageCode: String?, targetLanguageCode: String) async throws -> String
}
