#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"

if [[ "${1:-}" == "chat" ]]; then
    printf '聊天已经集成到 Yecatz.app，不再单独构建聊天 App。\n' >&2
    exit 2
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
compiler=(xcrun swiftc -swift-version 5 -sdk "$sdk" -module-cache-path "$scratch/modules")

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
cp persona.txt "$contents/Resources/persona.txt"
ditto Assets "$contents/Resources"
"${compiler[@]}" -target "$(uname -m)-apple-macos14.0" main.swift Chat.swift Commands.swift Weather.swift Updates.swift Transfer.swift -o "$contents/MacOS/Yecatz"
install_bundle Yecatz.app
