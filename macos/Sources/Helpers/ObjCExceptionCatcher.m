#import "ObjCExceptionCatcher.h"

#import <AppKit/AppKit.h>
#import <errno.h>
#import <fcntl.h>
#import <limits.h>
#import <signal.h>
#import <string.h>
#import <sys/stat.h>
#import <sys/types.h>
#import <unistd.h>

static char gGhoDexCrashMarkerPath[PATH_MAX];
static char gGhoDexCrashBundleID[256];
static char gGhoDexCrashExecutableName[256];
static char gGhoDexCrashSessionID[128];
static char gGhoDexCrashSessionStartedAt[128];
static volatile sig_atomic_t gGhoDexCrashMarkerWritten = 0;
static int gGhoDexCrashPID = 0;

static void GhoDexCopyCString(char *destination, size_t destinationSize, const char *source) {
    if (destinationSize == 0) {
        return;
    }

    if (source == NULL) {
        destination[0] = '\0';
        return;
    }

    strncpy(destination, source, destinationSize - 1);
    destination[destinationSize - 1] = '\0';
}

static const char *GhoDexCrashReasonForSignal(int signalNumber, char *buffer, size_t bufferSize) {
    switch (signalNumber) {
        case SIGABRT:
            return "signal_sigabrt";
        case SIGILL:
            return "signal_sigill";
        case SIGSEGV:
            return "signal_sigsegv";
        case SIGBUS:
            return "signal_sigbus";
        case SIGFPE:
            return "signal_sigfpe";
        case SIGTRAP:
            return "signal_sigtrap";
        default:
            snprintf(buffer, bufferSize, "signal_%d", signalNumber);
            return buffer;
    }
}

static const char *GhoDexCrashSignalName(int signalNumber) {
    switch (signalNumber) {
        case SIGABRT:
            return "SIGABRT";
        case SIGILL:
            return "SIGILL";
        case SIGSEGV:
            return "SIGSEGV";
        case SIGBUS:
            return "SIGBUS";
        case SIGFPE:
            return "SIGFPE";
        case SIGTRAP:
            return "SIGTRAP";
        default:
            return "SIGUNKNOWN";
    }
}

static void GhoDexWriteBufferToCrashMarker(const char *buffer, size_t length) {
    if (gGhoDexCrashMarkerPath[0] == '\0' || buffer == NULL || length == 0) {
        return;
    }

    int fileDescriptor = open(
        gGhoDexCrashMarkerPath,
        O_WRONLY | O_CREAT | O_TRUNC,
        S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
    );
    if (fileDescriptor < 0) {
        return;
    }

    size_t remaining = length;
    const char *cursor = buffer;
    while (remaining > 0) {
        ssize_t written = write(fileDescriptor, cursor, remaining);
        if (written < 0) {
            if (errno == EINTR) {
                continue;
            }
            break;
        }
        remaining -= (size_t)written;
        cursor += written;
    }

    fsync(fileDescriptor);
    close(fileDescriptor);
}

static void GhoDexWriteSignalCrashMarker(int signalNumber) {
    if (gGhoDexCrashMarkerPath[0] == '\0' || gGhoDexCrashMarkerWritten) {
        return;
    }
    gGhoDexCrashMarkerWritten = 1;

    char reasonBuffer[32];
    const char *reason = GhoDexCrashReasonForSignal(signalNumber, reasonBuffer, sizeof(reasonBuffer));
    const char *signalName = GhoDexCrashSignalName(signalNumber);

    char buffer[2048];
    int length = snprintf(
        buffer,
        sizeof(buffer),
        "schema_version=1\n"
        "crash_kind=fatal_signal\n"
        "pid=%d\n"
        "bundle_id=%s\n"
        "executable_name=%s\n"
        "session_id=%s\n"
        "session_started_at=%s\n"
        "reason=%s\n"
        "signal_name=%s\n"
        "signal_number=%d\n",
        gGhoDexCrashPID,
        gGhoDexCrashBundleID,
        gGhoDexCrashExecutableName,
        gGhoDexCrashSessionID,
        gGhoDexCrashSessionStartedAt,
        reason,
        signalName,
        signalNumber
    );
    if (length <= 0) {
        return;
    }

    size_t writeLength = (size_t)MIN((int)sizeof(buffer), length);
    GhoDexWriteBufferToCrashMarker(buffer, writeLength);
}

