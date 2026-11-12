import AppKit
import AVFoundation
import Foundation

/// A small, local command layer that handles obvious desktop actions without
/// spending an API request. Anything it does not recognize falls through to
/// the normal chat model.
struct LocalCommand {
    let run: () -> String

    static func match(_ raw: String) -> LocalCommand? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()

        if text.count <= 18,
           !contains(lower, ["不想听", "不要放", "别放", "不想放", "不要听"]),
           contains(lower, ["放点音乐", "放首歌", "来点音乐", "来首歌", "播放音乐", "放音乐", "放歌", "听歌", "想听歌", "play music"]) {
            return LocalCommand { MediaControl.play() }
        }
        if text.count <= 6,
           ["放", "来吧", "放吧", "放啊", "你放啊", "放起来", "来"].contains(lower) {
            return LocalCommand { MediaControl.play() }
        }
        if contains(lower, ["打开音乐", "开音乐"]) {
            return LocalCommand { MediaControl.openMusic() }
        }
        if text.count <= 6,
           contains(lower, ["暂停", "停一下", "别放了", "先停", "pause"]) {
            return LocalCommand { MediaControl.pause() }
        }
        if contains(lower, ["下一首", "换一首", "切歌", "next track", "next song"]) {
            return LocalCommand { MediaControl.next() }
        }
        if contains(lower, ["上一首", "前一首", "previous track", "previous song"]) {
            return LocalCommand { MediaControl.previous() }
        }
        if let volume = requestedVolume(text) {
            return LocalCommand { MediaControl.setVolume(to: volume) }
        }
        if contains(lower, ["大声点", "大声一点", "音量大", "声音大", "调大声音", "调大音量", "声音调大", "音量调大", "volume up"]) {
            return LocalCommand { MediaControl.volume(by: 10) }
        }
        if contains(lower, ["小声点", "小声一点", "音量小", "声音小", "调小声音", "调小音量", "声音调小", "音量调小", "volume down"]) {
            return LocalCommand { MediaControl.volume(by: -10) }
        }
        if contains(lower, ["取消静音", "恢复声音", "unmute"]) {
            return LocalCommand { MediaControl.setMuted(false) }
        }
        if !contains(lower, ["不要静音", "别静音"]),
           contains(lower, ["静音", "mute"]) {
            return LocalCommand { MediaControl.setMuted(true) }
        }
        if contains(lower, ["几点了", "现在几点", "什么时间", "what time"]) {
            return LocalCommand { LocalCommand.timeReply() }
        }
        if contains(lower, ["今天几号", "今天日期", "星期几", "今天星期", "what date", "what day"]) {
            return LocalCommand { LocalCommand.dateReply() }
        }
        if contains(lower, ["打开浏览器", "打开 safari", "打开safari", "open safari"]) {
            return LocalCommand { LocalCommand.open(bundle: "com.apple.Safari", reply: "浏览器打开了。") }
        }
        if contains(lower, ["打开访达", "打开 finder", "打开finder", "open finder"]) {
            return LocalCommand {
                NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()))
                return "访达打开了。"
            }
        }
        if contains(lower, ["打开计算器", "open calculator"]) {
            return LocalCommand { LocalCommand.open(bundle: "com.apple.calculator", reply: "计算器打开了。") }
        }
        return nil
    }

    private static func requestedVolume(_ text: String) -> Int? {
        let lower = text.lowercased()
        guard lower.contains("音量") || lower.contains("声音") || lower.contains("调到")
            || lower.contains("百分之") || lower.contains("%") else { return nil }
        let scalars = Array(lower)
        var digits = ""
        for scalar in scalars {
            if scalar.isNumber { digits.append(scalar) }
        }
        if let value = Int(digits), (0...100).contains(value) { return value }
        if let percent = lower.range(of: "百分之") {
            let rest = lower[percent.upperBound...]
            if let value = chineseNumber(String(rest)), (0...100).contains(value) { return value }
        }
        return nil
    }

    private static func chineseNumber(_ text: String) -> Int? {
        let map: [Character: Int] = ["零": 0, "一": 1, "二": 2, "三": 3, "四": 4,
                                     "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        if text.contains("百") { return 100 }
        if let ten = text.firstIndex(of: "十") {
            let before = text[..<ten]
            let after = text[text.index(after: ten)...]
            let tens = before.isEmpty ? 1 : (map[before.first ?? "一"] ?? 1)
            let ones = after.first.flatMap { map[$0] } ?? 0
            return tens * 10 + ones
        }
        return text.first.flatMap { map[$0] }
    }

    private static func contains(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func open(bundle: String, reply: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            return "没找到这个 App。"
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            _ = error
        }
        return reply
    }

    private static func timeReply() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return "现在 \(formatter.string(from: Date()))，\(weekday())。"
    }

    private static func dateReply() -> String {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: Date())
        let day = calendar.component(.day, from: Date())
        return "\(month) 月 \(day) 日，\(weekday())。"
    }

    private static func weekday() -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let index = Calendar.current.component(.weekday, from: Date()) - 1
        return "星期\(names[max(0, min(names.count - 1, index))])"
    }
}

