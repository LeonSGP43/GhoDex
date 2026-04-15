import AppKit

final class WorkspaceMapWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            if event.type == .otherMouseDown,
               appDelegate.handleMouseBackForwardTabSwitch(event, in: self) {
                return
            }
        }

        super.sendEvent(event)
    }
}
