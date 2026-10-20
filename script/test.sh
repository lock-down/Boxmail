#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
if [[ ! -d Backend/node_modules ]]; then
  npm ci --prefix Backend --no-fund --no-audit
fi
# The PPT integration tests exercise the same native renderer shipped in the App.
swift build --product BoxmailPresentationRenderer
export BOXMAIL_PRESENTATION_RENDERER="$(swift build --show-bin-path)/BoxmailPresentationRenderer"
npm test --prefix Backend

# Some Command Line Tools distributions do not auto-load the Testing macro plugin.
SWIFT_USR="$(cd "$(dirname "$(xcrun --find swift)")/.." && pwd)"
TESTING_PLUGIN="$SWIFT_USR/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$TESTING_PLUGIN" ]]; then
  swift test -Xswiftc -load-plugin-library -Xswiftc "$TESTING_PLUGIN"
else
  swift test
fi