enum MediaControl {
    private static let spotifyBundle = "com.spotify.client"

    private static var spotifyRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: spotifyBundle).isEmpty
    }

    private static var musicRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
    }

    static func play() -> String {
        PreviewPlayer.shared.stop()
        if let local = LocalMusic.next(), PreviewPlayer.shared.playFile(local) {
            return "放首 \(LocalMusic.displayName(local))。"
        }
        if spotifyRunning {
            return runScript("""
            tell application "Spotify"
                activate
                play
            end tell
            """, success: "行，放点音乐。", failure: "Spotify 没启动起来。")
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return runScript("""
            tell application "Music"
                activate
                play
            end tell
            """, success: "行，放点音乐。", failure: "音乐 App 没开始播放，可能曲库是空的。")
        }
        return "这台 Mac 上没找到音乐 App。"
    }

    enum RecommendationPlayback {
        case played
        case missing
        case failed(String)
    }

    static func playRecommended(_ song: RecommendedSong) -> RecommendationPlayback {
        if spotifyRunning {
            return .missing
        }
        let artist = appleScriptString(song.artist)
        let title = appleScriptString(song.title)
        let source = """
        tell application "Music"
            activate
            set hits to (every track whose name contains "\(title)" and artist contains "\(artist)")
            if (count of hits) > 0 then
                play item 1 of hits
                return "played"
            end if
        end tell
        return "missing"
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return .failed("音乐 App 没响应。") }
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 {
                return .failed("没有控制音乐的权限。去“系统设置 → 隐私与安全性 → 自动化”里允许 Yecatz。")
            }
            return .failed("音乐 App 没播起来。")
        }
        return result.stringValue == "played" ? .played : .missing
    }

    private static func appleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func openMusic() -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return "音乐打开了。"
        }
        return "没找到音乐 App。"
    }

    static func pause() -> String {
        if PreviewPlayer.shared.stop() { return "先停一下。" }
        if spotifyRunning {
            return runScript("tell application \"Spotify\" to pause", success: "先停一下。", failure: "暂停失败。")
        }
        if musicRunning {
            return runScript("tell application \"Music\" to pause", success: "先停一下。", failure: "暂停失败。")
        }
        return "音乐没在放。"
    }

    static func next() -> String {
        PreviewPlayer.shared.stop()
        if spotifyRunning {
            return runScript("tell application \"Spotify\" to next track", success: "换一首。", failure: "切歌失败。")
        }
        if musicRunning {
            return runScript("tell application \"Music\" to next track", success: "换一首。", failure: "切歌失败。")
        }
        return "音乐没在放。"
    }

    static func previous() -> String {
        PreviewPlayer.shared.stop()
        if spotifyRunning {
            return runScript("tell application \"Spotify\" to previous track", success: "回上一首。", failure: "切歌失败。")
        }
        if musicRunning {
            return runScript("tell application \"Music\" to previous track", success: "回上一首。", failure: "切歌失败。")
        }
        return "音乐没在放。"
    }

    static func volume(by delta: Int) -> String {
        let script = """
        set currentVolume to output volume of (get volume settings)
        set newVolume to currentVolume + \(delta)
        if newVolume > 100 then set newVolume to 100
        if newVolume < 0 then set newVolume to 0
        set volume output volume newVolume
        """
        return runScript(script, success: delta > 0 ? "大声一点。" : "小声一点。", failure: "音量没调成。")
    }

    static func setVolume(to value: Int) -> String {
        let clamped = max(0, min(100, value))
        return runScript("set volume output volume \(clamped)",
                         success: "音量调到 \(clamped)。",
                         failure: "音量没调成。")
    }

    static func setMuted(_ muted: Bool) -> String {
        let script = "set volume output muted \(muted ? "true" : "false")"
        return runScript(script, success: muted ? "静音了。" : "声音回来了。", failure: "静音没设置成。")
    }

    private static func runScript(_ source: String, success: String, failure: String) -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return failure }
        script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 {
                return "没有控制音乐的权限。去“系统设置 → 隐私与安全性 → 自动化”里允许 Yecatz。"
            }
            return failure
        }
        return success
    }
}

struct RecommendedSong {
    let artist: String
    let title: String
    let reason: String
}

enum LocalRecommendation {
    static let songs: [RecommendedSong] = [
        RecommendedSong(artist: "Kanye West", title: "Runaway",
                        reason: "钢琴一响，情绪就有地方落脚了。"),
        RecommendedSong(artist: "Frank Ocean", title: "Pink + White",
                        reason: "钢琴和和声都很轻，听完像晒到一点太阳。"),
        RecommendedSong(artist: "The Weeknd", title: "Blinding Lights",
                        reason: "夜路和合成器，是很难输的组合。"),
        RecommendedSong(artist: "Steve Lacy", title: "Bad Habit",
                        reason: "松弛的旋律里藏着一点不甘心。"),
        RecommendedSong(artist: "Denzel Curry", title: "Walkin",
                        reason: "节奏越走越有劲，适合把状态拉回来。"),
        RecommendedSong(artist: "Sampha", title: "Blood On Me",
                        reason: "有点紧张，也有种推着人往前的力量。"),
        RecommendedSong(artist: "Avicii", title: "Levels",
                        reason: "前奏起来，空气都亮了。"),
        RecommendedSong(artist: "Tyler, The Creator", title: "See You Again",
                        reason: "旋律甜，底色有点倔。")
    ]

    private static var index = 0

    static func matches(_ text: String) -> Bool {
        let lower = text.lowercased()
        guard !contains(lower, ["不想听", "不要放", "别放", "不想放", "不要听", "别推荐"]) else { return false }
        return contains(lower, [
            "来首你推荐的", "来一首你推荐的", "推荐一首歌", "推荐首歌",
            "来首你喜欢的", "来一首你喜欢的", "放首你喜欢的", "放一首你喜欢的",
            "播放一首你喜欢的", "播一首你喜欢的", "你推荐一首", "recommend a song",
            "play a song you like", "play your favorite song",
            "再来一首你推荐", "再推荐一首", "放首你推荐的", "放一首你推荐的",
            "来首你推荐", "来一首你推荐", "来首牛逼", "来首有劲", "来首带劲",
            "来首好听", "来首燃", "来首你拿手", "点首歌", "推荐首"
        ])
    }

    static func next() -> RecommendedSong {
        let song = songs[index % songs.count]
        index += 1
        return song
    }

    private static func requestedVolume(_ text: String) -> Int? {
        let lower = text.lowercased()
        guard lower.contains("音量") || lower.contains("声音") || lower.contains("调到")
            || lower.contains("百分之") || lower.contains("%") else { return nil }
        let scalars = Array(lower)
        var digits = ""
        for scalar in scalars {
            if scalar.isNumber { digits.append(scalar) }
        }
        if let value = Int(digits), (0...100).contains(value) { return value }
        if let percent = lower.range(of: "百分之") {
            let rest = lower[percent.upperBound...]
            if let value = chineseNumber(String(rest)), (0...100).contains(value) { return value }
        }
        return nil
    }

    private static func chineseNumber(_ text: String) -> Int? {
        let map: [Character: Int] = ["零": 0, "一": 1, "二": 2, "三": 3, "四": 4,
                                     "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        if text.contains("百") { return 100 }
        if let ten = text.firstIndex(of: "十") {
            let before = text[..<ten]
            let after = text[text.index(after: ten)...]
            let tens = before.isEmpty ? 1 : (map[before.first ?? "一"] ?? 1)
            let ones = after.first.flatMap { map[$0] } ?? 0
            return tens * 10 + ones
        }
        return text.first.flatMap { map[$0] }
    }

    private static func contains(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}

enum LocalMusic {
    private static var chosen: URL?

    static func ensureFolder() -> URL {
        if let chosen { return chosen }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support")
        let candidates = [
            home.appendingPathComponent("Music", isDirectory: true).appendingPathComponent("Yecatz", isDirectory: true),
            support.appendingPathComponent("Yecatz", isDirectory: true).appendingPathComponent("Music", isDirectory: true),
            home.appendingPathComponent("Yecatz Music", isDirectory: true)
        ]

        var picked: URL?
        for candidate in candidates {
            do {
                try FileManager.default.createDirectory(
                    at: candidate,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o755]
                )
                if FileManager.default.isWritableFile(atPath: candidate.path) {
                    picked = candidate
                    break
                }
            } catch {
                continue
            }
        }
        let url = picked ?? candidates[1]
        chosen = url
        writeReadme(at: url)
        return url
    }

    static var folderURL: URL { ensureFolder() }

    private static func writeReadme(at url: URL) {
        let readme = url.appendingPathComponent("README.txt")
        if !FileManager.default.fileExists(atPath: readme.path) {
            let text = """
            把无 DRM 的 mp3 / m4a / aac / wav / aiff 放在这里。
            文件名建议写成：歌手 - 歌名.mp3
            Yecatz 的「放点音乐」会优先播放这里的歌；
            「来首你推荐的歌」如果歌单里有匹配文件，会整首播放。
            """
            try? text.write(to: readme, atomically: true, encoding: .utf8)
        }
    }

    static func files() -> [URL] {
        let url = ensureFolder()
        let extensions = ["mp3", "m4a", "aac", "wav", "aiff", "aif"]
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static var index = 0

    static func next() -> URL? {
        let all = files()
        guard !all.isEmpty else { return nil }
        let file = all[index % all.count]
        index += 1
        return file
    }

    static func match(artist: String, title: String) -> URL? {
        let artist = artist.lowercased()
        let title = title.lowercased()
        return files().first { url in
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            return name.contains(title) || (name.contains(artist) && name.contains(title.split(separator: " ").first ?? ""))
        }
    }

    static func displayName(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }
}

final class PreviewPlayer {
    static let shared = PreviewPlayer()
    private var player: AVAudioPlayer?
    private var tempURL: URL?
    private var generation = UUID()

    private init() {}

    func play(_ url: URL) async -> Bool {
        stop()
        let token = UUID()
        generation = token
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return false }
        guard generation == token else { return false }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("yecatz-preview-\(UUID().uuidString).m4a")
        guard (try? data.write(to: temp)) != nil,
              let player = try? AVAudioPlayer(contentsOf: temp)
        else {
            try? FileManager.default.removeItem(at: temp)
            return false
        }
        guard generation == token else {
            try? FileManager.default.removeItem(at: temp)
            return false
        }
        self.player = player
        self.tempURL = temp
        player.prepareToPlay()
        return player.play()
    }

    func playFile(_ url: URL) -> Bool {
        stop()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return false }
        self.player = player
        self.tempURL = nil
        player.prepareToPlay()
        return player.play()
    }

    @discardableResult
    func stop() -> Bool {
        generation = UUID()
        let wasPlaying = player != nil
        player?.stop()
        player = nil
        if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
        tempURL = nil
        return wasPlaying
    }

    static func previewURL(artist: String, title: String) async -> URL? {
        let desiredArtist = normalized(artist)
        let desiredTitle = normalized(title)
        for country in ["cn", "us"] {
            guard !Task.isCancelled else { return nil }
            guard var components = URLComponents(string: "https://itunes.apple.com/search") else { continue }
            components.queryItems = [
                URLQueryItem(name: "term", value: "\(artist) \(title)"),
                URLQueryItem(name: "entity", value: "song"),
                URLQueryItem(name: "limit", value: "8"),
                URLQueryItem(name: "country", value: country)
            ]
            guard let url = components.url else { continue }
            guard let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 8)),
                  let response = try? JSONDecoder().decode(ITunesResponse.self, from: data),
                  let preview = response.results.first(where: { item in
                      normalized(item.artistName ?? "") == desiredArtist &&
                      normalized(item.trackName ?? "").hasPrefix(desiredTitle) &&
                      item.previewUrl != nil
                  })?.previewUrl,
                  let previewURL = URL(string: preview), previewURL.scheme == "https"
            else { continue }
            return previewURL
        }
        return nil
    }

    private struct ITunesResponse: Decodable {
        struct Item: Decodable {
            let artistName: String?
            let trackName: String?
            let previewUrl: String?
        }
        let results: [Item]
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }
}
