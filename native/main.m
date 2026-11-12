#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <SafariServices/SafariServices.h>
#import "TerminalKeyboardAccessory.h"
#import "PlatformBridge.h"

static NSString *const AppScheme = @"ollieos";
static NSString *const AppHost = @"app";

#pragma mark - Bundled site scheme handler

@interface BundledSiteSchemeHandler : NSObject <WKURLSchemeHandler>
@property (nonatomic, strong) NSString *siteRootPath;
@end

@implementation BundledSiteSchemeHandler

- (instancetype)init {
    self = [super init];
    if (self) {
        // standardise here too: stringByStandardizingPath strips the /private prefix from the bundle path,
        // so an unstandardised root never matches the candidate path and everything 404s
        _siteRootPath = [[[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:@"www"] stringByStandardizingPath];
    }
    return self;
}

- (NSString *)mimeTypeForExtension:(NSString *)extension {
    static NSDictionary<NSString *, NSString *> *mimeTypes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mimeTypes = @{
            @"html": @"text/html",
            @"htm": @"text/html",
            @"js": @"text/javascript",
            @"mjs": @"text/javascript",
            @"css": @"text/css",
            @"json": @"application/json",
            @"map": @"application/json",
            @"txt": @"text/plain",
            @"svg": @"image/svg+xml",
            @"png": @"image/png",
            @"jpg": @"image/jpeg",
            @"jpeg": @"image/jpeg",
            @"gif": @"image/gif",
            @"ico": @"image/x-icon",
            @"webp": @"image/webp",
            @"mp3": @"audio/mpeg",
            @"wav": @"audio/wav",
            @"ogg": @"audio/ogg",
            @"ttf": @"font/ttf",
            @"woff": @"font/woff",
            @"woff2": @"font/woff2",
            @"wasm": @"application/wasm",
        };
    });
    return mimeTypes[extension.lowercaseString] ?: @"application/octet-stream";
}

- (NSString *)resolveFilePathForRequestPath:(NSString *)requestPath {
    NSString *decodedPath = requestPath.stringByRemovingPercentEncoding ?: requestPath;
    if (decodedPath.length == 0) {
        decodedPath = @"/";
    }

    NSString *candidatePath = [[self.siteRootPath stringByAppendingPathComponent:decodedPath] stringByStandardizingPath];

    // refuse anything that escapes the bundled site directory
    BOOL isSiteRoot = [candidatePath isEqualToString:self.siteRootPath];
    BOOL isInsideSiteRoot = [candidatePath hasPrefix:[self.siteRootPath stringByAppendingString:@"/"]];
    if (!isSiteRoot && !isInsideSiteRoot) {
        return nil;
    }

    BOOL isDirectory = NO;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:candidatePath isDirectory:&isDirectory]) {
        if (!isDirectory) {
            return candidatePath;
        }
        NSString *indexPath = [candidatePath stringByAppendingPathComponent:@"index.html"];
        if ([fileManager fileExistsAtPath:indexPath]) {
            return indexPath;
        }
    }

    // mirror github pages: /page resolves to /page.html
    NSString *htmlPath = [candidatePath stringByAppendingPathExtension:@"html"];
    if ([fileManager fileExistsAtPath:htmlPath]) {
        return htmlPath;
    }

    return nil;
}

- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
    NSURL *requestURL = urlSchemeTask.request.URL;
    NSString *filePath = [self resolveFilePathForRequestPath:requestURL.path];
    NSInteger statusCode = 200;

    if (filePath == nil) {
        statusCode = 404;
        filePath = [self.siteRootPath stringByAppendingPathComponent:@"404.html"];
    }

    NSData *fileData = [NSData dataWithContentsOfFile:filePath] ?: [NSData data];
    NSString *mimeType = [self mimeTypeForExtension:filePath.pathExtension];
    if ([mimeType hasPrefix:@"text/"] || [mimeType isEqualToString:@"application/json"]) {
        mimeType = [mimeType stringByAppendingString:@"; charset=utf-8"];
    }

    NSDictionary *headers = @{
        @"Content-Type": mimeType,
        @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)fileData.length],
        @"Cache-Control": @"no-cache",
        @"Access-Control-Allow-Origin": @"*",
    };

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:requestURL
                                                              statusCode:statusCode
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:headers];
    [urlSchemeTask didReceiveResponse:response];
    [urlSchemeTask didReceiveData:fileData];
    [urlSchemeTask didFinish];
}

- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
}

@end

#pragma mark - Web view controller

@interface WebViewController : UIViewController <WKNavigationDelegate, WKUIDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) WKWebViewConfiguration *providedConfiguration;
@end

@implementation WebViewController

