#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol GhoDexCEFViewDelegate;

FOUNDATION_EXPORT int GhoDexCEFExecuteProcessIfNeeded(void);
FOUNDATION_EXPORT BOOL GhoDexCEFInitializeGlobal(void);
FOUNDATION_EXPORT void GhoDexCEFShutdownGlobal(void);
FOUNDATION_EXPORT BOOL GhoDexCEFBuildSupportsManagedRuntime(void);
FOUNDATION_EXPORT BOOL GhoDexCEFBuildHasRuntime(void);
FOUNDATION_EXPORT BOOL GhoDexCEFIsInitialized(void);
FOUNDATION_EXPORT NSString * _Nullable GhoDexCEFConfiguredProfileDirectoryName(void);
FOUNDATION_EXPORT NSString * const GhoDexCEFControlErrorDomain;

typedef NS_ENUM(NSInteger, GhoDexCEFControlErrorCode) {
    GhoDexCEFControlErrorCodeBridgeUnavailable = 1,
    GhoDexCEFControlErrorCodeEvaluationUnavailable = 2,
    GhoDexCEFControlErrorCodeEvaluationFailed = 3,
};

typedef void (^GhoDexCEFJavaScriptEvaluationCompletion)(NSString * _Nullable resultJSON, NSError * _Nullable error);

@interface GhoDexCEFView : NSView
@property(nonatomic, weak, nullable) id<GhoDexCEFViewDelegate> delegate;
- (instancetype)initWithInitialURLString:(NSString *)initialURLString NS_DESIGNATED_INITIALIZER;
- (void)loadURLString:(NSString *)urlString;
- (void)goBack;
- (void)goForward;
- (void)reloadPage;
- (void)executeJavaScript:(NSString *)javaScript;
- (void)evaluateJavaScript:(NSString *)javaScript completion:(GhoDexCEFJavaScriptEvaluationCompletion)completion;
@end

@protocol GhoDexCEFViewDelegate <NSObject>
- (void)cefViewDidBecomeReady:(GhoDexCEFView *)view;
- (void)cefView:(GhoDexCEFView *)view didUpdateTitle:(NSString *)title;
- (void)cefView:(GhoDexCEFView *)view
    didUpdateURL:(NSString *)url
       canGoBack:(BOOL)canGoBack
    canGoForward:(BOOL)canGoForward
       isLoading:(BOOL)isLoading;
- (void)cefView:(GhoDexCEFView *)view
    didReceiveConsoleMessage:(NSString *)message
                       level:(NSString *)level
                      source:(NSString *)source
                        line:(NSInteger)line;
- (void)cefView:(GhoDexCEFView *)view requestOpenURLInNewTab:(NSString *)urlString;
@end

NS_ASSUME_NONNULL_END
