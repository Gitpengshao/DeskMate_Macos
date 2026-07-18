#!/usr/bin/env bash
set -euo pipefail

# DeskMate macOS 打包脚本
# 输出：build/DeskMate_v{VERSION}.dmg
# 用法：./script/build_and_release.sh [版本号]
#
# 版本号优先级：
#   1. 命令行参数传入的版本号
#   2. 最近的 git tag（格式 v*）
#   3. Xcode 工程中的 MARKETING_VERSION（自动补 v 前缀）
#   4. 默认 v0.0.1

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="DeskMate"
CONFIGURATION="Release"
BUILD_DIR="${PROJECT_DIR}/build"
DERIVED_DATA_DIR="${BUILD_DIR}/DerivedData"
APP_NAME="DeskMate.app"

# 获取版本号
get_version() {
    if [[ $# -ge 1 && -n "$1" ]]; then
        echo "$1"
        return
    fi

    local git_tag
    git_tag="$(git -C "${PROJECT_DIR}" describe --tags --abbrev=0 2>/dev/null || true)"
    if [[ -n "${git_tag}" ]]; then
        echo "${git_tag}"
        return
    fi

    local xcode_version
    xcode_version="$(awk '/MARKETING_VERSION =/{gsub(/;/,"",$3); print $3; exit}' "${PROJECT_DIR}/DeskMate.xcodeproj/project.pbxproj" 2>/dev/null || true)"
    if [[ -n "${xcode_version}" ]]; then
        echo "v${xcode_version}"
        return
    fi

    echo "v0.0.1"
}

VERSION="$(get_version "${1:-}")"
DMG_NAME="DeskMate_${VERSION}.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"
STAGING_DIR="${BUILD_DIR}/DeskMate_${VERSION}"

echo "==> DeskMate macOS 打包脚本"
echo "    版本：${VERSION}"
echo "    工程目录：${PROJECT_DIR}"
echo "    输出文件：${DMG_PATH}"

# 检测必要工具
if ! command -v xcodebuild &>/dev/null; then
    echo "错误：未找到 xcodebuild，请安装 Xcode 命令行工具。" >&2
    exit 1
fi

# 清理旧构建产物
rm -rf "${DERIVED_DATA_DIR}"
rm -rf "${STAGING_DIR}"
rm -f "${DMG_PATH}"

# 执行 Release 构建
echo "==> 开始 Release 构建..."
xcodebuild \
    -project "${PROJECT_DIR}/DeskMate.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -derivedDataPath "${DERIVED_DATA_DIR}" \
    -destination "platform=macOS" \
    clean build \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO

BUILT_APP="${DERIVED_DATA_DIR}/Build/Products/${CONFIGURATION}/${APP_NAME}"
if [[ ! -d "${BUILT_APP}" ]]; then
    echo "错误：未找到构建产物 ${BUILT_APP}" >&2
    exit 1
fi

# 准备 DMG 内容：App + Applications 快捷方式
echo "==> 准备 DMG 内容..."
mkdir -p "${STAGING_DIR}"
cp -a "${BUILT_APP}" "${STAGING_DIR}/${APP_NAME}"
ln -s /Applications "${STAGING_DIR}/Applications"

# 创建 DMG
echo "==> 创建 DMG..."
hdiutil create \
    -srcfolder "${STAGING_DIR}" \
    -volname "DeskMate ${VERSION}" \
    -fs HFS+ \
    -format UDZO \
    -size 200m \
    "${DMG_PATH}"

if [[ ! -f "${DMG_PATH}" ]]; then
    echo "错误：DMG 创建失败" >&2
    exit 1
fi

echo "    输出：${DMG_PATH}"
echo "    大小：$(du -h "${DMG_PATH}" | cut -f1)"

# 可选：清理中间目录
rm -rf "${STAGING_DIR}"

echo "==> 完成！"
echo "    手动上传文件：${DMG_PATH}"
