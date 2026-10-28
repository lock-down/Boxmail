---
version: 1
slug: "sources-boxmail-views-developersettingsview-swift"
primary_target: "Sources/Boxmail/Views/DeveloperSettingsView.swift"
related_targets: ["Sources/Boxmail/Views/SettingsView.swift","Sources/Boxmail/Stores/MailStore+Sync.swift"]
---

# Developer diagnostics settings

Mode: Operate. Native macOS SwiftUI. Ordinary scoped extension of the existing SettingsView, not a visual-system change.

## THESIS
A tester can find and export a useful diagnostic ZIP in Settings > 开发者, including while synchronization or the local backend is unhealthy.

## OWN-WORLD
Inherit Boxmail's existing settings sidebar, SectionCard, ActionButton, WorkflowNotice, UIType, Palette and native save panel. No new fonts, decorative raster assets or global tokens.

## STORY
Find 开发者 in the settings sidebar, read what is collected, activate 导出诊断日志, choose the file destination, and see inline success or actionable failure. Current connection and synchronization state is visible below the export action.

## FIRST VIEWPORT
The export action and privacy scope remain visible in the fixed 1000 by 750 point settings window. The two existing card-style sections group export and current state. The button stays enabled during sync and when store.ready is false; only an export in progress disables it.

## FORM
Seed: not-applicable-scoped-extension. The user explicitly requested a developer option and export of key runtime logs. Code-led implementation in the incumbent native settings layout; no decision comp or alternative identity was needed.

## FINISH
Verify default developer settings, native save workflow, exported success, export while backend is disconnected, and safety of the archive's explicit file allowlist. No HTML/CSS detector applies to SwiftUI. Required captures are native desktop settings at their actual fixed size. Keep runtime and secret material out of evidence; use synthetic accounts and loopback services.

## DOCUMENTATION COMPLETION

The final surface preserves the incumbent system in `Sources/Boxmail/Support/DesignSystem.swift` and `Sources/Boxmail/Views/WorkflowControls.swift`: UIType supplies the title, section, body, caption and small roles; Palette supplies the existing canvas, sidebar, paper, accent, muted, success and warning treatments; SectionCard, ActionButton and WorkflowNotice render the two groups, export control and inline result. The fixed Settings layout, sidebar selection and footer remain inherited. No global design files or tokens were created or changed by this documentation pass.

Evidence checked: `.impeccable/review/developer-settings-desktop.png` and `.impeccable/review/developer-export-success-desktop.png` were visually inspected and each measures 2000 × 1500 pixels for the fixed 1000 × 750 point Settings surface. Export, collection scope and privacy text remain visible in both. The success capture shows the saved ZIP path without displacing the current-state card beyond the viewport. `.impeccable/review/developer-finish-review.md` records `ship` with no material surface fixes.

`DiagnosticExportService.swift` uses the asynchronous native save sheet. Interactive destination choice and ZIP creation were exercised by the parent task. Offline export is supported by the local archive implementation and `diagnosticArchiveExcludesCredentialsAndMailAndWorksWithoutBackend`; it has no captured native offline state. The archive's `ditto` flags suppress resource forks, extended attributes and quarantine metadata, and the regression test rejects AppleDouble members. Diagnostic-specific passing results were observed in `.scratch/sync-diagnostics/full-tests.log`; this document does not certify the whole-suite process exit or a combined total. No HTML/CSS detector or shipping raster-asset comparison applies to this native extension.

Detailed evidence and the incumbent-system comparison are recorded in `.impeccable/review/developer-documentation.md`.
