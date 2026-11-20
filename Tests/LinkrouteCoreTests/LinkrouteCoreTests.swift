import XCTest
@testable import LinkrouteCore

final class RuleMatcherTests: XCTestCase {
    private func url(_ s: String) -> URL { URL(string: s)! }

    func testHostMatchesItselfAndSubdomains() {
        XCTAssertTrue(RuleMatcher.matches("acme.com", url: url("https://acme.com")))
        XCTAssertTrue(RuleMatcher.matches("acme.com", url: url("https://www.acme.com/a")))
        XCTAssertTrue(RuleMatcher.matches("acme.com", url: url("https://a.b.acme.com")))
        XCTAssertFalse(RuleMatcher.matches("acme.com", url: url("https://notacme.com")))
        XCTAssertFalse(RuleMatcher.matches("acme.com", url: url("https://acme.com.evil.io")))
    }

    func testWildcardSchemeAndPortAreIgnored() {
        XCTAssertTrue(RuleMatcher.matches("*.atlassian.net", url: url("https://acme.atlassian.net/jira")))
        XCTAssertTrue(RuleMatcher.matches("https://Example.com:8443", url: url("http://example.com/")))
        XCTAssertTrue(RuleMatcher.matches("  EXAMPLE.com  ", url: url("https://example.com")))
    }

    func testPathPrefix() {
        XCTAssertTrue(RuleMatcher.matches("github.com/acme", url: url("https://github.com/acme")))
        XCTAssertTrue(RuleMatcher.matches("github.com/acme/", url: url("https://github.com/Acme/repo/pull/1")))
        XCTAssertFalse(RuleMatcher.matches("github.com/acme", url: url("https://github.com/acmecorp/repo")))
        XCTAssertFalse(RuleMatcher.matches("github.com/acme", url: url("https://github.com/")))
    }

    func testTrailingDotHostStillMatches() {
        XCTAssertTrue(RuleMatcher.matches("acme.com", url: url("https://acme.com./a")))
        XCTAssertTrue(RuleMatcher.matches("acme.com.", url: url("https://app.acme.com")))
    }

    func testPatternsWithQueryUserinfoOrInnerWildcardAreInvalid() {
        for bad in ["example.com?x=1", "user@example.com", "a.*.com", "exa mple.com", "example.com#top"] {
            XCTAssertFalse(RuleMatcher.isValid(bad), bad)
        }
        XCTAssertTrue(RuleMatcher.isValid("*.example.com"))
        XCTAssertTrue(RuleMatcher.isValid("github.com/acme"))
    }

    func testInvalidPatternsNeverMatch() {
        XCTAssertFalse(RuleMatcher.matches("", url: url("https://example.com")))
        XCTAssertFalse(RuleMatcher.matches("*", url: url("https://example.com")))
        XCTAssertFalse(RuleMatcher.matches("example.com", url: url("file:///tmp/example.com.html")))
    }

    func testMostSpecificRuleWins() {
        let edge = Target(bundleID: "edge", profileID: "Profile 7")
        let chrome = Target(bundleID: "chrome")
        let rules = [
            Rule(pattern: "github.com", target: chrome),
            Rule(pattern: "github.com/acme", target: edge),
            Rule(pattern: "sharepoint.com", target: chrome),
            Rule(pattern: "acme.sharepoint.com", target: edge),
        ]
        XCTAssertEqual(RuleMatcher.bestMatch(in: rules, for: url("https://github.com/acme/x"))?.target, edge)
        XCTAssertEqual(RuleMatcher.bestMatch(in: rules, for: url("https://github.com/other"))?.target, chrome)
        XCTAssertEqual(RuleMatcher.bestMatch(in: rules, for: url("https://acme.sharepoint.com/s"))?.target, edge)
        XCTAssertEqual(RuleMatcher.bestMatch(in: rules, for: url("https://foo.sharepoint.com"))?.target, chrome)
        XCTAssertNil(RuleMatcher.bestMatch(in: rules, for: url("https://example.com")))
    }

    func testDisabledRulesAreSkippedAndTiesGoToFirst() {
        let a = Target(bundleID: "a"), b = Target(bundleID: "b")
        let rules = [
            Rule(pattern: "x.com", target: a, enabled: false),
            Rule(pattern: "x.com", target: b),
            Rule(pattern: "*.x.com", target: a),
        ]
        XCTAssertEqual(RuleMatcher.bestMatch(in: rules, for: url("https://x.com"))?.target, b)
    }
}

final class ProfileParsingTests: XCTestCase {
    func testChromiumLocalState() throws {
        let json = """
        {"profile": {"last_used": "Profile 2",
          "info_cache": {
            "Profile 2": {"name": "personal"},
            "Profile 1": {"name": "Work"},
            "Default": {"name": ""}
          }}}
        """
        let state = try ChromiumLocalState(data: Data(json.utf8))
        XCTAssertEqual(state.lastUsed, "Profile 2")
        XCTAssertEqual(state.profiles.map(\.name), ["Default", "personal", "Work"])
        XCTAssertEqual(state.profiles.first { $0.name == "Work" }?.id, "Profile 1")
    }

    func testFirefoxProfilesINI() {
        let ini = """
        [Profile1]
        Name=default
        IsRelative=1
        Default=1

        [Profile0]
        Name=default-release

        [General]
        StartWithLastProfile=1

        [Install0123456789ABCDEF]
        Default=Profiles/abcd1234.default-release
        """
        XCTAssertEqual(FirefoxProfiles.names(fromINI: ini), ["default", "default-release"])
    }
}
