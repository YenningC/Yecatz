// Run on macOS with the repository's supported Swift toolchain.
// xcrun swiftc -swift-version 5 -parse-as-library Updates.swift tools/test_updates.swift -o /tmp/yecatz-update-tests
// /tmp/yecatz-update-tests
import Foundation

private final class ReleasesProtocol: URLProtocol {
    static var pages: [[GitHubUpdateChecker.Release]] = []
    static var requestedPages: [Int] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        let page = Int(query.first(where: { $0.name == "page" })!.value!)!
        Self.requestedPages.append(page)
        let releases = Self.pages[page - 1].map { release -> [String: Any] in
            ["tag_name": release.tag_name, "html_url": release.html_url.absoluteString,
             "draft": release.draft, "prerelease": release.prerelease,
             "assets": release.assets.map { asset -> [String: Any] in
                 ["name": asset.name, "browser_download_url": asset.browser_download_url.absoluteString,
                  "size": asset.size]
             }]
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: releases))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
private struct UpdateTests {
    static func release(_ tag: String, prerelease: Bool = false, draft: Bool = false,
                        assetName: String = "Yecatz-macOS-arm64.zip") -> GitHubUpdateChecker.Release {
        let base = "https://github.com/YenningC/Yecatz/releases"
        return .init(tag_name: tag, html_url: URL(string: "\(base)/tag/\(tag)")!, draft: draft,
                     prerelease: prerelease, assets: [.init(name: assetName,
                        browser_download_url: URL(string: "\(base)/download/\(tag)/\(assetName)")!, size: 1024, digest: nil)])
    }

    static func main() async throws {
        assert(ReleaseVersion("0.1.2") == ReleaseVersion("0.1.2_M"))
        assert(ReleaseVersion("1.10.0")! > ReleaseVersion("1.2.9")!)
        assert(ReleaseVersion("1") == ReleaseVersion("1.0.0"))
        assert(ReleaseVersion.macTag("v1.2.3_M") != nil)
        for invalid in ["1.2.3_W", "1.2.3", "1.2_M", "1.2.3-beta_M", "1.2.3_M+test", "1.2.٣_M"] {
            assert(ReleaseVersion.macTag(invalid) == nil, invalid)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleasesProtocol.self]
        let checker = GitHubUpdateChecker(owner: "YenningC", repository: "Yecatz", session: URLSession(configuration: configuration))
        assert(checker.candidate(release("1.0.0_M")) != nil)
        assert(checker.candidate(release("1.0.0_W")) == nil)
        assert(checker.candidate(release("1.0.0_M", prerelease: true)) == nil)
        assert(checker.candidate(release("1.0.0_M", draft: true)) == nil)
        assert(checker.candidate(release("1.0.0_M", assetName: "Yecatz-Windows-x64.zip")) == nil)
        ReleasesProtocol.pages = [Array(repeating: release("9.0.0_W"), count: 100),
                                 [release("1.2.0_M"), release("1.10.0_M"), release("2.0.0_M", draft: true)]]
        guard case .update(let update) = try await checker.check(current: "0.1.2") else { fatalError("Missing update") }
        assert(update.release.tag_name == "1.10.0_M")
        assert(ReleasesProtocol.requestedPages == [1, 2])
        ReleasesProtocol.pages = [[release("1.0.0_M"), release("1.1.0_W")]]
        guard case .current = try await checker.check(current: "1.0.0_M") else { fatalError("Incorrect platform or equal-version update") }
        ReleasesProtocol.pages = [[]]
        guard case .current = try await checker.check(current: "0.1.2") else { fatalError("Empty releases") }
        print("macOS version, platform, asset, pagination and comparison regressions passed")
    }
}
