import Foundation
import Dispatch
import Darwin

public struct TranslationResult: Equatable, Sendable {
    public let text: String
    public let description: String?
    public let providerTitle: String
    public let model: String
    public let usage: TranslationUsage?
    public let sourceLanguage: String?
    public let targetLanguage: String?
    public let detectedSourceLanguage: String?

    public init(
        text: String,
        description: String? = nil,
        providerTitle: String,
        model: String,
        usage: TranslationUsage? = nil,
        sourceLanguage: String? = nil,
        targetLanguage: String? = nil,
        detectedSourceLanguage: String? = nil
    ) {
        self.text = text
        self.description = description?.nilIfBlank
        self.providerTitle = providerTitle
        self.model = model
        self.usage = usage
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.detectedSourceLanguage = detectedSourceLanguage
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
    private let localBackendGate = LocalBackendExecutionGate()

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

        let languages = TranslationLanguageResolver.resolve(
            text: trimmed,
            sourceLanguage: settings.sourceLanguage,
            targetLanguage: settings.targetLanguage
        )

        switch settings.provider {
        case .localHyMT2:
            return try await translateWithLocalModel(
                text: trimmed,
                settings: settings,
                credentials: credentials,
                languages: languages
            )
        case .openRouter:
            return try await translateWithOpenRouterText(
                text: trimmed,
                settings: settings,
                credentials: credentials,
                contextImagePNGData: contextImagePNGData,
                languages: languages
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
        Return JSON with "translation" only containing the translation text and "description" set to null.
        Preserve line breaks when they help readability.
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
            description: response.description,
            providerTitle: TranslationProvider.openRouter.title,
            model: settings.openRouterVisionModel,
            usage: response.usage
        )
    }

    private func translateWithLocalModel(
        text: String,
        settings: TranslatorSettings,
        credentials: TranslatorCredentials,
        languages: ResolvedTranslationLanguages
    ) async throws -> TranslationResult {
        let model = LocalModelRegistry.model(
            id: settings.localModelID,
            customModelsPath: settings.customLocalModelsPath
        ) ?? LocalModelRegistry.defaultModel(customModelsPath: settings.customLocalModelsPath)

        guard model.supports(sourceLanguage: languages.sourceLanguage, targetLanguage: languages.targetLanguage) else {
            throw TranslationError.localModelUnavailable(
                "\(model.title) does not support \(languages.sourceLanguage) -> \(languages.targetLanguage)."
            )
        }

        let prompt = """
        Translate the following \(languages.sourceLanguage) text into \(languages.targetLanguage).
        Only output the translated result without any additional explanation:

        \(text)
        """

        do {
            let response = try await runLocalBackend(
                prompt: prompt,
                sourceText: text,
                settings: settings,
                credentials: credentials,
                languages: languages,
                model: model
            )
            return TranslationResult(
                text: response,
                providerTitle: settings.provider.title,
                model: model.title,
                sourceLanguage: languages.sourceLanguage,
                targetLanguage: languages.targetLanguage,
                detectedSourceLanguage: languages.detectedSourceLanguage
            )
        } catch {
            throw TranslationError.localModelUnavailable("""
            Local backend failed: \(error.localizedDescription)
            """)
        }
    }

    private func translateWithOpenRouterText(
        text: String,
        settings: TranslatorSettings,
        credentials: TranslatorCredentials,
        contextImagePNGData: Data?,
        languages: ResolvedTranslationLanguages
    ) async throws -> TranslationResult {
        let key = try require(credentials.openRouterAPIKey, named: "OPENROUTER_API_KEY")
        let model = contextImagePNGData == nil
            ? settings.openRouterTextModel
            : settings.openRouterVisionModel
        let prompt = openRouterTextPrompt(
            text: text,
            sourceLanguage: languages.sourceLanguage,
            targetLanguage: languages.targetLanguage,
            hasScreenContext: contextImagePNGData != nil
        )
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
                        "detail": "low",
                    ],
                ],
            ] as [[String: Any]]
        } else {
            userContent = prompt
        }

        let providerRouting: [String: Any] = contextImagePNGData == nil
            ? [
                "sort": "throughput",
                "preferred_max_latency": [
                    "p90": 5,
                ],
            ]
            : [
                "sort": [
                    "by": "throughput",
                    "partition": "none",
                ],
                "preferred_max_latency": [
                    "p90": 5,
                ],
            ]

        var body: [String: Any] = [
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
            "provider": providerRouting,
            "response_format": translationSchema,
        ]
        if contextImagePNGData != nil {
            body.removeValue(forKey: "model")
            body["models"] = [
                model,
                "qwen/qwen3-vl-8b-instruct",
                "google/gemini-2.5-flash-lite",
            ].uniqued()
        }

        let response = try await postOpenRouter(body: body, apiKey: key)
        return TranslationResult(
            text: response.translation,
            description: response.description,
            providerTitle: settings.provider.title,
            model: model,
            usage: response.usage,
            sourceLanguage: languages.sourceLanguage,
            targetLanguage: languages.targetLanguage,
            detectedSourceLanguage: languages.detectedSourceLanguage
        )
    }

    private func runLocalBackend(
        prompt: String,
        sourceText: String,
        settings: TranslatorSettings,
        credentials: TranslatorCredentials,
        languages: ResolvedTranslationLanguages,
        model: LocalModelSpec
    ) async throws -> String {
        let backendPath = try resolveLocalBackendPath(settings: settings, model: model)
        let payload: [String: Any] = [
            "text": sourceText,
            "prompt": prompt,
            "source_language": languages.sourceLanguage,
            "target_language": languages.targetLanguage,
            "local_model_id": model.id,
            "model_id": model.modelID,
            "runtime": model.runtime.rawValue,
            "artifact_name": model.artifactName ?? "",
            "hf_token": credentials.huggingFaceToken ?? "",
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let backendGate = localBackendGate
        let processHandle = LocalBackendProcessHandle()

        let outputData = try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try backendGate.waitForTurn(cancelledBy: processHandle)
                defer {
                    backendGate.releaseTurn()
                }
                try processHandle.checkCancellation()

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

                processHandle.set(process)
                defer {
                    processHandle.clear()
                }

                try process.run()
                try processHandle.checkCancellationTerminatingActiveProcess()
                input.fileHandleForWriting.write(payloadData)
                try input.fileHandleForWriting.close()
                process.waitUntilExit()
                try processHandle.checkCancellation()

                let data = output.fileHandleForReading.readDataToEndOfFile()
                let errorData = error.fileHandleForReading.readDataToEndOfFile()

                guard process.terminationStatus == 0 else {
                    let stdout = String(data: data, encoding: .utf8) ?? ""
                    let stderr = String(data: errorData, encoding: .utf8) ?? ""
                    throw TranslationError.localModelUnavailable((stdout + "\n" + stderr).trimmingCharacters(in: .whitespacesAndNewlines))
                }

                return data
            }.value
        } onCancel: {
            processHandle.cancelAndTerminate()
        }

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

    private func resolveLocalBackendPath(settings: TranslatorSettings, model: LocalModelSpec) throws -> String {
        let explicit = settings.localHyMT2BackendPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicit, !explicit.isEmpty {
            return explicit
        }

        if let modelBackendPath = model.customBackendPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !modelBackendPath.isEmpty {
            return modelBackendPath
        }

        if let environmentPath = ProcessInfo.processInfo.environment["COPY_TRANSLATOR_LOCAL_BACKEND"],
           !environmentPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return environmentPath
        }

        if let environmentPath = ProcessInfo.processInfo.environment["COPY_TRANSLATOR_HYMT2_BACKEND"],
           !environmentPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return environmentPath
        }

        guard let scriptName = model.backendScriptName else {
            throw TranslationError.localModelUnavailable("\(model.title) has no bundled backend yet. Add a custom backend path or choose a bundled model.")
        }

        let candidates: [String] = [
            Bundle.main.resourceURL?.appendingPathComponent(scriptName).path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("scripts/\(scriptName)").path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Scripts/\(scriptName)").path,
        ].compactMap { $0 }

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }

        throw TranslationError.localModelUnavailable("Could not find scripts/\(scriptName) or bundled \(scriptName).")
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
            return OpenRouterCompletion(translation: clean(content), description: nil, usage: usage)
        }

        return OpenRouterCompletion(
            translation: clean(translation),
            description: clean(parsed["description"] as? String),
            usage: usage
        )
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

    private func openRouterTextPrompt(
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        hasScreenContext: Bool
    ) -> String {
        let contextInstruction = hasScreenContext
            ? """
            A screen image is attached. Use it only to understand the selected fragment's local sentence, referent, part of speech, tone, casing, UI label, or product name. The image is context, not the translation target.
            """
            : "No screen image is attached."

        return """
        Translate the selected or copied \(sourceLanguage) text into \(targetLanguage).

        Critical rules:
        - Treat the text inside <selected_text> as the only source text. Ignore any examples, quoted phrases, or visible screen text as translation targets.
        - Translate exactly the text inside <selected_text>. Do not translate the full sentence visible in the screen image.
        - If <selected_text> is a word or fragment inside a larger sentence, return only that word or fragment's translation.
        - Use surrounding screen context only to choose the right meaning and to write the optional description.
        - Put only the translated text in "translation". Put contextual details only in "description".
        - Write every returned string value in \(targetLanguage), including "description". Do not write English explanations unless \(targetLanguage) is English.
        - Set "description" to null unless the selected text is ambiguous, pronominal, deictic, or needs screen context to be understood.
        - When a screen image is attached and <selected_text> is a pronoun or deictic word such as "it", "this", "that", or "they", "description" must be a short \(targetLanguage) sentence that explains the referent from the visible context.
        - If the visible context is a sentence and the exact referent is implicit, explain the most likely referent in that sentence instead of returning null.
        - For Korean, translate "twice" as "두번" when it means two times.
        - For Korean, translate the pronoun "it" literally as "그것"; when <selected_text> is exactly "it" and a screen image is attached, "description" must never be null.
        - If <selected_text> is exactly "it" but the attached image does not show a reliable referent, still return "그것" and describe it as the most likely object from the surrounding visible sentence.

        \(contextInstruction)

        <selected_text>
        \(text)
        </selected_text>
        """
    }

    private func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clean(_ text: String?) -> String? {
        text?.nilIfBlank
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
                        "description": [
                            "type": ["string", "null"],
                        ],
                    ],
                    "required": ["translation", "description"],
                    "additionalProperties": false,
                ],
            ],
        ]
    }
}

