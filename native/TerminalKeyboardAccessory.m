#import "TerminalKeyboardAccessory.h"
#import <objc/runtime.h>

NSString *const KeyboardAccessoryMessageName = @"ollieosKeyboard";

static const CGFloat AccessoryBarHeight = 46.0;
static const CGFloat KeyHeight = 34.0;
static const CGFloat KeyMinimumWidth = 42.0;
static const CGFloat KeySpacing = 6.0;
static const NSTimeInterval KeyRepeatDelay = 0.4;
static const NSTimeInterval KeyRepeatInterval = 0.07;

static char AccessoryAssociationKey;

#pragma mark - Content view accessory override

// the keyboard's first responder is WKWebView's private WKContentView, so its inputAccessoryView is what
// ios shows. we give that one instance a runtime subclass whose inputAccessoryView returns our bar
static UIView *ContentViewInputAccessoryView(id contentView, SEL selector) {
    UIView *ancestorView = [(UIView *)contentView superview];
    while (ancestorView != nil && ![ancestorView isKindOfClass:[WKWebView class]]) {
        ancestorView = ancestorView.superview;
    }
    if (ancestorView == nil) {
        return nil;
    }
    return objc_getAssociatedObject(ancestorView, &AccessoryAssociationKey);
}

static UIView *FindContentView(WKWebView *webView) {
    for (UIView *subview in webView.scrollView.subviews) {
        if ([NSStringFromClass([subview class]) hasPrefix:@"WKContent"]) {
            return subview;
        }
    }
    return nil;
}

static Class AccessorySubclassForClass(Class contentViewClass) {
    NSString *subclassName = [NSString stringWithFormat:@"OllieOSAccessory_%@", NSStringFromClass(contentViewClass)];
    Class existingSubclass = NSClassFromString(subclassName);
    if (existingSubclass != nil) {
        return existingSubclass;
    }

    Class accessorySubclass = objc_allocateClassPair(contentViewClass, subclassName.UTF8String, 0);
    if (accessorySubclass == nil) {
        return nil;
    }
    class_addMethod(accessorySubclass, @selector(inputAccessoryView), (IMP)ContentViewInputAccessoryView, "@@:");
    objc_registerClassPair(accessorySubclass);
    return accessorySubclass;
}

#pragma mark - Script message handler

@interface KeyboardAccessoryMessageHandler : NSObject <WKScriptMessageHandler>
@end

@implementation KeyboardAccessoryMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.body isKindOfClass:[NSDictionary class]] || message.webView == nil) {
        return;
    }
    NSDictionary *modifierState = message.body;
    TerminalKeyboardAccessory *accessory = [TerminalKeyboardAccessory accessoryForWebView:message.webView];
    [accessory setControlActive:[modifierState[@"ctrl"] boolValue]];
}

@end

#pragma mark - Key button

@interface AccessoryKeyButton : UIButton
@property (nonatomic, copy) NSString *keyName;
@property (nonatomic, assign) BOOL repeatsWhileHeld;
@property (nonatomic, assign) BOOL isModifier;
@property (nonatomic, assign) BOOL modifierActive;
@end

@implementation AccessoryKeyButton

+ (UIColor *)keyBackgroundColor {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:0.42 alpha:1.0]
            : [UIColor whiteColor];
    }];
}

+ (UIColor *)keyPressedColor {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:0.28 alpha:1.0]
            : [UIColor colorWithWhite:0.72 alpha:1.0];
    }];
}

