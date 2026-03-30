import XCTest
@testable import GhoDex

final class NewTabPickerWorkspaceMapTests: XCTestCase {
    func testWithBrowserEntryIncludesBrowserOnly() {
        let entries = NewTabPickerModel.withBrowserEntry([], includeBrowserEntry: true)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].kind, .browser)
        XCTAssertEqual(entries[0].shortcutIndex, 1)
    }

    func testFilteredEntriesDoNotSurfaceWorkspaceMapQuery() {
        let entries = NewTabPickerModel.withBrowserEntry([], includeBrowserEntry: false)
        let filtered = NewTabPickerModel.filteredEntries(entries, query: "workspace map")

        XCTAssertTrue(filtered.isEmpty)
    }

    func testWithBrowserEntryRenumbersExistingEntriesWithoutWorkspaceMapMode() {
        let entries = NewTabPickerModel.withBrowserEntry(
            [
                .init(kind: .host(.local), section: .local, shortcutIndex: nil),
            ],
            includeBrowserEntry: true
        )

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].kind, .browser)
        XCTAssertEqual(entries[0].shortcutIndex, 1)
        XCTAssertEqual(entries[1].kind, .host(.local))
        XCTAssertEqual(entries[1].shortcutIndex, 2)
    }
}