private struct OpenRouterCompletion {
    let translation: String
    let description: String?
    let usage: TranslationUsage?
}

private final class LocalBackendExecutionGate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 1)

    func waitForTurn(cancelledBy processHandle: LocalBackendProcessHandle) throws {
        while semaphore.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
            try processHandle.checkCancellation()
        }
    }

    func releaseTurn() {
        semaphore.signal()
    }
}

private final class LocalBackendProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var isCancelled = false

    func set(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldTerminate = isCancelled
        lock.unlock()

        if shouldTerminate {
            terminate(process)
        }
    }

    func clear() {
        lock.lock()
        process = nil
        lock.unlock()
    }

    func cancelAndTerminate() {
        lock.lock()
        isCancelled = true
        let runningProcess = process
        lock.unlock()

        guard let runningProcess else {
            return
        }
        terminate(runningProcess)
    }

    func checkCancellation() throws {
        lock.lock()
        let isCancelled = isCancelled
        lock.unlock()

        if isCancelled {
            throw CancellationError()
        }
    }

    func checkCancellationTerminatingActiveProcess() throws {
        lock.lock()
        let isCancelled = isCancelled
        let runningProcess = process
        lock.unlock()

        guard isCancelled else {
            return
        }

        if let runningProcess {
            terminate(runningProcess)
        }
        throw CancellationError()
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else {
            return
        }

        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
            self?.forceKillIfStillRunning(pid: pid)
        }
    }

    private func forceKillIfStillRunning(pid: pid_t) {
        lock.lock()
        let shouldKill = process?.processIdentifier == pid && process?.isRunning == true
        lock.unlock()

        if shouldKill {
            kill(pid, SIGKILL)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
