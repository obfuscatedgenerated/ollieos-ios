#import "PlatformBridge.h"

#import <objc/message.h>
#import <sys/utsname.h>

#import <AVFoundation/AVFoundation.h>
#import <Contacts/Contacts.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import <EventKit/EventKit.h>
#import <GameController/GameController.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import <Network/Network.h>
#import <PhotosUI/PhotosUI.h>
#import <Security/Security.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <UserNotifications/UserNotifications.h>

static NSString *const PlatformMessageHandlerName = @"ollieosPlatform";
static NSString *const PlatformSchemeName = @"ollieos";
static NSString *const KeychainServiceName = @"ollieos.platform";
static const NSTimeInterval MotionSampleTimeout = 2.0;

typedef void (^PlatformReply)(id _Nullable result, NSString *_Nullable errorMessage);
typedef void (^CapabilityHandler)(NSDictionary *args, PlatformReply reply);

#pragma mark - Argument helpers

static NSString *StringArgument(NSDictionary *args, NSString *key) {
    id value = args[key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSNumber *NumberArgument(NSDictionary *args, NSString *key) {
    id value = args[key];
    return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

static id NullIfNil(id value) {
    return value ?: [NSNull null];
}

static NSString *SafeFileName(NSString *requestedName) {
    NSString *fileName = [requestedName.lastPathComponent stringByReplacingOccurrencesOfString:@":" withString:@"_"];
    return fileName.length > 0 ? fileName : @"file";
}

static NSString *ISODateString(NSDate *date) {
    static NSISO8601DateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSISO8601DateFormatter alloc] init];
    });
    return date ? [formatter stringFromDate:date] : nil;
}

static NSDate *DateFromISOString(NSString *dateString) {
    if (dateString == nil) {
        return nil;
    }

    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    NSDate *parsedDate = [formatter dateFromString:dateString];
    if (parsedDate == nil) {
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
        parsedDate = [formatter dateFromString:dateString];
    }
    return parsedDate;
}

static NSDictionary *VectorDictionary(double xValue, double yValue, double zValue) {
    return @{ @"x": @(xValue), @"y": @(yValue), @"z": @(zValue) };
}

#pragma mark - Picker delegate helpers

@interface DocumentPickerHandler : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, copy) void (^onPick)(NSArray<NSURL *> *urls);
@property (nonatomic, copy) void (^onCancel)(void);
@end

@implementation DocumentPickerHandler

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    self.onPick(urls);
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    self.onCancel();
}

@end

@interface PhotoPickerHandler : NSObject <PHPickerViewControllerDelegate>
@property (nonatomic, copy) void (^onFinish)(NSArray<PHPickerResult *> *results);
@end

@implementation PhotoPickerHandler

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    self.onFinish(results);
}

@end

#pragma mark - Code scanner

@interface CodeScannerViewController : UIViewController <AVCaptureMetadataOutputObjectsDelegate>
@property (nonatomic, copy) void (^onFinish)(NSString *_Nullable scannedText, NSString *_Nullable codeType);
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, assign) BOOL finished;
@end

@implementation CodeScannerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    self.captureSession = [[AVCaptureSession alloc] init];
    AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDeviceInput *cameraInput = camera ? [AVCaptureDeviceInput deviceInputWithDevice:camera error:nil] : nil;
    if (cameraInput == nil || ![self.captureSession canAddInput:cameraInput]) {
        [self finishWithText:nil type:nil];
        return;
    }
    [self.captureSession addInput:cameraInput];

    AVCaptureMetadataOutput *metadataOutput = [[AVCaptureMetadataOutput alloc] init];
    if (![self.captureSession canAddOutput:metadataOutput]) {
        [self finishWithText:nil type:nil];
        return;
    }
    [self.captureSession addOutput:metadataOutput];
    [metadataOutput setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];

    NSArray<AVMetadataObjectType> *wantedTypes = @[
        AVMetadataObjectTypeQRCode, AVMetadataObjectTypeAztecCode, AVMetadataObjectTypeDataMatrixCode,
        AVMetadataObjectTypePDF417Code, AVMetadataObjectTypeEAN13Code, AVMetadataObjectTypeEAN8Code,
        AVMetadataObjectTypeCode128Code, AVMetadataObjectTypeCode39Code, AVMetadataObjectTypeUPCECode,
    ];
    NSMutableArray<AVMetadataObjectType> *supportedTypes = [NSMutableArray array];
    for (AVMetadataObjectType codeType in wantedTypes) {
        if ([metadataOutput.availableMetadataObjectTypes containsObject:codeType]) {
            [supportedTypes addObject:codeType];
        }
    }
    metadataOutput.metadataObjectTypes = supportedTypes;

    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer addSublayer:self.previewLayer];

    UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    cancelButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    cancelButton.tintColor = [UIColor whiteColor];
    cancelButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    cancelButton.layer.cornerRadius = 10;
    cancelButton.contentEdgeInsets = UIEdgeInsetsMake(8, 18, 8, 18);
    [cancelButton addTarget:self action:@selector(cancelScan) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:cancelButton];

    [NSLayoutConstraint activateConstraints:@[
        [cancelButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [cancelButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-24],
    ]];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self.captureSession startRunning];
    });
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.previewLayer.frame = self.view.bounds;
}

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)metadataObjects
              fromConnection:(AVCaptureConnection *)connection {
    for (AVMetadataObject *metadataObject in metadataObjects) {
        if ([metadataObject isKindOfClass:[AVMetadataMachineReadableCodeObject class]]) {
            AVMetadataMachineReadableCodeObject *codeObject = (AVMetadataMachineReadableCodeObject *)metadataObject;
            if (codeObject.stringValue != nil) {
                [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeSuccess];
                [self finishWithText:codeObject.stringValue type:codeObject.type];
                return;
            }
        }
    }
}

