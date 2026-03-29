import XCTest
@testable import GhoDex

final class NewTabPickerWorkspaceMapTests: XCTestCase {
    func testWithBrowserEntryIncludesWorkspaceMapWhenEnabled() {
        let entries = NewTabPickerModel.withBrowserEntry(
            [],
            includeBrowserEntry: true,
            includeWorkspaceMapEntry: true
        )

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].kind, .browser)
        XCTAssertEqual(entries[1].kind, .workspaceMap)
        XCTAssertEqual(entries[0].shortcutIndex, 1)
        XCTAssertEqual(entries[1].shortcutIndex, 2)
    }

    func testWithBrowserEntryCanHideWorkspaceMap() {
        let entries = NewTabPickerModel.withBrowserEntry(
            [],
            includeBrowserEntry: true,
            includeWorkspaceMapEntry: false
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].kind, .browser)
        XCTAssertEqual(entries[0].shortcutIndex, 1)
    }

    func testFilteredEntriesMatchesWorkspaceMapQuery() {
        let entries = NewTabPickerModel.withBrowserEntry(
            [],
            includeBrowserEntry: false,
            includeWorkspaceMapEntry: true
        )
        let filtered = NewTabPickerModel.filteredEntries(entries, query: "workspace map")

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.kind, .workspaceMap)
    }
}
