#import "GhoDexApplication.h"

@interface GhoDexApplication ()
@property(nonatomic, assign, getter=isHandlingSendEvent) BOOL handlingSendEvent;
@end

@implementation GhoDexApplication

- (void)sendEvent:(NSEvent *)event {
    BOOL wasHandlingSendEvent = self.handlingSendEvent;
    self.handlingSendEvent = YES;
    @try {
        [super sendEvent:event];
    } @finally {
        self.handlingSendEvent = wasHandlingSendEvent;
    }
}

@end