- (void)refreshAppearance {
    if (self.isModifier && self.modifierActive) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.tintColor = [UIColor whiteColor];
        [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    } else {
        self.backgroundColor = self.highlighted ? [AccessoryKeyButton keyPressedColor] : [AccessoryKeyButton keyBackgroundColor];
        self.tintColor = [UIColor labelColor];
        [self setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    }
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [self refreshAppearance];
}

- (void)setModifierActive:(BOOL)modifierActive {
    _modifierActive = modifierActive;
    [self refreshAppearance];
}

@end

#pragma mark - Key scroll view

@interface AccessoryKeyScrollView : UIScrollView
@end

@implementation AccessoryKeyScrollView

// UIScrollView refuses to cancel touches in UIControls by default, so a drag that starts on a key
// never becomes a scroll. allow it, the key then gets TouchCancel and sends nothing
- (BOOL)touchesShouldCancelInContentView:(UIView *)view {
    return YES;
}

@end

#pragma mark - Accessory bar

@interface TerminalKeyboardAccessory ()
@property (nonatomic, weak) WKWebView *webView;
@property (nonatomic, strong) AccessoryKeyButton *controlButton;
@property (nonatomic, strong) NSTimer *repeatTimer;
@property (nonatomic, assign) BOOL repeatStarted;
@property (nonatomic, strong) UIImpactFeedbackGenerator *feedbackGenerator;
@end

@implementation TerminalKeyboardAccessory

+ (void)prepareConfiguration:(WKWebViewConfiguration *)configuration {
    NSString *scriptPath = [[NSBundle mainBundle] pathForResource:@"keyboard_accessory" ofType:@"js"];
    NSString *scriptSource = [NSString stringWithContentsOfFile:scriptPath encoding:NSUTF8StringEncoding error:nil];
    if (scriptSource == nil) {
        return;
    }

    WKUserScript *keyboardScript = [[WKUserScript alloc] initWithSource:scriptSource
                                                          injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                       forMainFrameOnly:NO];
    [configuration.userContentController addUserScript:keyboardScript];
    [configuration.userContentController addScriptMessageHandler:[[KeyboardAccessoryMessageHandler alloc] init]
                                                            name:KeyboardAccessoryMessageName];
}

+ (void)installOnWebView:(WKWebView *)webView {
    UIView *contentView = FindContentView(webView);
    if (contentView == nil) {
        return;
    }

    Class accessorySubclass = AccessorySubclassForClass([contentView class]);
    if (accessorySubclass == nil) {
        return;
    }

    TerminalKeyboardAccessory *accessory = [[TerminalKeyboardAccessory alloc] initWithWebView:webView];
    objc_setAssociatedObject(webView, &AccessoryAssociationKey, accessory, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if ([contentView class] != accessorySubclass) {
        object_setClass(contentView, accessorySubclass);
    }
}

+ (TerminalKeyboardAccessory *)accessoryForWebView:(WKWebView *)webView {
    return objc_getAssociatedObject(webView, &AccessoryAssociationKey);
}

- (instancetype)initWithWebView:(WKWebView *)webView {
    CGRect barFrame = CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, AccessoryBarHeight);
    self = [super initWithFrame:barFrame inputViewStyle:UIInputViewStyleKeyboard];
    if (self) {
        _webView = webView;
        _feedbackGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        self.allowsSelfSizing = NO;
        [self buildLayout];
    }
    return self;
}

- (void)buildLayout {
    AccessoryKeyScrollView *keyScrollView = [[AccessoryKeyScrollView alloc] init];
    keyScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    keyScrollView.showsHorizontalScrollIndicator = NO;
    keyScrollView.alwaysBounceHorizontal = YES;
    // hold back touch-down briefly so a quick swipe is claimed by the scroll view, not the key under it
    keyScrollView.delaysContentTouches = YES;
    keyScrollView.canCancelContentTouches = YES;
    [self addSubview:keyScrollView];

    UIStackView *keyStack = [[UIStackView alloc] init];
    keyStack.translatesAutoresizingMaskIntoConstraints = NO;
    keyStack.axis = UILayoutConstraintAxisHorizontal;
    keyStack.spacing = KeySpacing;
    keyStack.alignment = UIStackViewAlignmentCenter;
    [keyScrollView addSubview:keyStack];

    self.controlButton = [self modifierButtonWithTitle:@"ctrl"];

    NSMutableArray<UIView *> *keyButtons = [@[
        [self keyButtonWithTitle:@"esc" keyName:@"escape" repeats:NO],
        self.controlButton,
        [self keyButtonWithTitle:@"tab" keyName:@"tab" repeats:NO],
        [self keyButtonWithSymbol:@"arrow.left" keyName:@"left"],
        [self keyButtonWithSymbol:@"arrow.up" keyName:@"up"],
        [self keyButtonWithSymbol:@"arrow.down" keyName:@"down"],
        [self keyButtonWithSymbol:@"arrow.right" keyName:@"right"],
        [self keyButtonWithTitle:@"|" keyName:@"pipe" repeats:NO],
        [self keyButtonWithTitle:@"~" keyName:@"tilde" repeats:NO],
        [self keyButtonWithTitle:@"/" keyName:@"slash" repeats:NO],
        [self keyButtonWithTitle:@"-" keyName:@"dash" repeats:YES],
        [self keyButtonWithTitle:@"home" keyName:@"home" repeats:NO],
        [self keyButtonWithTitle:@"end" keyName:@"end" repeats:NO],
        [self keyButtonWithTitle:@"pg up" keyName:@"pageup" repeats:YES],
        [self keyButtonWithTitle:@"pg dn" keyName:@"pagedown" repeats:YES],
    ] mutableCopy];

    for (NSInteger functionNumber = 1; functionNumber <= 12; functionNumber++) {
        [keyButtons addObject:[self keyButtonWithTitle:[NSString stringWithFormat:@"F%ld", (long)functionNumber]
                                               keyName:[NSString stringWithFormat:@"f%ld", (long)functionNumber]
                                               repeats:NO]];
    }

    for (UIView *keyButton in keyButtons) {
        [keyStack addArrangedSubview:keyButton];
    }

    UIButton *dismissButton = [UIButton buttonWithType:UIButtonTypeSystem];
    dismissButton.translatesAutoresizingMaskIntoConstraints = NO;
    [dismissButton setImage:[UIImage systemImageNamed:@"keyboard.chevron.compact.down"] forState:UIControlStateNormal];
    dismissButton.tintColor = [UIColor labelColor];
    dismissButton.accessibilityLabel = @"Hide keyboard";
    [dismissButton addTarget:self action:@selector(dismissKeyboard) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:dismissButton];

    UILayoutGuide *safeArea = self.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [keyScrollView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor],
        [keyScrollView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [keyScrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [keyScrollView.trailingAnchor constraintEqualToAnchor:dismissButton.leadingAnchor],

        [dismissButton.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor constant:-4],
        [dismissButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [dismissButton.widthAnchor constraintEqualToConstant:44],
        [dismissButton.heightAnchor constraintEqualToConstant:AccessoryBarHeight],

        [keyStack.leadingAnchor constraintEqualToAnchor:keyScrollView.contentLayoutGuide.leadingAnchor constant:KeySpacing],
        [keyStack.trailingAnchor constraintEqualToAnchor:keyScrollView.contentLayoutGuide.trailingAnchor constant:-KeySpacing],
        [keyStack.topAnchor constraintEqualToAnchor:keyScrollView.contentLayoutGuide.topAnchor],
        [keyStack.bottomAnchor constraintEqualToAnchor:keyScrollView.contentLayoutGuide.bottomAnchor],
        [keyStack.heightAnchor constraintEqualToAnchor:keyScrollView.frameLayoutGuide.heightAnchor],
    ]];
}

#pragma mark Button factories

- (AccessoryKeyButton *)baseKeyButton {
    AccessoryKeyButton *keyButton = [AccessoryKeyButton buttonWithType:UIButtonTypeCustom];
    keyButton.translatesAutoresizingMaskIntoConstraints = NO;
    keyButton.layer.cornerRadius = 6.0;
    keyButton.layer.shadowColor = [UIColor blackColor].CGColor;
    keyButton.layer.shadowOffset = CGSizeMake(0, 1);
    keyButton.layer.shadowOpacity = 0.3;
    keyButton.layer.shadowRadius = 0;
    keyButton.titleLabel.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightMedium];
    keyButton.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 10);
    [keyButton refreshAppearance];

    [NSLayoutConstraint activateConstraints:@[
        [keyButton.heightAnchor constraintEqualToConstant:KeyHeight],
        [keyButton.widthAnchor constraintGreaterThanOrEqualToConstant:KeyMinimumWidth],
    ]];
    return keyButton;
}

