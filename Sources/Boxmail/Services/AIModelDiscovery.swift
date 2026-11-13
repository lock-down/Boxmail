import BoxmailCore

@MainActor enum AIModelDiscovery {
  static func fetch(_ provider: AIProvider, apiKey: String) async throws -> [AIModel] {
    let result: ModelsResponse = try await BackendService.shared.request(
      "/ai/models", method: "POST",
      body: [
        "config": [
          "providerId": provider.id, "baseURL": provider.baseURL,
          "apiProtocol": provider.apiProtocol.rawValue, "model": "",
        ], "apiKey": apiKey,
      ])
    return result.catalog
  }
}
