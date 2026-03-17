import Foundation

extension Ghostty {
    /// This is a delegate that should be applied to your global app delegate for GhoDexKit
    /// to perform app-global operations.
    protocol Delegate {
        /// Look up a surface within the application by ID.
        func ghosttySurface(id: UUID) -> SurfaceView?
    }
}