- (AccessoryKeyButton *)keyButtonWithTitle:(NSString *)title keyName:(NSString *)keyName repeats:(BOOL)repeats {
    AccessoryKeyButton *keyButton = [self baseKeyButton];
    [keyButton setTitle:title forState:UIControlStateNormal];
    keyButton.accessibilityLabel = keyName;
    keyButton.keyName = keyName;
    keyButton.repeatsWhileHeld = repeats;
    [self attachKeyPressHandlers:keyButton];
    return keyButton;
}

- (AccessoryKeyButton *)keyButtonWithSymbol:(NSString *)symbolName keyName:(NSString *)keyName {
    AccessoryKeyButton *keyButton = [self baseKeyButton];
    UIImageSymbolConfiguration *symbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightMedium];
    [keyButton setImage:[UIImage systemImageNamed:symbolName withConfiguration:symbolConfiguration] forState:UIControlStateNormal];
    keyButton.adjustsImageWhenHighlighted = NO;
    keyButton.accessibilityLabel = keyName;
    keyButton.keyName = keyName;
    keyButton.repeatsWhileHeld = YES;
    [self attachKeyPressHandlers:keyButton];
    return keyButton;
}

- (AccessoryKeyButton *)modifierButtonWithTitle:(NSString *)title {
    AccessoryKeyButton *modifierButton = [self baseKeyButton];
    [modifierButton setTitle:title forState:UIControlStateNormal];
    modifierButton.accessibilityLabel = title;
    modifierButton.isModifier = YES;
    [modifierButton addTarget:self action:@selector(toggleControl) forControlEvents:UIControlEventTouchUpInside];
    return modifierButton;
}

