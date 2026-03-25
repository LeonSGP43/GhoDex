#import <AppKit/AppKit.h>

@interface GhoDexApplication : NSApplication
- (BOOL)isHandlingSendEvent;
- (void)setHandlingSendEvent:(BOOL)handlingSendEvent;
@end
