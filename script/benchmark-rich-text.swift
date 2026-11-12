// Compile alongside RichTextDocument.swift, RichTextStyle.swift and RichTextListLayout.swift with swiftc -O.
import AppKit
import Darwin
import Foundation

@main struct RichTextBenchmark {
  static func main() throws {
    let content = Array(repeating: String(repeating: "正文", count: 49), count: 5000).joined(
      separator: "\n")
    let input = NSAttributedString(
      string: content,
      attributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.systemBlue])
    let storage = NSMutableAttributedString(attributedString: input)
    #if INCREMENTAL
      let projection = RichTextDocumentProjection()
      projection.reset(storage)
    #else
      _ = RichTextCodec.document(storage)
    #endif
    var samples: [[String: Double]] = []
    for _ in 0..<7 {
      var before = rusage()
      var after = rusage()
      getrusage(RUSAGE_SELF, &before)
      let range = NSRange(location: storage.length / 2 - 1, length: 1)
      let start = DispatchTime.now().uptimeNanoseconds
      storage.replaceCharacters(in: range, with: "字")
      #if INCREMENTAL
        let document = projection.update(storage, editedRange: range)
      #else
        let document = RichTextCodec.document(storage)
      #endif
      let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
      getrusage(RUSAGE_SELF, &after)
      precondition(document.blocks.count == 5000)
      func cpu(_ value: rusage) -> Double {
        Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec) * 1000 + Double(
          value.ru_utime.tv_usec + value.ru_stime.tv_usec) / 1000
      }
      samples.append([
        "elapsedMs": elapsed, "cpuMs": cpu(after) - cpu(before),
        "maxRSSBytes": Double(after.ru_maxrss),
      ])
    }
    let output = try JSONSerialization.data(
      withJSONObject: ["characters": content.utf16.count, "paragraphs": 5000, "samples": samples],
      options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: output, as: UTF8.self))
  }
}
