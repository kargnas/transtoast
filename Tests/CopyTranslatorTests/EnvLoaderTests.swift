import CopyTranslatorCore
import Testing

@Test func parsesDotEnvLines() {
    #expect(EnvLoader.parseLine("OPENROUTER_API_KEY=abc")?.key == "OPENROUTER_API_KEY")
    #expect(EnvLoader.parseLine("OPENROUTER_API_KEY=abc")?.value == "abc")
    #expect(EnvLoader.parseLine("export HF_TOKEN='secret'")?.value == "secret")
    #expect(EnvLoader.parseLine("# ignored") == nil)
}
