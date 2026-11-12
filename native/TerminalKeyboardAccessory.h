#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Name of the WKScriptMessageHandler keyboard_accessory.js reports modifier state to.
extern NSString *const KeyboardAccessoryMessageName;

/// Terminal key bar (esc, ctrl, tab, arrows, ...) shown above the software keyboard.
@interface TerminalKeyboardAccessory : UIInputView

/// Replaces the web view's form accessory bar with a TerminalKeyboardAccessory.
+ (void)installOnWebView:(WKWebView *)webView;

+ (nullable TerminalKeyboardAccessory *)accessoryForWebView:(WKWebView *)webView;

/// Adds the key event script and modifier state message handler to a configuration.
+ (void)prepareConfiguration:(WKWebViewConfiguration *)configuration;

- (void)setControlActive:(BOOL)controlActive;

@end

NS_ASSUME_NONNULL_END
