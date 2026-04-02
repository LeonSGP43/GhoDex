import AppKit

enum WorkspaceMapCanvasInputPolicy {
    private static let spacebarKeyCode: UInt16 = 49
    private static let newTabKeyCode: UInt16 = 17

    enum WheelInteractionMode {
        case pan
        case zoom
    }

    enum FocusShortcutDirection {
        case up
        case down
        case left
        case right
    }

    static func isSpaceKey(_ event: NSEvent) -> Bool {
        event.keyCode == spacebarKeyCode
    }

    static func wheelInteractionMode(
        hasPreciseScrollingDeltas _: Bool,
        deltaX: CGFloat,
        deltaY: CGFloat,
        modifierFlags: NSEvent.ModifierFlags
    ) -> WheelInteractionMode {
        if modifierFlags.contains(.shift) {
            return .pan
        }
        // Keep horizontal-leaning wheel gestures as pan, but default to zoom.
        if abs(deltaX) > abs(deltaY) * 1.5 {
            return .pan
        }

        return .zoom
    }

    static func focusShortcutDirection(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> FocusShortcutDirection? {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == [.command, .control] else {
            return nil
        }
        guard let key = charactersIgnoringModifiers?.lowercased() else {
            return nil
        }

        switch key {
        case "i":
            return .up
        case "k":
            return .down
        case "j":
            return .left
        case "l":
            return .right
        default:
            return nil
        }
    }

    static func isTopLevelNewTabShortcut(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags,
        keyCode: UInt16
    ) -> Bool {
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command),
              !modifiers.contains(.control),
              !modifiers.contains(.option),
              !modifiers.contains(.shift) else {
            return false
        }

        if let key = charactersIgnoringModifiers?.lowercased() {
            return key == "t"
        }

        return keyCode == newTabKeyCode
    }
}
