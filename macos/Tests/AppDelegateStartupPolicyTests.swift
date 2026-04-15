import Testing
import AppKit
import Foundation
@testable import GhoDex

struct AppDelegateStartupPolicyTests {
    @Test func skipInitialTerminalWindowDefaultsToFalse() {
        #expect(AppDelegate.shouldSkipInitialTerminalWindow(environment: [:]) == false)
    }

    @Test func skipInitialTerminalWindowAcceptsTruthyValues() {
        #expect(
            AppDelegate.shouldSkipInitialTerminalWindow(
                environment: ["GHODEX_SKIP_INITIAL_TERMINAL_WINDOW": "1"]
            )
        )
        #expect(
            AppDelegate.shouldSkipInitialTerminalWindow(
                environment: ["GHODEX_SKIP_INITIAL_TERMINAL_WINDOW": " TRUE "]
            )
        )
        #expect(
            AppDelegate.shouldSkipInitialTerminalWindow(
                environment: ["GHODEX_SKIP_INITIAL_TERMINAL_WINDOW": "yes"]
            )
        )
        #expect(
            AppDelegate.shouldSkipInitialTerminalWindow(
                environment: ["GHODEX_SKIP_INITIAL_TERMINAL_WINDOW": "on"]
            )
        )
    }

    @Test func skipInitialTerminalWindowRejectsFalsyValues() {
        #expect(
            AppDelegate.shouldSkipInitialTerminalWindow(
                environment: ["GHODEX_SKIP_INITIAL_TERMINAL_WINDOW": "0"]
            ) == false
        )
        #expect(
            AppDelegate.shouldSkipInitialTerminalWindow(
                environment: ["GHODEX_SKIP_INITIAL_TERMINAL_WINDOW": "false"]
            ) == false
        )
        #expect(
            AppDelegate.shouldSkipInitialTerminalWindow(
                environment: ["GHODEX_SKIP_INITIAL_TERMINAL_WINDOW": "nope"]
            ) == false
        )
    }

    @Test func applyMenuShortcutAssignsConfiguredNewTabShortcut() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        try """
        keybind = super+t=new_tab
        """.write(to: tempURL, atomically: true, encoding: .utf8)

        let config = Ghostty.Config(at: tempURL.path(percentEncoded: false))
        #expect(config.errors.isEmpty)

        let item = NSMenuItem()
        AppDelegate.applyMenuShortcut(config, action: "new_tab", to: item)

        #expect(item.keyEquivalent == "t")
        #expect(item.keyEquivalentModifierMask.contains(.command))
    }

    @Test func applyMenuShortcutAssignsDefaultNewTabShortcutWhenConfigIsEmpty() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ghodex")

        try "".write(to: tempURL, atomically: true, encoding: .utf8)

        let config = Ghostty.Config(at: tempURL.path(percentEncoded: false))
        #expect(config.errors.isEmpty)

        let item = NSMenuItem()
        AppDelegate.applyMenuShortcut(config, action: "new_tab", to: item)

        #expect(item.keyEquivalent == "t")
        #expect(item.keyEquivalentModifierMask.contains(.command))
    }

    @Test func mouseBackForwardTabSwitchTargetIndexSupportsMouseButtons() {
        #expect(
            AppDelegate.mouseBackForwardTabSwitchTargetIndex(
                forButtonNumber: 3,
                selectedIndex: 0,
                tabCount: 4
            ) == 3
        )
        #expect(
            AppDelegate.mouseBackForwardTabSwitchTargetIndex(
                forButtonNumber: 4,
                selectedIndex: 3,
                tabCount: 4
            ) == 0
        )
    }

    @Test func mouseBackForwardTabSwitchTargetIndexSupportsSwipeDirections() {
        #expect(
            AppDelegate.mouseBackForwardTabSwitchTargetIndex(
                swipeDeltaX: -1,
                selectedIndex: 2,
                tabCount: 4
            ) == 1
        )
        #expect(
            AppDelegate.mouseBackForwardTabSwitchTargetIndex(
                swipeDeltaX: 1,
                selectedIndex: 2,
                tabCount: 4
            ) == 3
        )
        #expect(
            AppDelegate.mouseBackForwardTabSwitchTargetIndex(
                swipeDeltaX: 0,
                selectedIndex: 2,
                tabCount: 4
            ) == nil
        )
    }
}
