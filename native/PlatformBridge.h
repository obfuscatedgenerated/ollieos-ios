#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Native side of IOSPlatformAPI. Only the root web view's OllieOS page can call it, and only with the
/// token it claimed at boot, so programs have to go through the kernel's platform API.
@interface PlatformBridge : NSObject <WKScriptMessageHandlerWithReply>

+ (instancetype)sharedBridge;

/// Adds the token handoff script and the message handler. Call once on the root configuration.
- (void)installOnConfiguration:(WKWebViewConfiguration *)configuration;

/// The only web view allowed to call the bridge.
@property (nonatomic, weak, nullable) WKWebView *rootWebView;

/// Shows notifications while the app is in the foreground. Call at launch.
- (void)registerNotificationPresentation;

@end

NS_ASSUME_NONNULL_END