- (instancetype)initWithConfiguration:(WKWebViewConfiguration *)configuration {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _providedConfiguration = configuration;
    }
    return self;
}

+ (WKWebViewConfiguration *)rootConfiguration {
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    [configuration setURLSchemeHandler:[[BundledSiteSchemeHandler alloc] init] forURLScheme:AppScheme];
    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    configuration.allowsInlineMediaPlayback = YES;
    configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = YES;
    [TerminalKeyboardAccessory prepareConfiguration:configuration];
    [[PlatformBridge sharedBridge] installOnConfiguration:configuration];
    return configuration;
}

- (void)loadView {
    WKWebViewConfiguration *configuration = self.providedConfiguration ?: [WebViewController rootConfiguration];
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    [TerminalKeyboardAccessory installOnWebView:self.webView];
    if (self.providedConfiguration == nil) {
        // only the root web view (the one running the kernel) may use the platform bridge
        [PlatformBridge sharedBridge].rootWebView = self.webView;
    }
    self.webView.allowsBackForwardNavigationGestures = NO;
    self.webView.scrollView.bounces = NO;
    self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.webView.opaque = NO;
    self.webView.backgroundColor = [UIColor blackColor];
    // respondsToSelector rather than @available, which needs compiler-rt (not shipped for ios on linux)
    if ([self.webView respondsToSelector:@selector(setInspectable:)]) {
        [self.webView setValue:@YES forKey:@"inspectable"];
    }
    self.view = [[UIView alloc] init];
    self.view.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.webView];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // keep the terminal clear of the notch and home indicator
    self.webView.frame = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (self.providedConfiguration == nil) {
        NSString *startURLString = [NSString stringWithFormat:@"%@://%@/", AppScheme, AppHost];
        [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:startURLString]]];
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (BOOL)isBundledURL:(NSURL *)url {
    NSString *scheme = url.scheme.lowercaseString;
    return [scheme isEqualToString:AppScheme] || [scheme isEqualToString:@"about"]
        || [scheme isEqualToString:@"blob"] || [scheme isEqualToString:@"data"];
}

- (void)openExternally:(NSURL *)url {
    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
        SFSafariViewController *safariController = [[SFSafariViewController alloc] initWithURL:url];
        [self presentViewController:safariController animated:YES completion:nil];
    } else {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

#pragma mark WKNavigationDelegate

- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
                    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    BOOL isTopFrame = navigationAction.targetFrame == nil || navigationAction.targetFrame.isMainFrame;

    // subframes (fsedit iframe etc.) load freely; top-level navigation away from the app opens outside
    if (!isTopFrame || [self isBundledURL:url]) {
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }

    [self openExternally:url];
    decisionHandler(WKNavigationActionPolicyCancel);
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    [webView reload];
}

#pragma mark WKUIDelegate

- (WKWebView *)webView:(WKWebView *)webView
    createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
               forNavigationAction:(WKNavigationAction *)navigationAction
                    windowFeatures:(WKWindowFeatures *)windowFeatures {
    NSURL *url = navigationAction.request.URL;

    if (url != nil && url.absoluteString.length > 0 && ![self isBundledURL:url]) {
        [self openExternally:url];
        return nil;
    }

    WebViewController *popupController = [[WebViewController alloc] initWithConfiguration:configuration];
    popupController.modalPresentationStyle = UIModalPresentationFullScreen;
    [popupController loadViewIfNeeded];
    [self presentViewController:popupController animated:YES completion:nil];
    return popupController.webView;
}

- (void)webViewDidClose:(WKWebView *)webView {
    if (self.providedConfiguration != nil) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)webView:(WKWebView *)webView
    runJavaScriptAlertPanelWithMessage:(NSString *)message
                      initiatedByFrame:(WKFrameInfo *)frame
                     completionHandler:(void (^)(void))completionHandler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        completionHandler();
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView
    runJavaScriptConfirmPanelWithMessage:(NSString *)message
                        initiatedByFrame:(WKFrameInfo *)frame
                       completionHandler:(void (^)(BOOL))completionHandler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        completionHandler(NO);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        completionHandler(YES);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView
    runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
                              defaultText:(NSString *)defaultText
                         initiatedByFrame:(WKFrameInfo *)frame
                        completionHandler:(void (^)(NSString *))completionHandler {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:prompt preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = defaultText;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        completionHandler(nil);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        completionHandler(alert.textFields.firstObject.text);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - App delegate

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor blackColor];
    [[PlatformBridge sharedBridge] registerNotificationPresentation];
    self.window.rootViewController = [[WebViewController alloc] initWithConfiguration:nil];
    [self.window makeKeyAndVisible];
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
