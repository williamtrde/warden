import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Creates the on-device client when the running system supports it.
public enum OnDeviceModel {
    public static func makeClient() -> LanguageModelClient? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let client = FoundationModelsClient()
            return client.isAvailable ? client : nil
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct GeneratedExplanation {
    @Guide(description: "One plain sentence saying what changed in the file.")
    var whatChanged: String
    @Guide(description: "One plain sentence saying what this concretely changes for the person, naming their projects.")
    var impact: String
}

/// Runs Apple's on-device model. Nothing here touches the network.
@available(macOS 26.0, *)
struct FoundationModelsClient: LanguageModelClient {
    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    func draft(instructions: String, prompt: String) async throws -> ModelDraft {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt, generating: GeneratedExplanation.self)
        return ModelDraft(whatChanged: response.content.whatChanged, impact: response.content.impact)
    }
}
#endif
