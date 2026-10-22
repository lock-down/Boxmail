#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
if [[ -n "$(git status --porcelain)" ]]; then
  echo "发布打包要求干净的已提交源码，请先提交修改或使用独立检出。" >&2
  exit 2
fi
SOURCE_COMMIT="$(git rev-parse HEAD)"
SOURCE_ID="$(git describe --tags --always)"
./script/build_and_run.sh --package
APP_VERSION="$(cat VERSION)"
PACKAGE_ARCH="$(uname -m)"
PACKAGE_NAME="Boxmail-v$APP_VERSION-macos-$PACKAGE_ARCH-clean"
PACKAGE_DIR="$ROOT_DIR/dist/$PACKAGE_NAME"
ARCHIVE="$ROOT_DIR/dist/$PACKAGE_NAME.zip"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PACKAGE_DIR/Boxmail.app/Contents/Info.plist")"
cp docs/USER_GUIDE.md "$PACKAGE_DIR/使用说明.md"
cat > "$PACKAGE_DIR/版本信息.txt" <<INFO
Boxmail $APP_VERSION (build $APP_BUILD)
架构：$PACKAGE_ARCH
最低系统：macOS 14.0
构建类型：Release，全新安装测试包
演示数据：关闭
源码标识：$SOURCE_ID
源码提交：$SOURCE_COMMIT
Node.js：$("$PACKAGE_DIR/Boxmail.app/Contents/Resources/Runtime/node" --version)
生成时间：$(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S %Z')
INFO
rm -f "$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_DIR" "$ARCHIVE"
(cd "$ROOT_DIR/dist" && shasum -a 256 "$PACKAGE_NAME.zip" > "$PACKAGE_NAME.zip.sha256")
echo "测试包：$ARCHIVE"
echo "校验文件：$ARCHIVE.sha256"
