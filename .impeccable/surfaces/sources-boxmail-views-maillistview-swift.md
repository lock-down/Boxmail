---
version: 1
slug: "sources-boxmail-views-maillistview-swift"
primary_target: "Sources/Boxmail/Views/MailListView.swift"
related_targets: ["Sources/Boxmail/Views/MailSenderGroupRow.swift","Sources/Boxmail/Stores/MailStore+SenderGroups.swift"]
---

# Mail list: sender aggregation

Mode: Operate. Platform: native macOS SwiftUI. Scope: extend the existing mail list, preserving its three-pane layout, system typography, slate text, blue selection, thin dividers, menus and native multi-selection.

## Direction contract

THESIS: Collapse repeated sender rows into one latest-mail summary, then disclose older messages without losing the reading pane or selection. Identity is the actual sender address within one account, not the display name or subject.

OWN-WORLD: Keep the existing white mail surface, muted metadata, blue unread and selection states, compact system type, and one-pixel separators. Reuse native List selection and existing controls; no new visual identity or raster assets.

STORY: Start in sender aggregation, see mail counts and the latest time immediately, open a group with its chevron, read or multi-select the visible mails, and switch back to individual chronological rows from the list header. Group counts cover all filtered matches. Draft search remains individual.

FIRST VIEWPORT: Retain the current list header and filters. A compact display menu sits beside selection actions. A grouped row shows sender, count, latest time, latest subject and preview; older children use a modest inset and omit the repeated sender line. Loading, retry and older-mail actions stay inside the expanded group.

FORM: Extend the established native mail list; seed key: not-applicable-scoped-extension. Groups and children sort newest first. Preserve selection across refreshes, expose externally opened older mail, never silently act on collapsed unseen mail, and keep account boundaries intact.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

This is an ordinary extension: no system changes or new DESIGN.md are authorized. The documenter must compare it against the incumbent tokens and preserve the existing design files. Verify the native app at the regular desktop window and minimum supported width. The HTML/CSS detector does not apply to SwiftUI. No plugin update runs in this task.

## Verification completion

Completed on 2026-10-27 against the final source and saved native captures. This finish follows the scoped-extension exception above: the incumbent authority remains `Sources/Boxmail/Support/DesignSystem.swift` and the existing `MailListView` / `ContentView`. There is no approved or implemented design-system change. `PRODUCT.md`, `DESIGN.md` and `.impeccable/design.json` remain absent; no global design documentation or tokens were created or repaired.

The collapsed desktop, expanded desktop and expanded narrow captures in `.impeccable/review/` retain the existing paper ground, slate metadata, blue unread/selection treatment, compact system typography, separators and three-pane layout. All three are 2880 × 1800 pixels, representing a 1440 × 900 pt window at 2×. The first two show a 380 pt list; the narrow capture verifies the list's 294 pt minimum within that same window. It is not evidence of a minimum whole-window capture. Counted summaries, independent disclosure, inset children without repeated sender names, and latest-first dates preserve the direction contract.

The full visual review in `.impeccable/review/sender-review.md` passed these three captures. Its subsequent verdict resolved the literal-plus query-encoding fix and records `disposition: ship`; that verdict scores the listed fix, not a fresh whole-surface audit. Both parent and member request sources contain the repair. Final regression evidence in `.scratch/sender-grouping/full-tests.log` is 333 Node tests and 121 Swift tests (37 client + 84 Core), with no failures or skips. `git diff --check` passes. The review's earlier 120-Swift count is superseded by this final log and its own verdict section.

This documentation pass inspected saved source, captures and regression evidence. Loading, retry, mode persistence, keyboard handling, selection and older-mail reveal are supported by source and recorded test/review evidence, not by additional captures or a new interactive run. No new shipping raster assets were introduced. Detailed evidence and scope limits are recorded in `.impeccable/review/sender-documentation.md`.
