import Foundation

public struct TranslationResult: Equatable, Sendable {
    public let text: String
    public let providerTitle: String
    public let model: String
    public let usage: TranslationUsage?

    public init(text: String, providerTitle: String, model: String, usage: TranslationUsage? = nil) {
        self.text = text
        self.providerTitle = providerTitle
        self.model = model
        self.usage = usage
    }
}

public struct TranslationUsage: Equatable, Sendable {
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let totalTokens: Int?

    public init(promptTokens: Int?, completionTokens: Int?, totalTokens: Int?) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }
}

public enum TranslationError: LocalizedError, Sendable {
    case emptyInput
    case missingCredential(String)
    case invalidURL(String)
    case invalidHTTPStatus(Int, String)
    case missingTranslation(String)
    case invalidImageData
    case localModelUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            "There is no text to translate."
        case let .missingCredential(name):
            "Missing \(name). Add it to .env.local or ~/.config/copy-translator/.env."
        case let .invalidURL(url):
            "Invalid URL: \(url)"
        case let .invalidHTTPStatus(status, body):
            "Request failed with HTTP \(status): \(body)"
        case let .missingTranslation(body):
            "The model response did not contain a translation: \(body)"
        case .invalidImageData:
            "The screenshot could not be encoded."
        case let .localModelUnavailable(message):
            message
        }
    }
}

