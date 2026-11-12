import AppKit
import Foundation

struct ReleaseVersion: Comparable {
    let components: [Int]

    init?(_ value: String) {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        // Preview releases do not replace the stable version.
        guard !text.contains("-") else { return nil }
        let version = text.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let pieces = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(pieces.count),
              pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              pieces.allSatisfy({ Int($0) != nil }) else { return nil }
        components = pieces.map { Int($0)! }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

struct GitHubUpdateChecker {
    struct Release: Decodable {
        let tag_name: String
        let html_url: URL
        let draft: Bool
        let prerelease: Bool
    }

    enum Result {
        case update(version: String, url: URL)
        case current
    }

    enum Failure: Error {
        case unavailable, invalidRelease
    }

    let owner: String
    let repository: String
    var session = URLSession.shared

    func check(current: String) async throws -> Result {
        guard let installed = ReleaseVersion(current),
              var components = URLComponents(string: "https://api.github.com") else {
            throw Failure.invalidRelease
        }
        components.path = "/repos/\(owner)/\(repository)/releases/latest"
        guard let url = components.url else { throw Failure.invalidRelease }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Yecatz/\(current)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw Failure.unavailable
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease,
              let version = ReleaseVersion(release.tag_name),
              release.html_url.scheme?.lowercased() == "https",
              release.html_url.host?.lowercased() == "github.com",
              release.html_url.path.lowercased().hasPrefix("/\(owner.lowercased())/\(repository.lowercased())/releases/") else {
            throw Failure.invalidRelease
        }
        return version > installed ? .update(version: release.tag_name, url: release.html_url) : .current
    }
}
