import AppKit

protocol TopLevelTabController: AnyObject {
    var window: NSWindow? { get }
    var titleOverride: String? { get set }
    func promptTabTitle()
    func closeTabImmediately(registerRedo: Bool)
}
