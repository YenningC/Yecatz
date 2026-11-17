import Foundation
import CryptoKit
import Darwin

struct ReleaseVersion: Comparable {
    let components: [Int]

    init?(_ value: String) {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix("_M") { text = String(text.dropLast(2)) }
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(pieces.count),
              pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0 >= "0" && $0 <= "9" }) }),
              pieces.allSatisfy({ Int($0) != nil }) else { return nil }
        components = pieces.map { Int($0)! }
    }

    static func macTag(_ value: String) -> Self? {
        guard value.hasSuffix("_M"), let version = Self(value), version.components.count == 3 else { return nil }
        return version
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: Self, rhs: Self) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

struct GitHubUpdateChecker {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
        let size: Int64
        let digest: String?
    }

    struct Release: Decodable {
        let tag_name: String
        let html_url: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }

    struct Update {
        let release: Release
        let asset: Asset
    }

    enum Result {
        case update(Update)
        case current
    }

    enum Failure: LocalizedError {
        case unavailable, invalidRelease
        var errorDescription: String? {
            switch self {
            case .unavailable: return "无法连接 GitHub 更新服务，请稍后重试。"
            case .invalidRelease: return "发布信息或当前版本号无效。"
            }
        }
    }

    let owner: String
    let repository: String
    var session = URLSession.shared

    func candidate(_ release: Release) -> Update? {
        guard !release.draft, !release.prerelease,
              ReleaseVersion.macTag(release.tag_name) != nil,
              release.html_url.scheme == "https", release.html_url.host?.lowercased() == "github.com",
              release.html_url.path.lowercased() == "/\(owner)/\(repository)/releases/tag/\(release.tag_name)".lowercased() else { return nil }
        let name = "Yecatz-macOS-arm64.zip"
        guard let asset = release.assets.first(where: { $0.name == name }),
              asset.size > 0, asset.size <= 512 * 1024 * 1024,
              asset.browser_download_url.scheme == "https",
              asset.browser_download_url.host?.lowercased() == "github.com",
              asset.browser_download_url.path.lowercased() == "/\(owner)/\(repository)/releases/download/\(release.tag_name)/\(name)".lowercased() else { return nil }
        return Update(release: release, asset: asset)
    }

    func check(current: String) async throws -> Result {
        guard let installed = ReleaseVersion(current) else { throw Failure.invalidRelease }
        var page = 1
        var best: Update?
        while true {
            var components = URLComponents(string: "https://api.github.com")!
            components.path = "/repos/\(owner)/\(repository)/releases"
            components.queryItems = [URLQueryItem(name: "per_page", value: "100"), URLQueryItem(name: "page", value: String(page))]
            var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Yecatz/\(current)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw Failure.unavailable }
            let releases = try JSONDecoder().decode([Release].self, from: data)
            for release in releases {
                guard let update = candidate(release), let version = ReleaseVersion.macTag(release.tag_name), version > installed else { continue }
                if best == nil || version > ReleaseVersion.macTag(best!.release.tag_name)! { best = update }
            }
            if releases.count < 100 { break }
            page += 1
        }
        if let best { return .update(best) }
        return .current
    }
}

enum MacUpdateInstaller {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct Transaction: Codable {
        let target: String
        let version: String
        let token: String
    }

    // A separate process retains the old app until its replacement acknowledges launch.
    // Process arguments carry paths without interpolating them into shell source.
    private static let helper = #"""
    #!/bin/sh
    set -u
    target=$1
    stage=$2
    old_pid=$3
    token=$4
    swap="$stage/yecatz-update-swap"
    replacement="$stage/unpacked/Yecatz.app"
    new_pid=
    old_exited=0
    old_identity=
    replacement_identity=
    success=0