static NSString *GhoDexSanitizeExceptionString(NSString *value) {
    if (value.length == 0) {
        return @"";
    }

    NSString *collapsed = [[value stringByReplacingOccurrencesOfString:@"\n" withString:@" "]
        stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    collapsed = [collapsed stringByReplacingOccurrencesOfString:@"=" withString:@":"];
    if (collapsed.length > 512) {
        return [collapsed substringToIndex:512];
    }
    return collapsed;
}

static void GhoDexWriteExceptionCrashMarker(NSException *exception) {
    if (gGhoDexCrashMarkerPath[0] == '\0' || exception == nil) {
        return;
    }

    NSString *content = [NSString stringWithFormat:
        @"schema_version=1\n"
        @"crash_kind=uncaught_exception\n"
        @"pid=%d\n"
        @"bundle_id=%s\n"
        @"executable_name=%s\n"
        @"session_id=%s\n"
        @"session_started_at=%s\n"
        @"reason=uncaught_exception\n"
        @"exception_name=%@\n"
        @"exception_reason=%@\n",
        gGhoDexCrashPID,
        gGhoDexCrashBundleID,
        gGhoDexCrashExecutableName,
        gGhoDexCrashSessionID,
        gGhoDexCrashSessionStartedAt,
        GhoDexSanitizeExceptionString(exception.name ?: @""),
        GhoDexSanitizeExceptionString(exception.reason ?: @"")
    ];
    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
    if (data.length == 0) {
        return;
    }

    GhoDexWriteBufferToCrashMarker(data.bytes, data.length);
}

static void GhoDexFatalSignalHandler(int signalNumber) {
    GhoDexWriteSignalCrashMarker(signalNumber);

    struct sigaction defaultAction;
    memset(&defaultAction, 0, sizeof(defaultAction));
    defaultAction.sa_handler = SIG_DFL;
    sigemptyset(&defaultAction.sa_mask);
    sigaction(signalNumber, &defaultAction, NULL);
    kill(getpid(), signalNumber);
}

static void GhoDexUncaughtExceptionHandler(NSException *exception) {
    GhoDexWriteExceptionCrashMarker(exception);
}

static void GhoDexInstallFatalSignalHandler(int signalNumber) {
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = GhoDexFatalSignalHandler;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_RESETHAND | SA_NODEFER;
    sigaction(signalNumber, &action, NULL);
}

BOOL GhosttyAddTabbedWindowSafely(
    id parent,
    id child,
    NSInteger ordered,
    NSError * _Nullable * _Nullable error
) {
    // AppKit occasionally throws NSException while adding tabbed windows,
    // in particular when creating tabs from the tab overview page since some
    // macOS update recently in 2025/2026 (unclear).
    //
    // We must catch it in Objective-C; letting this cross into Swift is unsafe.
    @try {
        [((NSWindow *)parent) addTabbedWindow:(NSWindow *)child ordered:(NSWindowOrderingMode)ordered];
        return YES;
    } @catch (NSException *exception) {
        if (error != NULL) {
            NSString *reason = exception.reason ?: @"Unknown Objective-C exception";
            *error = [NSError errorWithDomain:@"Ghostty.ObjCException"
                                         code:1
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: reason,
                                         @"exception_name": exception.name,
                                     }];
        }

        return NO;
    }
}

void GhoDexUpdateCrashDiagnosticsContext(
    const char *sessionID,
    const char *sessionStartedAt,
    int pid
) {
    GhoDexCopyCString(gGhoDexCrashSessionID, sizeof(gGhoDexCrashSessionID), sessionID);
    GhoDexCopyCString(gGhoDexCrashSessionStartedAt, sizeof(gGhoDexCrashSessionStartedAt), sessionStartedAt);
    gGhoDexCrashPID = pid;
}

void GhoDexInstallCrashDiagnosticsHandlers(
    const char *markerPath,
    const char *bundleID,
    const char *executableName,
    int pid,
    const char *sessionID,
    const char *sessionStartedAt
) {
    GhoDexCopyCString(gGhoDexCrashMarkerPath, sizeof(gGhoDexCrashMarkerPath), markerPath);
    GhoDexCopyCString(gGhoDexCrashBundleID, sizeof(gGhoDexCrashBundleID), bundleID);
    GhoDexCopyCString(gGhoDexCrashExecutableName, sizeof(gGhoDexCrashExecutableName), executableName);
    GhoDexUpdateCrashDiagnosticsContext(sessionID, sessionStartedAt, pid);

    if (gGhoDexCrashMarkerPath[0] != '\0') {
        NSString *marker = [NSString stringWithUTF8String:gGhoDexCrashMarkerPath];
        NSString *directory = [marker stringByDeletingLastPathComponent];
        if (directory.length > 0) {
            [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil];
        }
    }

    NSSetUncaughtExceptionHandler(&GhoDexUncaughtExceptionHandler);
    GhoDexInstallFatalSignalHandler(SIGABRT);
    GhoDexInstallFatalSignalHandler(SIGILL);
    GhoDexInstallFatalSignalHandler(SIGSEGV);
    GhoDexInstallFatalSignalHandler(SIGBUS);
    GhoDexInstallFatalSignalHandler(SIGFPE);
    GhoDexInstallFatalSignalHandler(SIGTRAP);
}
