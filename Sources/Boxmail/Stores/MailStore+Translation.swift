import BoxmailCore
import Foundation

struct MailTranslationPreference: Codable, Equatable {
  var auto = false
  var language: MailTranslationLanguage = .simplified
}

struct MailTranslationKey: Hashable {
  let messageId: String
  let language: MailTranslationLanguage
}

struct MailTranslationReading {
  let messageId: String
  var shown: MailTranslationLanguage?
  var explicitlyOriginal = false
  var checkedTarget: MailTranslationLanguage?
}

extension MailStore {
  func translationPreference(for message: MailMessage) -> MailTranslationPreference {
    translationPreferences[message.accountId] ?? .init()
  }

  func prepareTranslation(_ message: MailMessage, automatic: Bool = true) async {
    guard selectedMessageId == message.id, message.bodyLoaded != false, message.draftId == nil else { return }
    if translationReading?.messageId != message.id { translationReading = .init(messageId: message.id) }
    if translationPreferences[message.accountId] == nil {
      let revision = restoreRevision
      do {
        var url = URLComponents()
        url.path = "/translation/preferences"
        url.queryItems = [URLQueryItem(name: "accountId", value: message.accountId)]
        let preference: MailTranslationPreference = try await backend.request(url.string ?? url.path)
        guard !Task.isCancelled, revision == restoreRevision else { return }
        if translationPreferences[message.accountId] == nil { translationPreferences[message.accountId] = preference }
      } catch { return }
    }
    if !Task.isCancelled, automatic { applyAutomaticTranslation(message) }
  }

  private func applyAutomaticTranslation(_ message: MailMessage) {
    let preference = translationPreference(for: message)
    guard selectedMessageId == message.id, !showSettings, composer == nil, previewAttachment == nil,
      translationReading?.messageId == message.id,
      translationReading?.shown == nil, translationReading?.explicitlyOriginal == false, preference.auto,
      translationReading?.checkedTarget != preference.language else { return }
    translationReading?.checkedTarget = preference.language
    if translationResult(message, language: preference.language) != nil
      || settings.ai.enabled && preference.language.detectsDifferentLanguage(in: message.body) {
      showTranslation(message, language: preference.language, automatic: true)
    }
  }

  func changeTranslationPreference(_ message: MailMessage, auto: Bool? = nil, language: MailTranslationLanguage? = nil) {
    var body: [String: Any] = ["accountId": message.accountId]
    if let auto { body["auto"] = auto }
    if let language { body["language"] = language.rawValue }
    let revision = restoreRevision
    Task {
      do {
        let saved: MailTranslationPreference = try await backend.request("/translation/preferences", method: "POST", body: body)
        guard revision == restoreRevision else { return }
        translationPreferences[message.accountId] = saved
        guard let current = selectedMessage, current.accountId == message.accountId,
          translationReading?.messageId == current.id else { return }
        if language != nil, translationReading?.shown != nil {
          showTranslation(current, language: saved.language, automatic: false)
        } else if auto == true || language != nil {
          translationReading?.checkedTarget = nil
          applyAutomaticTranslation(current)
        }
      } catch {
        guard revision == restoreRevision else { return }
        translationErrors[translationKey(for: message)] = error.localizedDescription
      }
    }
  }

  func translationKey(for message: MailMessage) -> MailTranslationKey {
    .init(messageId: message.id, language: translationPreference(for: message).language)
  }

  func isShowingTranslation(_ message: MailMessage) -> Bool {
    translationReading?.messageId == message.id && translationReading?.shown == translationPreference(for: message).language
  }

  func toggleTranslation(_ message: MailMessage) {
    guard message.bodyLoaded != false else { return }
    if translationPreferences[message.accountId] == nil {
      Task {
        await prepareTranslation(message, automatic: false)
        if selectedMessageId == message.id { toggleLoadedTranslation(message) }
      }
    } else { toggleLoadedTranslation(message) }
  }

  private func toggleLoadedTranslation(_ message: MailMessage) {
    let current = detailCache[message.id] ?? message
    if translationReading?.messageId != current.id { translationReading = .init(messageId: current.id) }
    if isShowingTranslation(current), translationErrors[translationKey(for: current)] == nil {
      translationReading?.shown = nil
      translationReading?.explicitlyOriginal = true
    } else {
      showTranslation(current, language: translationPreference(for: current).language, automatic: false)
    }
  }

  private func showTranslation(_ message: MailMessage, language: MailTranslationLanguage, automatic: Bool) {
    let key = MailTranslationKey(messageId: message.id, language: language)
    translationReading?.explicitlyOriginal = false
    translationErrors[key] = nil
    if translationResult(message, language: language) != nil {
      translationReading?.shown = language
      return
    }
    guard settings.ai.enabled, !settings.ai.model.isEmpty else {
      if !automatic { settingsTab = "AI"; showSettings = true }
      return
    }
    translationReading?.shown = language
    guard translationRequests.insert(key).inserted else { return }
    watchAIOutput()
    let revision = restoreRevision
    Task {
      defer { if revision == restoreRevision { translationRequests.remove(key) } }
      if automatic && selectedMessageId != message.id { return }
      do {
        let apiKey = try CredentialService.read(settings.ai.credentialAccount)
        var job: AgentJob = try await backend.request("/translation", method: "POST",
          body: ["accountId": message.accountId, "messageId": message.id, "targetLanguage": language.rawValue,
            "auto": automatic, "providerId": settings.ai.providerId, "apiKey": apiKey], timeout: 15)
        while job.status == "running", revision == restoreRevision {
          try await Task.sleep(for: .seconds(1))
          job = try await backend.request("/jobs/\(job.id)", timeout: 30)
        }
        guard revision == restoreRevision else { return }
        guard job.status == "completed", let text = job.result?.text else {
          throw backend.failure(job.error ?? "翻译未完成，请重试。")
        }
        translationResults[key] = .init(text: text, html: job.result?.html)
      } catch {
        guard revision == restoreRevision else { return }
        translationErrors[key] = error.localizedDescription
        if translationReading?.messageId == message.id, translationReading?.shown == language {
          translationReading?.shown = nil
          if !automatic && CredentialService.isCredentialError(error) {
            settingsTab = "AI"; showSettings = true
          }
        }
      }
    }
  }

  func translationOutput(for message: MailMessage) -> AIStreamOutput? {
    let key = translationKey(for: message)
    return aiOutputs.values.first { $0.task == "translate" && $0.messageId == key.messageId
      && $0.targetLanguage == key.language.rawValue && $0.status == "running" }
  }

  func translationResult(_ message: MailMessage, language: MailTranslationLanguage) -> MailTranslationResult? {
    let key = MailTranslationKey(messageId: message.id, language: language)
    if let result = translationResults[key] ?? message.translations?[language.rawValue] { return result }
    if language == .simplified, let text = message.translation {
      return .init(text: text, html: message.translationHTML)
    }
    return nil
  }

  func translatedMessage(_ message: MailMessage) -> MailMessage {
    guard isShowingTranslation(message) else { return message }
    let language = translationPreference(for: message).language
    guard let result = translationResult(message, language: language) else { return message }
    var value = message
    value.body = result.text
    value.html = result.html
    return value
  }
}