    finish() {
        if [ "$success" -eq 0 ] && [ -n "$old_identity" ] &&
            [ "$(/usr/bin/stat -f '%d:%i' "$replacement" 2>/dev/null)" = "$old_identity" ]; then
            if [ -n "$new_pid" ]; then
                kill "$new_pid" 2>/dev/null || true
                attempts=0
                while kill -0 "$new_pid" 2>/dev/null && [ "$attempts" -lt 10 ]; do
                    sleep 1
                    attempts=$((attempts + 1))
                done
                if kill -0 "$new_pid" 2>/dev/null; then
                    kill -9 "$new_pid" 2>/dev/null || true
                fi
            fi
            if [ "$(/usr/bin/stat -f '%d:%i' "$target" 2>/dev/null)" = "$replacement_identity" ] &&
                "$swap" "$target" "$replacement" >> "$stage/launch.log" 2>&1; then
                /bin/mv "$replacement" "$stage/failed.app" || true
                printf '%s\n' '新版未能完成启动，已恢复旧版本。更新文件保留在此目录供排查。' > "$stage/failure.txt"
                /usr/bin/open -n "$target" --args --yecatz-update-error "$stage" </dev/null
            else
                printf '%s\n' '无法自动恢复旧版本。旧应用保存在此目录的 unpacked/Yecatz.app。' > "$stage/failure.txt"
            fi
        elif [ "$success" -eq 0 ] && [ "$old_exited" -eq 1 ] && [ -d "$target" ]; then
            printf '%s\n' '无法替换当前应用，已重新打开旧版本。请检查应用目录权限后重试。' > "$stage/failure.txt"
            /usr/bin/open -n "$target" --args --yecatz-update-error "$stage" </dev/null
        fi
    }
    trap finish EXIT
    trap 'exit 1' HUP INT TERM
    printf '%s\n' "$token" > "$stage/helper-ready" || exit 1
    attempts=0
    while kill -0 "$old_pid" 2>/dev/null; do
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 60 ]; then
            printf '%s\n' '旧版进程未能退出，已取消安装。' > "$stage/failure.txt"
            exit 1
        fi
        sleep 1
    done
    old_exited=1
    old_identity=$(/usr/bin/stat -f '%d:%i' "$target") || exit 1
    replacement_identity=$(/usr/bin/stat -f '%d:%i' "$replacement") || exit 1
    # The staged slot holds the original bundle after a successful exchange.
    "$swap" "$target" "$replacement" >> "$stage/launch.log" 2>&1 || exit 1
    "$target/Contents/MacOS/Yecatz" --yecatz-update-ready "$stage" --yecatz-update-token "$token" </dev/null >> "$stage/launch.log" 2>&1 &
    new_pid=$!
    attempts=0
    while kill -0 "$new_pid" 2>/dev/null && [ "$attempts" -lt 90 ]; do
        if [ -f "$stage/ready" ] && [ "$(/bin/cat "$stage/ready")" = "$token" ]; then
            sleep 2
            kill -0 "$new_pid" 2>/dev/null || break
            success=1
            /bin/rm -rf "$stage"
            exit 0
        fi
        attempts=$((attempts + 1))
        sleep 1
    done
    exit 1
    """#

    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: output, encoding: .utf8) else {
            throw Failure(message: "更新包验证失败，当前应用已保留。")
        }
        return text
    }

    private static func acquireLock(_ lock: URL) throws -> FileHandle {
        let fd = Darwin.open(lock.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw Failure(message: "无法打开更新锁，请检查应用目录权限。") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let busy = errno == EWOULDBLOCK
            Darwin.close(fd)
            throw Failure(message: busy ? "已有更新任务正在运行。请等待它完成后重试。" : "无法锁定更新目录。")
        }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    static func install(_ update: GitHubUpdateChecker.Update) async throws {
        let manager = FileManager.default
        let target = Bundle.main.bundleURL.standardizedFileURL
        let parent = target.deletingLastPathComponent()
        guard target.pathExtension == "app", target.resolvingSymlinksInPath() == target,
              !target.path.contains("/AppTranslocation/"), manager.isWritableFile(atPath: parent.path) else {
            throw Failure(message: "请先将 Yecatz.app 移到可写的应用目录，再运行更新。")
        }
        #if !arch(arm64)
        throw Failure(message: "当前发布包面向 Apple 芯片，请在 GitHub 查看适合本机的版本。")
        #else
        let stage = parent.appendingPathComponent(".Yecatz-update-\(UUID().uuidString)", isDirectory: true)
        let lock = try acquireLock(parent.appendingPathComponent(".\(target.lastPathComponent).update-lockfile"))
        defer { try? lock.close() }
        var handedOff = false
        defer {
            if !handedOff { try? manager.removeItem(at: stage) }
        }
        try manager.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var request = URLRequest(url: update.asset.browser_download_url, timeoutInterval: 120)
        request.setValue("Yecatz-Updater", forHTTPHeaderField: "User-Agent")
        let (temporary, response) = try await URLSession.shared.download(for: request)
        defer { try? manager.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.scheme == "https",
              ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(http.url?.host?.lowercased() ?? ""),
              let size = try manager.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber,
              size.int64Value == update.asset.size else { throw Failure(message: "更新包下载不完整，请重试。") }
        if let digest = update.asset.digest {
            let handle = try FileHandle(forReadingFrom: temporary)
            defer { try? handle.close() }
            var hash = SHA256()
            while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
            let actual = "sha256:" + hash.finalize().map { String(format: "%02x", $0) }.joined()
            guard digest.lowercased() == actual else { throw Failure(message: "更新包校验值不匹配，请重试。") }
        }
        let archive = stage.appendingPathComponent("release.zip")
        try manager.moveItem(at: temporary, to: archive)
        let members = try run("/usr/bin/unzip", ["-Z1", archive.path]).split(separator: "\n", omittingEmptySubsequences: true)
        guard !members.isEmpty, members.count < 100_000,
              members.allSatisfy({ member in
                  let path = String(member)
                  let parts = path.split(separator: "/", omittingEmptySubsequences: false)
                  return !path.contains("\\") && !path.contains("\r") && !parts.contains("..") && !parts.contains(".")
                      && (parts.first == "Yecatz.app" || parts.first == "__MACOSX")
              }) else { throw Failure(message: "更新包包含无效路径。") }
        let listing = try run("/usr/bin/unzip", ["-Z", "-l", archive.path])
        guard !listing.split(separator: "\n").contains(where: { $0.hasPrefix("l") }) else {
            throw Failure(message: "更新包包含不受支持的符号链接。")
        }
        let unpacked = stage.appendingPathComponent("unpacked", isDirectory: true)
        try manager.createDirectory(at: unpacked, withIntermediateDirectories: false)
        _ = try run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])
        let replacement = unpacked.appendingPathComponent("Yecatz.app", isDirectory: true)
        guard let bundle = Bundle(url: replacement), bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String == "Yecatz",
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              ReleaseVersion(version) == ReleaseVersion.macTag(update.release.tag_name),
              manager.isExecutableFile(atPath: replacement.appendingPathComponent("Contents/MacOS/Yecatz").path) else {
            throw Failure(message: "更新包的应用标识或版本与发布标签不一致。")
        }
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", replacement.path])
        let token = UUID().uuidString
        let transaction = Transaction(target: target.path, version: version, token: token)
        try JSONEncoder().encode(transaction).write(to: stage.appendingPathComponent("transaction.json"), options: .atomic)
        guard let swap = Bundle.main.url(forResource: "yecatz-update-swap", withExtension: nil),
              manager.isExecutableFile(atPath: swap.path) else {
            throw Failure(message: "应用缺少更新工具，请从 GitHub 手动安装完整发行包。")
        }
        try manager.copyItem(at: swap, to: stage.appendingPathComponent("yecatz-update-swap"))
        let script = stage.appendingPathComponent("install.sh")
        try helper.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, target.path, stage.path, String(ProcessInfo.processInfo.processIdentifier), token]
        // The installer inherits the lock descriptor. Closing the app or installer releases it.
        process.standardInput = lock
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            if !handedOff && process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }
        var helperReady = false
        for _ in 0..<50 {
            let marker = try? String(contentsOf: stage.appendingPathComponent("helper-ready"), encoding: .utf8)
            if process.isRunning && marker?.trimmingCharacters(in: .whitespacesAndNewlines) == token {
                helperReady = true
                break
            }
            if !process.isRunning { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard helperReady else {
            throw Failure(message: "无法启动更新安装程序，当前应用已保留。")
        }
        handedOff = true
        #endif
    }

    private static func launchTransaction(_ flag: String) -> (URL, Transaction)? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        let stage = URL(fileURLWithPath: arguments[index + 1]).standardizedFileURL
        let target = Bundle.main.bundleURL.standardizedFileURL
        let name = stage.lastPathComponent
        guard stage.deletingLastPathComponent() == target.deletingLastPathComponent(),
              name.hasPrefix(".Yecatz-update-"), UUID(uuidString: String(name.dropFirst(".Yecatz-update-".count))) != nil,
              stage.resolvingSymlinksInPath() == stage,
              let data = try? Data(contentsOf: stage.appendingPathComponent("transaction.json")),
              let transaction = try? JSONDecoder().decode(Transaction.self, from: data), transaction.target == target.path else { return nil }
        return (stage, transaction)
    }

    static func acknowledgeLaunch() {
        guard let (stage, transaction) = launchTransaction("--yecatz-update-ready"),
              let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              ReleaseVersion(version) == ReleaseVersion(transaction.version),
              let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--yecatz-update-token"),
              index + 1 < ProcessInfo.processInfo.arguments.count,
              ProcessInfo.processInfo.arguments[index + 1] == transaction.token else { return }
        try? transaction.token.write(to: stage.appendingPathComponent("ready"), atomically: true, encoding: .utf8)
    }

    static func launchFailure() -> String? {
        guard let (stage, _) = launchTransaction("--yecatz-update-error") else { return nil }
        return try? String(contentsOf: stage.appendingPathComponent("failure.txt"), encoding: .utf8)
    }
}