- (void)cancelScan {
    [self finishWithText:nil type:nil];
}

- (void)finishWithText:(NSString *)scannedText type:(NSString *)codeType {
    if (self.finished) {
        return;
    }
    self.finished = YES;

    AVCaptureSession *captureSession = self.captureSession;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [captureSession stopRunning];
    });

    void (^onFinish)(NSString *, NSString *) = self.onFinish;
    [self.presentingViewController dismissViewControllerAnimated:YES completion:^{
        onFinish(scannedText, codeType);
    }];
}

@end

#pragma mark - Bridge

@interface PlatformBridge () <CLLocationManagerDelegate, AVSpeechSynthesizerDelegate, UNUserNotificationCenterDelegate>
@property (nonatomic, copy) NSString *bridgeToken;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CapabilityHandler> *capabilityHandlers;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *capabilityDescriptors;

@property (nonatomic, strong) AVSpeechSynthesizer *speechSynthesizer;
@property (nonatomic, strong) NSMapTable<AVSpeechUtterance *, PlatformReply> *pendingSpeechReplies;

@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) NSMutableArray<PlatformReply> *pendingLocationReplies;

@property (nonatomic, strong) CMMotionManager *motionManager;

@property (nonatomic, strong, nullable) DocumentPickerHandler *activeDocumentPickerHandler;
@property (nonatomic, strong, nullable) PhotoPickerHandler *activePhotoPickerHandler;
@end

@implementation PlatformBridge

+ (instancetype)sharedBridge {
    static PlatformBridge *sharedBridge;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedBridge = [[PlatformBridge alloc] init];
    });
    return sharedBridge;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _bridgeToken = [NSUUID UUID].UUIDString;
        _capabilityHandlers = [NSMutableDictionary dictionary];
        _capabilityDescriptors = [NSMutableArray array];
        _pendingSpeechReplies = [NSMapTable strongToStrongObjectsMapTable];
        _pendingLocationReplies = [NSMutableArray array];
        [self registerCapabilities];
    }
    return self;
}

#pragma mark Installation

- (void)installOnConfiguration:(WKWebViewConfiguration *)configuration {
    NSDictionary *handoff = @{ @"token": self.bridgeToken, @"capabilities": self.capabilityDescriptors };
    NSData *handoffData = [NSJSONSerialization dataWithJSONObject:handoff options:0 error:nil];
    NSString *handoffJSON = [[NSString alloc] initWithData:handoffData encoding:NSUTF8StringEncoding];

    // the os loader claims this once at boot, before any program runs. popups (which have an opener) never get it
    NSString *handoffScript = [NSString stringWithFormat:
        @"(() => {\n"
         "    if (window.opener || window.top !== window) { return; }\n"
         "    const handoff = %@;\n"
         "    let claimed = false;\n"
         "    Object.defineProperty(window, \"__ollieos_claim_platform\", {\n"
         "        configurable: true,\n"
         "        value: () => {\n"
         "            delete window.__ollieos_claim_platform;\n"
         "            if (claimed) { return null; }\n"
         "            claimed = true;\n"
         "            return handoff;\n"
         "        },\n"
         "    });\n"
         "})();", handoffJSON];

    WKUserScript *userScript = [[WKUserScript alloc] initWithSource:handoffScript
                                                       injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                    forMainFrameOnly:YES];
    [configuration.userContentController addUserScript:userScript];
    [configuration.userContentController addScriptMessageHandlerWithReply:self
                                                             contentWorld:[WKContentWorld pageWorld]
                                                                     name:PlatformMessageHandlerName];
}

- (void)registerNotificationPresentation {
    [UNUserNotificationCenter currentNotificationCenter].delegate = self;
}

#pragma mark Message handling

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message
                 replyHandler:(void (^)(id _Nullable reply, NSString *_Nullable errorMessage))replyHandler {
    BOOL fromRootPage = message.webView != nil && message.webView == self.rootWebView && message.frameInfo.isMainFrame
        && [message.frameInfo.securityOrigin.protocol isEqualToString:PlatformSchemeName];
    if (!fromRootPage) {
        replyHandler(nil, @"Platform bridge is only available to the OllieOS kernel");
        return;
    }

    if (![message.body isKindOfClass:[NSDictionary class]]) {
        replyHandler(nil, @"Malformed platform request");
        return;
    }

    NSDictionary *request = message.body;
    if (![request[@"token"] isEqual:self.bridgeToken]) {
        replyHandler(nil, @"Platform bridge is only available to the OllieOS kernel");
        return;
    }

    NSString *capabilityName = StringArgument(request, @"capability");
    CapabilityHandler handler = capabilityName ? self.capabilityHandlers[capabilityName] : nil;
    if (handler == nil) {
        replyHandler(nil, [NSString stringWithFormat:@"Unknown platform capability \"%@\"", capabilityName]);
        return;
    }

    NSDictionary *args = [request[@"args"] isKindOfClass:[NSDictionary class]] ? request[@"args"] : @{};

    // wrap so a handler can never reply twice (webkit throws on that)
    __block BOOL replied = NO;
    handler(args, ^(id result, NSString *errorMessage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (replied) {
                return;
            }
            replied = YES;
            replyHandler(errorMessage ? nil : NullIfNil(result), errorMessage);
        });
    });
}

