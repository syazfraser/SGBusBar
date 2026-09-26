import Foundation
import Testing
@testable import SGBusBar

@Suite("What's New and the changelog")
struct ChangelogTests {
    private let sample = """
    # Changelog

    Intro text that isn't part of any version.

    ## [Unreleased]

    ## [0.2.0] - 2026-09-26

    The first public release.

    ### Added
    - Menu bar times with **colour**.
    - [A link](https://example.com).

    ### Fixed
    - A crash.

    ## [0.1.0] - 2026-09-01

    - First version.

    [0.2.0]: https://github.com/syazfraser/SGBusBar/releases/tag/v0.2.0
    """

    @Test("Versions, dates, summaries and sections are read in order")
    func parsing() throws {
        let entries = Changelog.parse(sample)
        #expect(entries.map(\.version) == ["0.2.0", "0.1.0"])  // the empty Unreleased is dropped
        let latest = try #require(entries.first)
        #expect(latest.date == "2026-09-26")
        #expect(latest.summary == ["The first public release."])
        #expect(latest.sections.map(\.title) == ["Added", "Fixed"])
        #expect(latest.sections[0].items.count == 2)
        #expect(entries[1].sections.first?.title == nil)
        #expect(entries[1].sections.first?.items == ["First version."])
    }

    @Test("The app ships a changelog with an entry for its own version")
    func bundledChangelogMatchesVersion() {
        let released = Changelog.load().filter { $0.version != "Unreleased" }
        #expect(released.first?.version == AppInfo.version, "Add a CHANGELOG.md entry when bumping MARKETING_VERSION")
    }
}
