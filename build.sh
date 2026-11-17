#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"

if [[ "${1:-}" == "chat" ]]; then
    printf '聊天已经集成到 Yecatz.app，不再单独构建聊天 App。\n' >&2
    exit 2
fi

release_tag="${1:-}"
if [[ "$#" -gt 1 ]] || [[ -n "$release_tag" && ! "$release_tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+_M$ ]]; then
    printf '版本参数应使用 ./build.sh 1.0.0_M 格式。\n' >&2
    exit 2
fi

required_assets=(cat.png cat-blink.png cat-entry.png AppIcon.icns pixel-zh-hans.ttf tie-status.png)
missing_assets=()
for asset in "${required_assets[@]}"; do
    if [[ ! -f "Assets/$asset" || ! -s "Assets/$asset" ]]; then
        missing_assets+=("Assets/$asset")
    fi
done
if (( ${#missing_assets[@]} > 0 )); then
    printf '缺少必需素材或文件为空，请向维护者取得完整的 Assets 目录：\n' >&2
    printf '  %s\n' "${missing_assets[@]}" >&2
    exit 1
fi

sdk="${SDKROOT:-}"
if [[ -z "$sdk" ]]; then
    probe="$(mktemp "${TMPDIR:-/tmp}/yecatz-sdk.XXXXXX.swift")"
    printf 'print("ok")\n' > "$probe"
    while IFS= read -r candidate; do
        [[ "$(basename "$candidate")" == "MacOSX.sdk" ]] && continue
        if xcrun swiftc -sdk "$candidate" "$probe" -o "$probe.bin" >/dev/null 2>&1; then
            sdk="$candidate"
            break
        fi
    done < <(ls -1d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -r)
    rm -f "$probe" "$probe.bin"
fi
[[ -n "$sdk" ]] || sdk="$(xcrun --sdk macosx --show-sdk-path)"

scratch="$(mktemp -d "${TMPDIR:-/tmp}/yecatz-build.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
compiler=(xcrun swiftc -swift-version 5 -sdk "$sdk" -module-cache-path "$scratch/modules" -target "$(uname -m)-apple-macos14.0")

install_bundle() {
    local bundle="$1"
    codesign --force --sign - "$scratch/$bundle"
    if [[ -e "$bundle" ]]; then
        mv "$bundle" "$scratch/previous.app"
    fi
    if ! mv "$scratch/$bundle" "$bundle"; then
        if [[ -e "$scratch/previous.app" ]]; then mv "$scratch/previous.app" "$bundle"; fi
        return 1
    fi
    if [[ -e "$scratch/previous.app" ]]; then rm -rf "$scratch/previous.app"; fi
    codesign --verify --strict "$bundle"
}

contents="$scratch/Yecatz.app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp Info.plist "$contents/Info.plist"
if [[ -n "$release_tag" ]]; then
    release_version="${release_tag%_M}"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $release_version" "$contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $release_version" "$contents/Info.plist"
fi
cp persona.md "$contents/Resources/persona.md"
ditto Assets "$contents/Resources"
"${compiler[@]}" main.swift Chat.swift Commands.swift Weather.swift Updates.swift Transfer.swift -o "$contents/MacOS/Yecatz"
"${compiler[@]}" tools/mac_update_swap.swift -o "$contents/Resources/yecatz-update-swap"
install_bundle Yecatz.app