- (void)registerCapability:(NSString *)name privileged:(BOOL)privileged available:(BOOL)available handler:(CapabilityHandler)handler {
    if (!available) {
        return;
    }
    self.capabilityHandlers[name] = [handler copy];
    [self.capabilityDescriptors addObject:@{ @"name": name, @"privileged": @(privileged) }];
}

- (UIViewController *)topViewController {
    UIViewController *topController = self.rootWebView.window.rootViewController;
    while (topController.presentedViewController != nil) {
        topController = topController.presentedViewController;
    }
    return topController;
}

- (void)configurePopoverForController:(UIViewController *)controller {
    UIPopoverPresentationController *popover = controller.popoverPresentationController;
    if (popover == nil) {
        return;
    }
    UIView *sourceView = [self topViewController].view;
    popover.sourceView = sourceView;
    popover.sourceRect = CGRectMake(CGRectGetMidX(sourceView.bounds), CGRectGetMidY(sourceView.bounds), 1, 1);
    popover.permittedArrowDirections = 0;
}

- (NSURL *)writeTemporaryFileNamed:(NSString *)fileName data:(NSData *)fileData {
    NSString *directoryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *fileURL = [NSURL fileURLWithPath:[directoryPath stringByAppendingPathComponent:SafeFileName(fileName)]];
    return [fileData writeToURL:fileURL atomically:YES] ? fileURL : nil;
}

#pragma mark Capability registration

