import Foundation

public struct ArchiveDocument: Codable, Hashable {
  public var hash, status: String
  public var totalFiles, omitted: Int
  public var entries: [ArchiveEntry]
  public var summary: ArchiveSummary?
  public var understoodCount: Int { entries.filter { $0.status == "completed" }.count }
}
public struct ArchiveEntry: Codable, Hashable, Identifiable {
  public var id, path, name, contentType, status: String
  public var size: Int
  public var error, analysis: String?
  public var canPreview: Bool { status != "unsupported" }
  public var statusTitle: String {
    switch status {
    case "completed": return "已理解"
    case "running": return "理解中"
    case "failed": return "未完成"
    case "unsupported": return "未处理"
    default: return "待理解"
    }
  }
}
public struct ArchiveSummary: Codable, Hashable {
  public var overview: String
  public var groups: [ArchiveGroup]
  public var findings, actions: [ArchiveFinding]
}
public struct ArchiveGroup: Codable, Hashable {
  public var title: String
  public var entryIds: [String]
}
public struct ArchiveFinding: Codable, Hashable {
  public var text: String
  public var entryIds: [String]
}