- (void)attachKeyPressHandlers:(AccessoryKeyButton *)keyButton {
    [keyButton addTarget:self action:@selector(keyTouchDown:) forControlEvents:UIControlEventTouchDown];
    [keyButton addTarget:self action:@selector(keyTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];
    [keyButton addTarget:self
                  action:@selector(keyTouchAbandoned:)
        forControlEvents:UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
}

#pragma mark Actions

// keys send on release (like the system keyboard) so a drag that turns into a scroll sends nothing.
// held repeat keys start sending after KeyRepeatDelay instead, and then skip the send on release
- (void)keyTouchDown:(AccessoryKeyButton *)keyButton {
    [self.feedbackGenerator impactOccurred];
    [self stopRepeating];

    if (!keyButton.repeatsWhileHeld) {
        return;
    }

    __weak TerminalKeyboardAccessory *weakSelf = self;
    NSString *heldKeyName = keyButton.keyName;
    self.repeatTimer = [NSTimer scheduledTimerWithTimeInterval:KeyRepeatDelay repeats:NO block:^(NSTimer *delayTimer) {
        weakSelf.repeatStarted = YES;
        [weakSelf sendKeyNamed:heldKeyName];
        weakSelf.repeatTimer = [NSTimer scheduledTimerWithTimeInterval:KeyRepeatInterval repeats:YES block:^(NSTimer *intervalTimer) {
            [weakSelf sendKeyNamed:heldKeyName];
        }];
    }];
}

- (void)keyTouchUpInside:(AccessoryKeyButton *)keyButton {
    if (!self.repeatStarted) {
        [self sendKeyNamed:keyButton.keyName];
    }
    [self stopRepeating];
}

- (void)keyTouchAbandoned:(AccessoryKeyButton *)keyButton {
    [self stopRepeating];
}

- (void)stopRepeating {
    [self.repeatTimer invalidate];
    self.repeatTimer = nil;
    self.repeatStarted = NO;
}

- (void)sendKeyNamed:(NSString *)keyName {
    // key names are fixed constants from buildLayout, so interpolating them into the script is safe
    NSString *script = [NSString stringWithFormat:@"window.__ollieosKeyboard && window.__ollieosKeyboard.pressKey('%@')", keyName];
    [self.webView evaluateJavaScript:script completionHandler:nil];
}

- (void)toggleControl {
    [self.feedbackGenerator impactOccurred];
    BOOL newControlState = !self.controlButton.modifierActive;
    [self setControlActive:newControlState];

    NSString *script = [NSString stringWithFormat:@"window.__ollieosKeyboard && window.__ollieosKeyboard.setModifier('ctrl', %@)",
                                                  newControlState ? @"true" : @"false"];
    [self.webView evaluateJavaScript:script completionHandler:nil];
}

- (void)setControlActive:(BOOL)controlActive {
    self.controlButton.modifierActive = controlActive;
}

- (void)dismissKeyboard {
    [self.repeatTimer invalidate];
    [self.webView endEditing:YES];
}

@end