- (void)registerCapabilities {
    __weak PlatformBridge *weakSelf = self;

    BOOL hasCamera = [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera];
    AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    BOOL hasTorch = videoDevice != nil && videoDevice.hasTorch;
    BOOL canAuthenticate = [[[LAContext alloc] init] canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:nil];

    // ---------- userspace ----------

    [self registerCapability:@"haptic" privileged:NO available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        NSString *style = StringArgument(args, @"style") ?: @"light";
        NSDictionary<NSString *, NSNumber *> *impactStyles = @{
            @"light": @(UIImpactFeedbackStyleLight),
            @"medium": @(UIImpactFeedbackStyleMedium),
            @"heavy": @(UIImpactFeedbackStyleHeavy),
            @"soft": @(UIImpactFeedbackStyleSoft),
            @"rigid": @(UIImpactFeedbackStyleRigid),
        };
        NSDictionary<NSString *, NSNumber *> *notificationStyles = @{
            @"success": @(UINotificationFeedbackTypeSuccess),
            @"warning": @(UINotificationFeedbackTypeWarning),
            @"error": @(UINotificationFeedbackTypeError),
        };

        if (impactStyles[style] != nil) {
            [[[UIImpactFeedbackGenerator alloc] initWithStyle:impactStyles[style].integerValue] impactOccurred];
        } else if (notificationStyles[style] != nil) {
            [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:notificationStyles[style].integerValue];
        } else if ([style isEqualToString:@"selection"]) {
            [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
        } else {
            reply(nil, [NSString stringWithFormat:@"Unknown haptic style \"%@\"", style]);
            return;
        }
        reply(@{}, nil);
    }];

    [self registerCapability:@"share" privileged:NO available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        NSMutableArray *shareItems = [NSMutableArray array];

        NSString *text = StringArgument(args, @"text");
        if (text.length > 0) {
            [shareItems addObject:text];
        }

        NSURL *url = StringArgument(args, @"url") ? [NSURL URLWithString:StringArgument(args, @"url")] : nil;
        if (url != nil) {
            [shareItems addObject:url];
        }

        NSString *fileBase64 = StringArgument(args, @"file_base64");
        if (fileBase64 != nil) {
            NSData *fileData = [[NSData alloc] initWithBase64EncodedString:fileBase64 options:NSDataBase64DecodingIgnoreUnknownCharacters];
            NSURL *fileURL = fileData ? [weakSelf writeTemporaryFileNamed:StringArgument(args, @"file_name") ?: @"file" data:fileData] : nil;
            if (fileURL == nil) {
                reply(nil, @"Could not prepare the file for sharing");
                return;
            }
            [shareItems addObject:fileURL];
        }

        if (shareItems.count == 0) {
            reply(nil, @"Nothing to share, give text, a url or a file");
            return;
        }

        UIActivityViewController *activityController = [[UIActivityViewController alloc] initWithActivityItems:shareItems applicationActivities:nil];
        activityController.completionWithItemsHandler = ^(UIActivityType activityType, BOOL completed, NSArray *returnedItems, NSError *activityError) {
            reply(@{ @"completed": @(completed), @"activity": NullIfNil(activityType) }, nil);
        };
        [weakSelf configurePopoverForController:activityController];
        [[weakSelf topViewController] presentViewController:activityController animated:YES completion:nil];
    }];

    [self registerCapability:@"device_info" privileged:NO available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        struct utsname systemInfo;
        uname(&systemInfo);
        UIDevice *device = [UIDevice currentDevice];
        UIScreen *screen = [UIScreen mainScreen];
        NSString *idiom = device.userInterfaceIdiom == UIUserInterfaceIdiomPad ? @"pad" : @"phone";

        reply(@{
            @"model_identifier": [NSString stringWithUTF8String:systemInfo.machine],
            @"model": device.model,
            @"system_name": device.systemName,
            @"system_version": device.systemVersion,
            @"idiom": idiom,
            @"screen": @{
                @"width": @(screen.bounds.size.width),
                @"height": @(screen.bounds.size.height),
                @"scale": @(screen.scale),
            },
            @"locale": [NSLocale currentLocale].localeIdentifier,
            @"time_zone": [NSTimeZone localTimeZone].name,
            @"app_version": NullIfNil([NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"]),
        }, nil);
    }];

    [self registerCapability:@"battery" privileged:NO available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        UIDevice *device = [UIDevice currentDevice];
        device.batteryMonitoringEnabled = YES;

        NSDictionary<NSNumber *, NSString *> *stateNames = @{
            @(UIDeviceBatteryStateUnknown): @"unknown",
            @(UIDeviceBatteryStateUnplugged): @"unplugged",
            @(UIDeviceBatteryStateCharging): @"charging",
            @(UIDeviceBatteryStateFull): @"full",
        };

        float batteryLevel = device.batteryLevel;
        reply(@{
            @"level": batteryLevel < 0 ? [NSNull null] : @(batteryLevel),
            @"state": stateNames[@(device.batteryState)] ?: @"unknown",
            @"low_power_mode": @([NSProcessInfo processInfo].lowPowerModeEnabled),
        }, nil);
    }];

    [self registerCapability:@"thermal_state" privileged:NO available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        NSDictionary<NSNumber *, NSString *> *stateNames = @{
            @(NSProcessInfoThermalStateNominal): @"nominal",
            @(NSProcessInfoThermalStateFair): @"fair",
            @(NSProcessInfoThermalStateSerious): @"serious",
            @(NSProcessInfoThermalStateCritical): @"critical",
        };
        reply(@{ @"state": stateNames[@([NSProcessInfo processInfo].thermalState)] ?: @"unknown" }, nil);
    }];

    [self registerCapability:@"network_path" privileged:NO available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        nw_path_monitor_t pathMonitor = nw_path_monitor_create();
        nw_path_monitor_set_queue(pathMonitor, dispatch_get_main_queue());

        __block BOOL reported = NO;
        nw_path_monitor_set_update_handler(pathMonitor, ^(nw_path_t path) {
            if (reported) {
                return;
            }
            reported = YES;

            NSString *status = @"unsatisfied";
            if (nw_path_get_status(path) == nw_path_status_satisfied) {
                status = @"satisfied";
            } else if (nw_path_get_status(path) == nw_path_status_satisfiable) {
                status = @"requires_connection";
            }

            NSMutableArray<NSString *> *interfaces = [NSMutableArray array];
            if (nw_path_uses_interface_type(path, nw_interface_type_wifi)) {
                [interfaces addObject:@"wifi"];
            }
            if (nw_path_uses_interface_type(path, nw_interface_type_cellular)) {
                [interfaces addObject:@"cellular"];
            }
            if (nw_path_uses_interface_type(path, nw_interface_type_wired)) {
                [interfaces addObject:@"wired"];
            }
            if (nw_path_uses_interface_type(path, nw_interface_type_other)) {
                [interfaces addObject:@"other"];
            }

            reply(@{
                @"status": status,
                @"interfaces": interfaces,
                @"expensive": @(nw_path_is_expensive(path)),
                @"constrained": @(nw_path_is_constrained(path)),
            }, nil);

            nw_path_monitor_cancel(pathMonitor);
        });
        nw_path_monitor_start(pathMonitor);
    }];

    [self registerCapability:@"say" privileged:NO available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        NSString *text = StringArgument(args, @"text");
        if (text.length == 0) {
            reply(nil, @"Nothing to say");
            return;
        }

        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
                                                mode:AVAudioSessionModeSpokenAudio
                                             options:AVAudioSessionCategoryOptionDuckOthers
                                               error:nil];
        [[AVAudioSession sharedInstance] setActive:YES error:nil];

        AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:text];
        NSString *language = StringArgument(args, @"language");
        if (language != nil) {
            utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:language];
        }
        NSNumber *rate = NumberArgument(args, @"rate");
        if (rate != nil) {
            // rate 1 is normal speed
            utterance.rate = MIN(MAX(AVSpeechUtteranceDefaultSpeechRate * rate.floatValue, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate);
        }

        if (weakSelf.speechSynthesizer == nil) {
            weakSelf.speechSynthesizer = [[AVSpeechSynthesizer alloc] init];
            weakSelf.speechSynthesizer.delegate = weakSelf;
        }
        [weakSelf.pendingSpeechReplies setObject:reply forKey:utterance];
        [weakSelf.speechSynthesizer speakUtterance:utterance];
    }];

    [self registerCapability:@"wake_lock" privileged:NO available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        NSNumber *enabled = NumberArgument(args, @"enabled");
        if (enabled != nil) {
            [UIApplication sharedApplication].idleTimerDisabled = enabled.boolValue;
        }
        reply(@{ @"enabled": @([UIApplication sharedApplication].idleTimerDisabled) }, nil);
    }];

    [self registerCapability:@"hardware_keyboard" privileged:NO available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        reply(@{ @"connected": @([GCKeyboard coalescedKeyboard] != nil) }, nil);
    }];

    [self registerCapability:@"motion" privileged:NO available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        if (weakSelf.motionManager == nil) {
            weakSelf.motionManager = [[CMMotionManager alloc] init];
        }
        CMMotionManager *motionManager = weakSelf.motionManager;
        if (!motionManager.deviceMotionAvailable) {
            reply(nil, @"Motion sensors are not available");
            return;
        }

        __block BOOL sampled = NO;
        [motionManager startDeviceMotionUpdatesToQueue:[NSOperationQueue mainQueue] withHandler:^(CMDeviceMotion *motion, NSError *motionError) {
            if (sampled || motion == nil) {
                return;
            }
            sampled = YES;
            [motionManager stopDeviceMotionUpdates];

            reply(@{
                @"attitude": @{ @"roll": @(motion.attitude.roll), @"pitch": @(motion.attitude.pitch), @"yaw": @(motion.attitude.yaw) },
                @"gravity": VectorDictionary(motion.gravity.x, motion.gravity.y, motion.gravity.z),
                @"user_acceleration": VectorDictionary(motion.userAcceleration.x, motion.userAcceleration.y, motion.userAcceleration.z),
                @"rotation_rate": VectorDictionary(motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z),
            }, nil);
        }];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MotionSampleTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!sampled) {
                sampled = YES;
                [motionManager stopDeviceMotionUpdates];
                reply(nil, @"Timed out reading motion sensors");
            }
        });
    }];

    [self registerCapability:@"notify" privileged:NO available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        NSString *title = StringArgument(args, @"title") ?: @"OllieOS";
        NSString *body = StringArgument(args, @"body") ?: @"";
        NSNumber *delaySeconds = NumberArgument(args, @"delay_seconds");

        UNUserNotificationCenter *notificationCenter = [UNUserNotificationCenter currentNotificationCenter];
        UNAuthorizationOptions options = UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge;
        [notificationCenter requestAuthorizationWithOptions:options completionHandler:^(BOOL granted, NSError *authorizationError) {
            if (!granted) {
                reply(nil, @"Notifications are not allowed for OllieOS");
                return;
            }

            UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
            content.title = title;
            content.body = body;
            content.sound = [UNNotificationSound defaultSound];

            UNTimeIntervalNotificationTrigger *trigger = nil;
            if (delaySeconds != nil && delaySeconds.doubleValue >= 1) {
                trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:delaySeconds.doubleValue repeats:NO];
            }

            NSString *identifier = [NSUUID UUID].UUIDString;
            UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger];
            [notificationCenter addNotificationRequest:request withCompletionHandler:^(NSError *scheduleError) {
                if (scheduleError != nil) {
                    reply(nil, scheduleError.localizedDescription);
                } else {
                    reply(@{ @"id": identifier }, nil);
                }
            }];
        }];
    }];

    [self registerCapability:@"clipboard_write" privileged:NO available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        [UIPasteboard generalPasteboard].string = StringArgument(args, @"text") ?: @"";
        reply(@{}, nil);
    }];

    [self registerCapability:@"torch" privileged:NO available:hasTorch handler:^(NSDictionary *args, PlatformReply reply) {
        AVCaptureDevice *torchDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        NSNumber *turnOn = NumberArgument(args, @"on");
        NSNumber *level = NumberArgument(args, @"level");

        if (turnOn != nil || level != nil) {
            NSError *lockError = nil;
            if (![torchDevice lockForConfiguration:&lockError]) {
                reply(nil, lockError.localizedDescription ?: @"Could not control the torch");
                return;
            }

            BOOL shouldBeOn = turnOn != nil ? turnOn.boolValue : YES;
            if (shouldBeOn) {
                float torchLevel = level != nil ? MIN(MAX(level.floatValue, 0.01f), 1.0f) : 1.0f;
                [torchDevice setTorchModeOnWithLevel:torchLevel error:nil];
            } else {
                torchDevice.torchMode = AVCaptureTorchModeOff;
            }
            [torchDevice unlockForConfiguration];
        }

        reply(@{ @"on": @(torchDevice.torchMode == AVCaptureTorchModeOn), @"level": @(torchDevice.torchLevel) }, nil);
    }];

    [self registerCapability:@"brightness" privileged:NO available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        NSNumber *level = NumberArgument(args, @"level");
        if (level != nil) {
            [UIScreen mainScreen].brightness = MIN(MAX(level.doubleValue, 0.0), 1.0);
        }
        reply(@{ @"level": @([UIScreen mainScreen].brightness) }, nil);
    }];

    // userspace so the privilege agent (which runs unprivileged) can use it. it only reveals whether the owner confirmed
    [self registerCapability:@"authenticate" privileged:NO available:canAuthenticate handler:^(NSDictionary *args, PlatformReply reply) {
        NSString *reason = StringArgument(args, @"reason");
        if (reason.length == 0) {
            reply(nil, @"A reason is required to authenticate");
            return;
        }

        LAContext *authenticationContext = [[LAContext alloc] init];
        [authenticationContext evaluatePolicy:LAPolicyDeviceOwnerAuthentication localizedReason:reason reply:^(BOOL success, NSError *authenticationError) {
            reply(@{ @"success": @(success), @"error": NullIfNil(authenticationError.localizedDescription) }, nil);
        }];
    }];

    // ---------- privileged ----------

    [self registerCapability:@"clipboard_read" privileged:YES available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        reply(@{ @"text": NullIfNil([UIPasteboard generalPasteboard].string) }, nil);
    }];

    [self registerCapability:@"pick_file" privileged:YES available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        if (weakSelf.activeDocumentPickerHandler != nil) {
            reply(nil, @"A file picker is already open");
            return;
        }

        UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
        documentPicker.allowsMultipleSelection = NumberArgument(args, @"multiple").boolValue;

        DocumentPickerHandler *pickerHandler = [[DocumentPickerHandler alloc] init];
        pickerHandler.onPick = ^(NSArray<NSURL *> *urls) {
            weakSelf.activeDocumentPickerHandler = nil;
            NSMutableArray *pickedFiles = [NSMutableArray array];
            for (NSURL *fileURL in urls) {
                NSData *fileData = [NSData dataWithContentsOfURL:fileURL];
                if (fileData != nil) {
                    [pickedFiles addObject:@{
                        @"name": fileURL.lastPathComponent,
                        @"data_base64": [fileData base64EncodedStringWithOptions:0],
                    }];
                }
            }
            reply(@{ @"files": pickedFiles }, nil);
        };
        pickerHandler.onCancel = ^{
            weakSelf.activeDocumentPickerHandler = nil;
            reply(@{ @"files": @[] }, nil);
        };

        weakSelf.activeDocumentPickerHandler = pickerHandler;
        documentPicker.delegate = pickerHandler;
        [[weakSelf topViewController] presentViewController:documentPicker animated:YES completion:nil];
    }];

    [self registerCapability:@"export_file" privileged:YES available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        if (weakSelf.activeDocumentPickerHandler != nil) {
            reply(nil, @"A file picker is already open");
            return;
        }

        NSString *fileBase64 = StringArgument(args, @"data_base64");
        NSData *fileData = fileBase64 ? [[NSData alloc] initWithBase64EncodedString:fileBase64 options:NSDataBase64DecodingIgnoreUnknownCharacters] : nil;
        NSURL *fileURL = fileData ? [weakSelf writeTemporaryFileNamed:StringArgument(args, @"name") ?: @"file" data:fileData] : nil;
        if (fileURL == nil) {
            reply(nil, @"Could not prepare the file for export");
            return;
        }

        UIDocumentPickerViewController *exportPicker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[fileURL] asCopy:YES];

        DocumentPickerHandler *pickerHandler = [[DocumentPickerHandler alloc] init];
        pickerHandler.onPick = ^(NSArray<NSURL *> *urls) {
            weakSelf.activeDocumentPickerHandler = nil;
            reply(@{ @"exported": @YES }, nil);
        };
        pickerHandler.onCancel = ^{
            weakSelf.activeDocumentPickerHandler = nil;
            reply(@{ @"exported": @NO }, nil);
        };

        weakSelf.activeDocumentPickerHandler = pickerHandler;
        exportPicker.delegate = pickerHandler;
        [[weakSelf topViewController] presentViewController:exportPicker animated:YES completion:nil];
    }];

    [self registerCapability:@"pick_photo" privileged:YES available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        if (weakSelf.activePhotoPickerHandler != nil) {
            reply(nil, @"A photo picker is already open");
            return;
        }

        PHPickerConfiguration *pickerConfiguration = [[PHPickerConfiguration alloc] init];
        pickerConfiguration.filter = [PHPickerFilter imagesFilter];
        pickerConfiguration.selectionLimit = 1;

        BOOL wantsPNG = [StringArgument(args, @"format") isEqualToString:@"png"];

        PhotoPickerHandler *pickerHandler = [[PhotoPickerHandler alloc] init];
        pickerHandler.onFinish = ^(NSArray<PHPickerResult *> *results) {
            weakSelf.activePhotoPickerHandler = nil;

            NSItemProvider *itemProvider = results.firstObject.itemProvider;
            if (itemProvider == nil || ![itemProvider canLoadObjectOfClass:[UIImage class]]) {
                reply(@{ @"cancelled": @YES }, nil);
                return;
            }

            NSString *baseName = itemProvider.suggestedName.length > 0 ? itemProvider.suggestedName : @"photo";
            [itemProvider loadObjectOfClass:[UIImage class] completionHandler:^(id<NSItemProviderReading> loadedObject, NSError *loadError) {
                UIImage *image = [(NSObject *)loadedObject isKindOfClass:[UIImage class]] ? (UIImage *)loadedObject : nil;
                NSData *imageData = wantsPNG ? UIImagePNGRepresentation(image) : UIImageJPEGRepresentation(image, 0.9);
                if (imageData == nil) {
                    reply(nil, loadError.localizedDescription ?: @"Could not load the photo");
                    return;
                }

                reply(@{
                    @"cancelled": @NO,
                    @"name": [baseName stringByAppendingPathExtension:wantsPNG ? @"png" : @"jpg"],
                    @"data_base64": [imageData base64EncodedStringWithOptions:0],
                }, nil);
            }];
        };

        weakSelf.activePhotoPickerHandler = pickerHandler;
        PHPickerViewController *photoPicker = [[PHPickerViewController alloc] initWithConfiguration:pickerConfiguration];
        photoPicker.delegate = pickerHandler;
        [[weakSelf topViewController] presentViewController:photoPicker animated:YES completion:nil];
    }];

    [self registerCapability:@"scan_code" privileged:YES available:hasCamera handler:^(NSDictionary *args, PlatformReply reply) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!granted) {
                    reply(nil, @"Camera access is not allowed for OllieOS");
                    return;
                }

                CodeScannerViewController *scannerController = [[CodeScannerViewController alloc] init];
                scannerController.modalPresentationStyle = UIModalPresentationFullScreen;
                scannerController.onFinish = ^(NSString *scannedText, NSString *codeType) {
                    if (scannedText == nil) {
                        reply(@{ @"cancelled": @YES }, nil);
                    } else {
                        reply(@{ @"cancelled": @NO, @"text": scannedText, @"type": NullIfNil(codeType) }, nil);
                    }
                };
                [[weakSelf topViewController] presentViewController:scannerController animated:YES completion:nil];
            });
        }];
    }];

    [self registerCapability:@"location" privileged:YES available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        if (weakSelf.locationManager == nil) {
            weakSelf.locationManager = [[CLLocationManager alloc] init];
            weakSelf.locationManager.delegate = weakSelf;
            weakSelf.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
        }

        CLAuthorizationStatus status = weakSelf.locationManager.authorizationStatus;
        if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
            reply(nil, @"Location access is not allowed for OllieOS");
            return;
        }

        [weakSelf.pendingLocationReplies addObject:reply];
        if (status == kCLAuthorizationStatusNotDetermined) {
            // the authorization change callback requests the location once answered
            [weakSelf.locationManager requestWhenInUseAuthorization];
        } else {
            [weakSelf.locationManager requestLocation];
        }
    }];

    [self registerCapability:@"keychain_get" privileged:YES available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        NSString *key = StringArgument(args, @"key");
        if (key.length == 0) {
            reply(nil, @"A key is required");
            return;
        }

        NSDictionary *query = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: KeychainServiceName,
            (__bridge id)kSecAttrAccount: key,
            (__bridge id)kSecReturnData: @YES,
            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
        };

        CFTypeRef foundData = NULL;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &foundData);
        if (status == errSecItemNotFound) {
            reply(@{ @"value": [NSNull null] }, nil);
            return;
        }
        if (status != errSecSuccess) {
            reply(nil, [NSString stringWithFormat:@"Keychain error %d", (int)status]);
            return;
        }

        NSData *valueData = (__bridge_transfer NSData *)foundData;
        reply(@{ @"value": NullIfNil([[NSString alloc] initWithData:valueData encoding:NSUTF8StringEncoding]) }, nil);
    }];

    [self registerCapability:@"keychain_set" privileged:YES available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        NSString *key = StringArgument(args, @"key");
        NSString *value = StringArgument(args, @"value");
        if (key.length == 0 || value == nil) {
            reply(nil, @"A key and value are required");
            return;
        }

        NSDictionary *itemQuery = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: KeychainServiceName,
            (__bridge id)kSecAttrAccount: key,
        };
        SecItemDelete((__bridge CFDictionaryRef)itemQuery);

        NSMutableDictionary *newItem = [itemQuery mutableCopy];
        newItem[(__bridge id)kSecValueData] = [value dataUsingEncoding:NSUTF8StringEncoding];
        newItem[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;

        OSStatus status = SecItemAdd((__bridge CFDictionaryRef)newItem, NULL);
        if (status != errSecSuccess) {
            reply(nil, [NSString stringWithFormat:@"Keychain error %d", (int)status]);
            return;
        }
        reply(@{}, nil);
    }];

    [self registerCapability:@"keychain_delete" privileged:YES available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        NSString *key = StringArgument(args, @"key");
        if (key.length == 0) {
            reply(nil, @"A key is required");
            return;
        }

        NSDictionary *itemQuery = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: KeychainServiceName,
            (__bridge id)kSecAttrAccount: key,
        };
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)itemQuery);
        reply(@{ @"deleted": @(status == errSecSuccess) }, nil);
    }];

    [self registerCapability:@"contacts" privileged:YES available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        CNContactStore *contactStore = [[CNContactStore alloc] init];
        [contactStore requestAccessForEntityType:CNEntityTypeContacts completionHandler:^(BOOL granted, NSError *accessError) {
            if (!granted) {
                reply(nil, @"Contacts access is not allowed for OllieOS");
                return;
            }

            NSArray<id<CNKeyDescriptor>> *keys = @[
                CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey,
                CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
            ];
            CNContactFetchRequest *fetchRequest = [[CNContactFetchRequest alloc] initWithKeysToFetch:keys];
            fetchRequest.sortOrder = CNContactSortOrderGivenName;

            NSMutableArray *contacts = [NSMutableArray array];
            NSError *fetchError = nil;
            [contactStore enumerateContactsWithFetchRequest:fetchRequest error:&fetchError usingBlock:^(CNContact *contact, BOOL *stop) {
                NSMutableArray<NSString *> *phoneNumbers = [NSMutableArray array];
                for (CNLabeledValue<CNPhoneNumber *> *phoneNumber in contact.phoneNumbers) {
                    [phoneNumbers addObject:phoneNumber.value.stringValue];
                }
                NSMutableArray<NSString *> *emailAddresses = [NSMutableArray array];
                for (CNLabeledValue<NSString *> *emailAddress in contact.emailAddresses) {
                    [emailAddresses addObject:emailAddress.value];
                }

                [contacts addObject:@{
                    @"given_name": contact.givenName,
                    @"family_name": contact.familyName,
                    @"organization": contact.organizationName,
                    @"phone_numbers": phoneNumbers,
                    @"emails": emailAddresses,
                }];
            }];

            if (fetchError != nil) {
                reply(nil, fetchError.localizedDescription);
            } else {
                reply(@{ @"contacts": contacts }, nil);
            }
        }];
    }];

    [self registerCapability:@"calendar_events" privileged:YES available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        EKEventStore *eventStore = [[EKEventStore alloc] init];
        NSNumber *dayCount = NumberArgument(args, @"days") ?: @7;

        [weakSelf requestCalendarAccessForStore:eventStore completion:^(BOOL granted) {
            if (!granted) {
                reply(nil, @"Calendar access is not allowed for OllieOS");
                return;
            }

            NSDate *startDate = [NSDate date];
            NSDate *endDate = [startDate dateByAddingTimeInterval:MAX(dayCount.doubleValue, 1) * 86400];
            NSPredicate *eventPredicate = [eventStore predicateForEventsWithStartDate:startDate endDate:endDate calendars:nil];
            NSArray<EKEvent *> *events = [[eventStore eventsMatchingPredicate:eventPredicate] sortedArrayUsingSelector:@selector(compareStartDateWithEvent:)];

            NSMutableArray *eventList = [NSMutableArray array];
            for (EKEvent *event in events) {
                [eventList addObject:@{
                    @"title": NullIfNil(event.title),
                    @"start": NullIfNil(ISODateString(event.startDate)),
                    @"end": NullIfNil(ISODateString(event.endDate)),
                    @"all_day": @(event.allDay),
                    @"location": NullIfNil(event.location),
                    @"calendar": NullIfNil(event.calendar.title),
                }];
            }
            reply(@{ @"events": eventList }, nil);
        }];
    }];

    [self registerCapability:@"calendar_add" privileged:YES available:YES handler:^(NSDictionary *args, PlatformReply reply) {
        NSString *title = StringArgument(args, @"title");
        NSDate *startDate = DateFromISOString(StringArgument(args, @"start"));
        if (title.length == 0 || startDate == nil) {
            reply(nil, @"A title and an ISO 8601 start date are required");
            return;
        }
        NSDate *endDate = DateFromISOString(StringArgument(args, @"end")) ?: [startDate dateByAddingTimeInterval:3600];

        EKEventStore *eventStore = [[EKEventStore alloc] init];
        [weakSelf requestCalendarAccessForStore:eventStore completion:^(BOOL granted) {
            if (!granted) {
                reply(nil, @"Calendar access is not allowed for OllieOS");
                return;
            }

            EKEvent *event = [EKEvent eventWithEventStore:eventStore];
            event.title = title;
            event.startDate = startDate;
            event.endDate = endDate;
            event.location = StringArgument(args, @"location");
            event.notes = StringArgument(args, @"notes");
            event.calendar = eventStore.defaultCalendarForNewEvents;

            NSError *saveError = nil;
            if (![eventStore saveEvent:event span:EKSpanThisEvent commit:YES error:&saveError]) {
                reply(nil, saveError.localizedDescription ?: @"Could not save the event");
                return;
            }
            reply(@{ @"id": NullIfNil(event.eventIdentifier) }, nil);
        }];
    }];
}

