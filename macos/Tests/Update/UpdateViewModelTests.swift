import Testing
import Foundation
import SwiftUI
import Sparkle
@testable import Ghostty

struct UpdateViewModelTests {
    // MARK: - Text Formatting Tests

    @Test func testIdleText() {
        let viewModel = UpdateViewModel()
        viewModel.state = .idle
        #expect(viewModel.text == "")
    }

    @Test func testPermissionRequestText() {
        let viewModel = UpdateViewModel()
        let request = SPUUpdatePermissionRequest(systemProfile: [])
        viewModel.state = .permissionRequest(.init(request: request, reply: { _ in }))
        #expect(viewModel.text == AppLocalization.localizedText("Enable Automatic Updates?"))
    }

    @Test func testCheckingText() {
        let viewModel = UpdateViewModel()
        viewModel.state = .checking(.init(cancel: {}))
        #expect(viewModel.text == AppLocalization.localizedText("Checking for Updates…"))
    }

    @Test func testDownloadingTextWithKnownLength() {
        let viewModel = UpdateViewModel()
        viewModel.state = .downloading(.init(cancel: {}, expectedLength: 1000, progress: 500))
        #expect(
            viewModel.text == String(
                format: AppLocalization.localizedText("Downloading: %.0f%%"),
                50.0
            )
        )
    }

    @Test func testDownloadingTextWithUnknownLength() {
        let viewModel = UpdateViewModel()
        viewModel.state = .downloading(.init(cancel: {}, expectedLength: nil, progress: 500))
        #expect(viewModel.text == AppLocalization.localizedText("Downloading…"))
    }

    @Test func testDownloadingTextWithZeroExpectedLength() {
        let viewModel = UpdateViewModel()
        viewModel.state = .downloading(.init(cancel: {}, expectedLength: 0, progress: 500))
        #expect(viewModel.text == AppLocalization.localizedText("Downloading…"))
    }

    @Test func testExtractingText() {
        let viewModel = UpdateViewModel()
        viewModel.state = .extracting(.init(progress: 0.75))
        #expect(
            viewModel.text == String(
                format: AppLocalization.localizedText("Preparing: %.0f%%"),
                75.0
            )
        )
    }

    @Test func testInstallingText() {
        let viewModel = UpdateViewModel()
        viewModel.state = .installing(.init(isAutoUpdate: false, retryTerminatingApplication: {}, dismiss: {}))
        #expect(viewModel.text == AppLocalization.localizedText("Installing…"))
        viewModel.state = .installing(.init(isAutoUpdate: true, retryTerminatingApplication: {}, dismiss: {}))
        #expect(viewModel.text == AppLocalization.localizedText("Restart to Complete Update"))
    }

    @Test func testNotFoundText() {
        let viewModel = UpdateViewModel()
        viewModel.state = .notFound(.init(acknowledgement: {}))
        #expect(viewModel.text == AppLocalization.localizedText("No Updates Available"))
    }

    @Test func testErrorText() {
        let viewModel = UpdateViewModel()
        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        viewModel.state = .error(.init(error: error, retry: {}, dismiss: {}))
        #expect(viewModel.text == "Network error")
    }

    // MARK: - Max Width Text Tests

    @Test func testMaxWidthTextForDownloading() {
        let viewModel = UpdateViewModel()
        viewModel.state = .downloading(.init(cancel: {}, expectedLength: 1000, progress: 50))
        #expect(
            viewModel.maxWidthText == String(
                format: AppLocalization.localizedText("Downloading: %.0f%%"),
                100.0
            )
        )
    }

    @Test func testMaxWidthTextForExtracting() {
        let viewModel = UpdateViewModel()
        viewModel.state = .extracting(.init(progress: 0.5))
        #expect(
            viewModel.maxWidthText == String(
                format: AppLocalization.localizedText("Preparing: %.0f%%"),
                100.0
            )
        )
    }

    @Test func testMaxWidthTextForNonProgressState() {
        let viewModel = UpdateViewModel()
        viewModel.state = .checking(.init(cancel: {}))
        #expect(viewModel.maxWidthText == viewModel.text)
    }
}