public final class TranslationService: @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func translateText(
        _ text: String,
        settings: TranslatorSettings,
        credentials: TranslatorCredentials,
        contextImagePNGData: Data? = nil
    ) async throws -> TranslationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationError.emptyInput
        }

        switch settings.provider {
        case .localHyMT2:
            return try await translateWithLocalHyMT2(
                text: trimmed,
                settings: settings,
                credentials: credentials
            )
        case .openRouter:
            return try await translateWithOpenRouterText(
                text: trimmed,
                settings: settings,
                credentials: credentials,
                contextImagePNGData: contextImagePNGData
            )
        }
    }

    public func translateImage(
        pngData: Data,
        settings: TranslatorSettings,
        credentials: TranslatorCredentials
    ) async throws -> TranslationResult {
        guard !pngData.isEmpty else {
            throw TranslationError.invalidImageData
        }

        let key = try require(credentials.openRouterAPIKey, named: "OPENROUTER_API_KEY")
        let prompt = """
        Extract every visible piece of text in this screenshot and translate it into \(settings.targetLanguage).
        Return only the translation. Preserve line breaks when they help readability.
        """

        let body: [String: Any] = [
            "model": settings.openRouterVisionModel,
            "messages": [
                [
                    "role": "system",
                    "content": "You are a precise screenshot translation engine. Return only translated text.",
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": prompt,
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/png;base64,\(pngData.base64EncodedString())",
                            ],
                        ],
                    ],
                ],
            ],
            "max_tokens": maxTokens(for: settings.openRouterVisionModel),
            "temperature": 0.1,
            "response_format": translationSchema,
        ]

        let response = try await postOpenRouter(body: body, apiKey: key)
        return TranslationResult(
            text: response.translation,
            providerTitle: TranslationProvider.openRouter.title,
            model: settings.openRouterVisionModel,
            usage: response.usage
        )
    }

    private func translateWithLocalHyMT2(
        text: String,
        settings: TranslatorSettings,
        credentials: TranslatorCredentials
    ) async throws -> TranslationResult {
        let prompt = """
        Translate the following text into \(settings.targetLanguage). Note that you should only output the translated result without any additional explanation:

        \(text)
        """

        do {
            let response = try await runLocalHyMT2Backend(
                prompt: prompt,
                sourceText: text,
                settings: settings,
                credentials: credentials
            )
            return TranslationResult(
                text: response,
                providerTitle: settings.provider.title,
                model: settings.hyMT2Model.rawValue
            )
        } catch {
            throw TranslationError.localModelUnavailable("""
            Local Hy-MT2 backend failed: \(error.localizedDescription)
            """)
        }
    }

    private func translateWithOpenRouterText(
        text: String,
        settings: TranslatorSettings,
        credentials: TranslatorCredentials,
        contextImagePNGData: Data?
    ) async throws -> TranslationResult {
        let key = try require(credentials.openRouterAPIKey, named: "OPENROUTER_API_KEY")
        let model = contextImagePNGData == nil
            ? settings.openRouterTextModel
            : settings.openRouterVisionModel
        let prompt = """
        Translate the following selected or copied text into \(settings.targetLanguage). Return only the translated result.

        If a screen image is attached, use it only as visual context for nearby UI labels, product names, sentence boundaries, and ambiguous short text.

        Text:
        \(text)
        """
        let userContent: Any
        if let contextImagePNGData {
            userContent = [
                [
                    "type": "text",
                    "text": prompt,
                ],
                [
                    "type": "image_url",
                    "image_url": [
                        "url": "data:image/png;base64,\(contextImagePNGData.base64EncodedString())",
                    ],
                ],
            ] as [[String: Any]]
        } else {
            userContent = prompt
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": "You are a precise translation engine. Return only translated text.",
                ],
                [
                    "role": "user",
                    "content": userContent,
                ],
            ],
            "max_tokens": maxTokens(for: model),
            "temperature": 0.1,
            "response_format": translationSchema,
        ]

        let response = try await postOpenRouter(body: body, apiKey: key)
        return TranslationResult(
            text: response.translation,
            providerTitle: settings.provider.title,
            model: model,
            usage: response.usage
        )
    }

    private func runLocalHyMT2Backend(
        prompt: String,
        sourceText: String,
        settings: TranslatorSettings,
        credentials: TranslatorCredentials
    ) async throws -> String {
        let backendPath = try resolveLocalBackendPath(settings: settings)
        let payload: [String: Any] = [
            "text": sourceText,
            "prompt": prompt,
            "target_language": settings.targetLanguage,
            "model_id": settings.hyMT2Model.rawValue,
            "hf_token": credentials.huggingFaceToken ?? "",
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payload)

        let outputData = try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["uv", "run", backendPath]

            var environment = ProcessInfo.processInfo.environment
            if let token = credentials.huggingFaceToken {
                environment["HF_TOKEN"] = token
            }
            process.environment = environment

            let input = Pipe()
            let output = Pipe()
            let error = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = error

            try process.run()
            input.fileHandleForWriting.write(payloadData)
            try input.fileHandleForWriting.close()
            process.waitUntilExit()

            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = error.fileHandleForReading.readDataToEndOfFile()

            guard process.terminationStatus == 0 else {
                let stdout = String(data: data, encoding: .utf8) ?? ""
                let stderr = String(data: errorData, encoding: .utf8) ?? ""
                throw TranslationError.localModelUnavailable((stdout + "\n" + stderr).trimmingCharacters(in: .whitespacesAndNewlines))
            }

            return data
        }.value

        let object = try JSONSerialization.jsonObject(with: outputData)
        guard let dictionary = object as? [String: Any] else {
            throw TranslationError.missingTranslation(String(data: outputData, encoding: .utf8) ?? "")
        }

        if let translation = dictionary["translation"] as? String {
            return clean(translation)
        }

        if let error = dictionary["error"] as? String {
            throw TranslationError.localModelUnavailable(error)
        }

        throw TranslationError.missingTranslation(String(data: outputData, encoding: .utf8) ?? "")
    }

    private func resolveLocalBackendPath(settings: TranslatorSettings) throws -> String {
        let explicit = settings.localHyMT2BackendPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicit, !explicit.isEmpty {
            return explicit
        }

        if let environmentPath = ProcessInfo.processInfo.environment["COPY_TRANSLATOR_HYMT2_BACKEND"],
           !environmentPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return environmentPath
        }

        let candidates: [String] = [
            Bundle.main.resourceURL?.appendingPathComponent("hy_mt2_translate.py").path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("scripts/hy_mt2_translate.py").path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Scripts/hy_mt2_translate.py").path,
        ].compactMap { $0 }

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }

        throw TranslationError.localModelUnavailable("Could not find scripts/hy_mt2_translate.py or bundled hy_mt2_translate.py.")
    }

    private func postOpenRouter(body: [String: Any], apiKey: String) async throws -> OpenRouterCompletion {
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
            throw TranslationError.invalidURL("https://openrouter.ai/api/v1/chat/completions")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://kargn.as", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Sangrak", forHTTPHeaderField: "X-OpenRouter-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(request)
        return try extractOpenRouterCompletion(from: data)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.missingTranslation(String(data: data, encoding: .utf8) ?? "")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranslationError.invalidHTTPStatus(httpResponse.statusCode, body)
        }

        return data
    }

    private func extractOpenRouterCompletion(from data: Data) throws -> OpenRouterCompletion {
        let object = try JSONSerialization.jsonObject(with: data)
        guard
            let dictionary = object as? [String: Any],
            let choices = dictionary["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw TranslationError.missingTranslation(String(data: data, encoding: .utf8) ?? "")
        }

        let usage = extractOpenRouterUsage(from: dictionary)
        guard let contentData = content.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
              let translation = parsed["translation"] as? String
        else {
            return OpenRouterCompletion(translation: clean(content), usage: usage)
        }

        return OpenRouterCompletion(translation: clean(translation), usage: usage)
    }

    private func extractOpenRouterUsage(from dictionary: [String: Any]) -> TranslationUsage? {
        guard let usage = dictionary["usage"] as? [String: Any] else {
            return nil
        }

        return TranslationUsage(
            promptTokens: tokenCount(from: usage["prompt_tokens"]),
            completionTokens: tokenCount(from: usage["completion_tokens"]),
            totalTokens: tokenCount(from: usage["total_tokens"])
        )
    }

    private func tokenCount(from value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let doubleValue = value as? Double {
            return Int(doubleValue)
        }
        if let stringValue = value as? String {
            return Int(stringValue)
        }
        return nil
    }

    private func require(_ value: String?, named name: String) throws -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.missingCredential(name)
        }
        return value
    }

    private func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func maxTokens(for model: String) -> Int {
        let normalized = model.lowercased()
        if normalized.contains("gemini") {
            return 65_535
        }
        if normalized.contains("claude") || normalized.contains("gpt") || normalized.contains("openai") {
            return 10_000
        }
        return 10_000
    }

    private var translationSchema: [String: Any] {
        [
            "type": "json_schema",
            "json_schema": [
                "name": "translation_result",
                "strict": true,
                "schema": [
                    "type": "object",
                    "properties": [
                        "translation": [
                            "type": "string",
                        ],
                    ],
                    "required": ["translation"],
                    "additionalProperties": false,
                ],
            ],
        ]
    }
}

private struct OpenRouterCompletion {
    let translation: String
    let usage: TranslationUsage?
}
