import CopyTranslatorCore
import Foundation
import Testing

@Suite(.serialized)
struct OpenRouterScreenContextTests {
    @Test func openRouterTextUsesVisionModelWhenScreenContextIsProvided() async throws {
        let settings = TranslatorSettings(
            provider: .openRouter,
            openRouterTextModel: "openrouter/text-model",
            openRouterVisionModel: "openrouter/vision-model"
        )
        let service = TranslationService(session: stubbedOpenRouterSession { request in
            let body = try #require(request.jsonBody)
            #expect(body["model"] == nil)
            let models = try #require(body["models"] as? [String])
            #expect(models.first == "openrouter/vision-model")
            #expect(models.contains("~google/gemini-flash-latest"))
            #expect(models.contains("nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free"))

            let provider = try #require(body["provider"] as? [String: Any])
            let sort = try #require(provider["sort"] as? [String: Any])
            #expect(sort["by"] as? String == "throughput")
            #expect(sort["partition"] as? String == "none")

            let messages = try #require(body["messages"] as? [[String: Any]])
            let userMessage = try #require(messages.last)
            let content = try #require(userMessage["content"] as? [[String: Any]])
            #expect(content.contains { $0["type"] as? String == "image_url" })
            let image = try #require(content.first { $0["type"] as? String == "image_url" })
            let imageURL = try #require(image["image_url"] as? [String: Any])
            #expect(imageURL["detail"] as? String == "low")
            let prompt = try #require(content.compactMap { $0["text"] as? String }.first)
            #expect(prompt.contains("Do not translate the full sentence visible in the screen image."))
            #expect(prompt.contains("Translate exactly the text inside <selected_text>."))

            let responseFormat = try #require(body["response_format"] as? [String: Any])
            let jsonSchema = try #require(responseFormat["json_schema"] as? [String: Any])
            let schema = try #require(jsonSchema["schema"] as? [String: Any])
            let properties = try #require(schema["properties"] as? [String: Any])
            #expect(properties.keys.contains("description"))

            return openRouterResponse("화면 컨텍스트 번역")
        })

        let result = try await service.translateText(
            "Translate this.",
            settings: settings,
            credentials: TranslatorCredentials(openRouterAPIKey: "test-key", huggingFaceToken: nil),
            contextImagePNGData: Data([0x89, 0x50, 0x4E, 0x47])
        )

        #expect(result.text == "화면 컨텍스트 번역")
        #expect(result.model == "openrouter/vision-model")
        #expect(result.usage?.promptTokens == 11)
        #expect(result.usage?.completionTokens == 7)
        #expect(result.usage?.totalTokens == 18)
        #expect(result.usage?.costCredits == 0.000123)
    }

    @Test func openRouterTextParsesContextDescriptionSeparately() async throws {
        let settings = TranslatorSettings(
            provider: .openRouter,
            openRouterTextModel: "openrouter/text-model",
            openRouterVisionModel: "openrouter/vision-model"
        )
        let service = TranslationService(session: stubbedOpenRouterSession { request in
            let body = try #require(request.jsonBody)
            let messages = try #require(body["messages"] as? [[String: Any]])
            let userMessage = try #require(messages.last)
            let content = try #require(userMessage["content"] as? [[String: Any]])
            let prompt = try #require(content.compactMap { $0["text"] as? String }.first)
            #expect(prompt.contains("translate the pronoun \"it\" literally as \"그것\""))
            #expect(prompt.contains("Treat the text inside <selected_text> as the only source text."))
            #expect(prompt.contains("Write every returned string value in Korean"))
            #expect(!prompt.contains("Copy this brand new sentence twice to translate it."))
            return openRouterResponse(
                "그것",
                description: "이 문장에서 '그것'은 복사하려는 문장 전체를 의미합니다."
            )
        })

        let result = try await service.translateText(
            "it",
            settings: settings,
            credentials: TranslatorCredentials(openRouterAPIKey: "test-key", huggingFaceToken: nil),
            contextImagePNGData: Data([0x89, 0x50, 0x4E, 0x47])
        )

        #expect(result.text == "그것")
        #expect(result.description == "이 문장에서 '그것'은 복사하려는 문장 전체를 의미합니다.")
    }

    @Test func openRouterTextUsesTextModelWhenNoScreenContextExists() async throws {
        let settings = TranslatorSettings(
            provider: .openRouter,
            openRouterTextModel: "openrouter/text-model",
            openRouterVisionModel: "openrouter/vision-model"
        )
        let service = TranslationService(session: stubbedOpenRouterSession { request in
            let body = try #require(request.jsonBody)
            #expect(body["model"] as? String == "openrouter/text-model")

            let messages = try #require(body["messages"] as? [[String: Any]])
            let userMessage = try #require(messages.last)
            #expect(userMessage["content"] is String)

            return openRouterResponse("텍스트 번역")
        })

        let result = try await service.translateText(
            "Translate this.",
            settings: settings,
            credentials: TranslatorCredentials(openRouterAPIKey: "test-key", huggingFaceToken: nil)
        )

        #expect(result.text == "텍스트 번역")
        #expect(result.model == "openrouter/text-model")
    }
}

private func stubbedOpenRouterSession(
    handler: @escaping @Sendable (URLRequest) throws -> Data
) -> URLSession {
    OpenRouterStubURLProtocol.handler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OpenRouterStubURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func openRouterResponse(_ translation: String, description: String? = nil) -> Data {
    let contentObject: [String: Any] = [
        "translation": translation,
        "description": description ?? NSNull(),
    ]
    let contentData = try! JSONSerialization.data(withJSONObject: contentObject)
    let content = String(data: contentData, encoding: .utf8)!
    let payload: [String: Any] = [
        "choices": [
            [
                "message": [
                    "content": content,
                ],
            ],
        ],
        "usage": [
            "prompt_tokens": 11,
            "completion_tokens": 7,
            "total_tokens": 18,
            "cost": 0.000123,
        ],
    ]
    return try! JSONSerialization.data(withJSONObject: payload)
}

private final class OpenRouterStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> Data)?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "openrouter.ai"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let data = try Self.handler?(request) ?? Data()
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    var jsonBody: [String: Any]? {
        let bodyData: Data?
        if let httpBody {
            bodyData = httpBody
        } else if let httpBodyStream {
            httpBodyStream.open()
            defer {
                httpBodyStream.close()
            }

            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while httpBodyStream.hasBytesAvailable {
                let count = httpBodyStream.read(&buffer, maxLength: buffer.count)
                if count <= 0 {
                    break
                }
                data.append(buffer, count: count)
            }
            bodyData = data
        } else {
            bodyData = nil
        }

        guard let bodyData else {
            return nil
        }

        return (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any]
    }
}
