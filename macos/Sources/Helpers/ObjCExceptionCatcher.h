#import <Foundation/Foundation.h>

/// This file contains wrappers around various ObjC functions so we can catch
/// exceptions, since you can't natively catch ObjC exceptions from Swift
/// (at least at the time of writing this comment).

/// NSWindow.addTabbedWindow wrapper
FOUNDATION_EXPORT BOOL GhosttyAddTabbedWindowSafely(
    id _Nonnull parent,
    id _Nonnull child,
    NSInteger ordered,
    NSError * _Nullable * _Nullable error
);

FOUNDATION_EXPORT void GhoDexInstallCrashDiagnosticsHandlers(
    const char * _Nonnull markerPath,
    const char * _Nonnull bundleID,
    const char * _Nonnull executableName,
    int pid,
    const char * _Nullable sessionID,
    const char * _Nullable sessionStartedAt
);

FOUNDATION_EXPORT void GhoDexUpdateCrashDiagnosticsContext(
    const char * _Nullable sessionID,
    const char * _Nullable sessionStartedAt,
    int pid
);
