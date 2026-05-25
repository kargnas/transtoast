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
            #expect(body["model"] as? String == "openrouter/vision-model")

            let messages = try #require(body["messages"] as? [[String: Any]])
            let userMessage = try #require(messages.last)
            let content = try #require(userMessage["content"] as? [[String: Any]])
            #expect(content.contains { $0["type"] as? String == "image_url" })

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

private func openRouterResponse(_ translation: String) -> Data {
    let escaped = translation.replacingOccurrences(of: "\"", with: "\\\"")
    return Data("""
    {
      "choices": [
        {
          "message": {
            "content": "{\\"translation\\":\\"\(escaped)\\"}"
          }
        }
      ],
      "usage": {
        "prompt_tokens": 11,
        "completion_tokens": 7,
        "total_tokens": 18
      }
    }
    """.utf8)
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
