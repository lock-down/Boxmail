#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
APP_NAME="Boxmail"
BUNDLE_ID="com.boxmail.desktop"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
APP_VERSION="$(cat VERSION)"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must contain a version such as 0.0.1" >&2
  exit 2
fi
BUILD_CONFIGURATION="debug"
DEMO_DATA="true"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
case "$MODE" in
--package|package)
  BUILD_CONFIGURATION="release"
  DEMO_DATA="false"
  PACKAGE_ARCH="$(uname -m)"
  APP_BUNDLE="$ROOT_DIR/dist/Boxmail-v$APP_VERSION-macos-$PACKAGE_ARCH-clean/$APP_NAME.app"
  # Recreate only this generated bundle so stale development files cannot enter the package.
  rm -rf "$APP_BUNDLE"
  ;;
run|--verify|verify|--debug|debug|--logs|logs|--telemetry|telemetry)
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  ;;
*) echo "usage: $0 [run|--verify|--debug|--logs|--telemetry|--package]" >&2; exit 2 ;;
esac
APP_CONTENTS="$APP_BUNDLE/Contents"
SIGNING_IDENTITY="${BOXMAIL_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" && -f "$ROOT_DIR/.boxmail-signing-identity" ]]; then
  SIGNING_IDENTITY="$(tr -d '\r\n' < "$ROOT_DIR/.boxmail-signing-identity")"
fi
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
if [[ ! -d Backend/node_modules ]]; then npm ci --prefix Backend --no-fund --no-audit; fi
swift build --configuration "$BUILD_CONFIGURATION"
BUILD_DIR="$(swift build --configuration "$BUILD_CONFIGURATION" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"
launch_app() {
  if [[ -n "${BOXMAIL_DATA:-}" ]]; then
    /usr/bin/open -n "$APP_BUNDLE" --env "BOXMAIL_DATA=$BOXMAIL_DATA"
  else
    /usr/bin/open -n "$APP_BUNDLE"
  fi
}
mkdir -p "$APP_CONTENTS/MacOS" "$APP_CONTENTS/Resources/Runtime" "$APP_CONTENTS/Resources/Backend"
cp "$BUILD_BINARY" "$APP_CONTENTS/MacOS/$APP_NAME"
NODE_BINARY="$(command -v node)"
if [[ ! -f "$APP_CONTENTS/Resources/Runtime/node" || "$NODE_BINARY" -nt "$APP_CONTENTS/Resources/Runtime/node" ]]; then cp "$NODE_BINARY" "$APP_CONTENTS/Resources/Runtime/node"; fi
if [[ "$BUILD_CONFIGURATION" == "release" ]]; then
  # Allowlist source and install production dependencies into an otherwise empty bundle.
  rsync -a --delete Backend/src/ "$APP_CONTENTS/Resources/Backend/src/"
  cp Backend/package.json Backend/package-lock.json "$APP_CONTENTS/Resources/Backend/"
  npm ci --prefix "$APP_CONTENTS/Resources/Backend" --omit=dev --ignore-scripts --no-fund --no-audit
  rm "$APP_CONTENTS/Resources/Backend/package-lock.json"
else
  rsync -a --delete --exclude test --exclude package-lock.json --exclude '*.sqlite*' --exclude '.env*' --exclude '*.log' Backend/ "$APP_CONTENTS/Resources/Backend/"
fi
mkdir -p "$APP_CONTENTS/Resources/Backend/Resources"
cp Sources/BoxmailCore/Resources/DefaultPrompts.json "$APP_CONTENTS/Resources/Backend/Resources/DefaultPrompts.json"
cp Sources/BoxmailCore/Resources/ReplyPresets.json "$APP_CONTENTS/Resources/Backend/Resources/ReplyPresets.json"
rsync -a --delete "$BUILD_DIR/Boxmail_BoxmailCore.bundle/" "$APP_CONTENTS/Resources/Boxmail_BoxmailCore.bundle/"
chmod +x "$APP_CONTENTS/MacOS/$APP_NAME" "$APP_CONTENTS/Resources/Runtime/node"
if [[ ! -f "$APP_CONTENTS/Resources/Boxmail.icns" || script/generate_icon.swift -nt "$APP_CONTENTS/Resources/Boxmail.icns" ]]; then
  mkdir -p artifacts/Boxmail.iconset
  swift script/generate_icon.swift artifacts/Boxmail.iconset
  iconutil -c icns artifacts/Boxmail.iconset -o "$APP_CONTENTS/Resources/Boxmail.icns"
fi
cat > "$APP_CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string><string>zh-Hant</string><string>en</string></array>
<key>CFBundleAllowMixedLocalizations</key><true/>
<key>CFBundleIconFile</key><string>Boxmail</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
<key>CFBundleVersion</key><string>8</string>
<key>BoxmailDemoDataEnabled</key><$DEMO_DATA/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
# A fixed bundle ID alone does not preserve Keychain authorization across ad hoc builds.
# Set BOXMAIL_SIGNING_IDENTITY to a persistent development identity's SHA-1 fingerprint.
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  echo "使用临时签名：重新构建后可能需要再次授权钥匙串。固定证书可通过 BOXMAIL_SIGNING_IDENTITY 配置。" >&2
fi
codesign --force --sign "$SIGNING_IDENTITY" "$APP_CONTENTS/Resources/Runtime/node"
while IFS= read -r -d '' native_module; do
  codesign --force --sign "$SIGNING_IDENTITY" "$native_module"
done < <(find "$APP_CONTENTS/Resources/Backend/node_modules" -type f \( -name '*.node' -o -name '*.dylib' \) -print0)
codesign --force --sign "$SIGNING_IDENTITY" --identifier "$BUNDLE_ID" "$APP_BUNDLE" >/dev/null
codesign --verify --deep --strict "$APP_BUNDLE"
case "$MODE" in
--package|package) echo "已生成全新安装测试 App：$APP_BUNDLE" ;;
run) launch_app ;;
--verify|verify) launch_app; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
--debug|debug) lldb -- "$APP_CONTENTS/MacOS/$APP_NAME" ;;
--logs|logs) launch_app; /usr/bin/log stream --info --style compact --predicate 'process == "Boxmail"' ;;
--telemetry|telemetry) launch_app; /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.boxmail.desktop"' ;;
esac