- (void)requestCalendarAccessForStore:(EKEventStore *)eventStore completion:(void (^)(BOOL granted))completion {
    EKEventStoreRequestAccessCompletionHandler accessHandler = ^(BOOL granted, NSError *accessError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(granted);
        });
    };

    // ios 17 replaced the access request, call it dynamically so this builds against older sdks
    SEL fullAccessSelector = NSSelectorFromString(@"requestFullAccessToEventsWithCompletion:");
    if ([eventStore respondsToSelector:fullAccessSelector]) {
        void (*requestFullAccess)(id, SEL, EKEventStoreRequestAccessCompletionHandler) = (void *)objc_msgSend;
        requestFullAccess(eventStore, fullAccessSelector, accessHandler);
    } else {
        [eventStore requestAccessToEntityType:EKEntityTypeEvent completion:accessHandler];
    }
}

#pragma mark CLLocationManagerDelegate

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    if (self.pendingLocationReplies.count == 0) {
        return;
    }

    CLAuthorizationStatus status = manager.authorizationStatus;
    if (status == kCLAuthorizationStatusAuthorizedWhenInUse || status == kCLAuthorizationStatusAuthorizedAlways) {
        [manager requestLocation];
    } else if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
        [self finishLocationRequestsWithResult:nil error:@"Location access is not allowed for OllieOS"];
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *location = locations.lastObject;
    if (location == nil) {
        return;
    }

    [self finishLocationRequestsWithResult:@{
        @"latitude": @(location.coordinate.latitude),
        @"longitude": @(location.coordinate.longitude),
        @"altitude": @(location.altitude),
        @"horizontal_accuracy": @(location.horizontalAccuracy),
        @"vertical_accuracy": @(location.verticalAccuracy),
        @"timestamp": NullIfNil(ISODateString(location.timestamp)),
    } error:nil];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    [self finishLocationRequestsWithResult:nil error:error.localizedDescription ?: @"Could not get the location"];
}

- (void)finishLocationRequestsWithResult:(NSDictionary *)result error:(NSString *)errorMessage {
    NSArray<PlatformReply> *replies = [self.pendingLocationReplies copy];
    [self.pendingLocationReplies removeAllObjects];
    for (PlatformReply reply in replies) {
        reply(result, errorMessage);
    }
}

#pragma mark AVSpeechSynthesizerDelegate

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    [self finishSpeechUtterance:utterance cancelled:NO];
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didCancelSpeechUtterance:(AVSpeechUtterance *)utterance {
    [self finishSpeechUtterance:utterance cancelled:YES];
}

- (void)finishSpeechUtterance:(AVSpeechUtterance *)utterance cancelled:(BOOL)cancelled {
    PlatformReply reply = [self.pendingSpeechReplies objectForKey:utterance];
    [self.pendingSpeechReplies removeObjectForKey:utterance];
    if (reply != nil) {
        reply(@{ @"cancelled": @(cancelled) }, nil);
    }
}

#pragma mark UNUserNotificationCenterDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList | UNNotificationPresentationOptionSound);
}

@end
