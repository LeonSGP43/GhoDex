import AppKit

final class WorkspaceMapWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .otherMouseDown,
           let appDelegate = NSApp.delegate as? AppDelegate,
           appDelegate.handleMouseBackForwardTabSwitch(event, in: self) {
            return
        }

        super.sendEvent(event)
    }
}
