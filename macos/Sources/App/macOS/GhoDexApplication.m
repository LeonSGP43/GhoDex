#import "GhoDexApplication.h"

@interface GhoDexApplication ()
@property(nonatomic, assign, getter=isHandlingSendEvent) BOOL handlingSendEvent;
@end

static BOOL GhoDexShouldAttemptMenuKeyEquivalentFallback(NSEvent *event, BOOL isHandlingSendEvent) {
    if (isHandlingSendEvent) return NO;
    if (event.type != NSEventTypeKeyDown) return NO;

    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    return (flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) != 0;
}

@implementation GhoDexApplication

- (void)sendEvent:(NSEvent *)event {
    BOOL wasHandlingSendEvent = self.handlingSendEvent;

    if (GhoDexShouldAttemptMenuKeyEquivalentFallback(event, wasHandlingSendEvent)) {
        NSMenu *mainMenu = self.mainMenu;
        if (mainMenu != nil && [mainMenu performKeyEquivalent:event]) {
            return;
        }
    }

    self.handlingSendEvent = YES;
    @try {
        [super sendEvent:event];
    } @finally {
        self.handlingSendEvent = wasHandlingSendEvent;
    }
}

@end
