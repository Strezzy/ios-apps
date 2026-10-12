// Enter the Third Dimension — native landscape host for the bundled game.
// Always compiled with Apple's SDK. NSObject's layout comes from Foundation;
// no hand-declared headers, downloaded game code, private APIs, or JIT are used.
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

static UIColor *GameBackground(void) {
    return [UIColor colorWithRed:0.035 green:0.043 blue:0.09 alpha:1.0];
}

@interface GameController : UIViewController <WKNavigationDelegate>
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) NSURL *entryURL;
@property(nonatomic, strong) NSURL *gameDirectory;
@property(nonatomic, strong) UIButton *statusButton;
@property(nonatomic) BOOL appInactive;
@property(nonatomic) BOOL needsPauseAfterLoad;
@property(nonatomic) BOOL smokeTest;
@property(nonatomic) NSUInteger loadGeneration;
@property(nonatomic) NSUInteger readinessAttempts;
- (void)loadGame;
- (void)pauseGame;
- (void)inspectReadinessForGeneration:(NSUInteger)generation;
@end

@implementation GameController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = GameBackground();
    self.view.multipleTouchEnabled = YES;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.smokeTest = [NSProcessInfo.processInfo.arguments containsObject:@"--native-smoke-test"];

    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = NO;
    configuration.allowsInlineMediaPlayback = YES;
    configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    NSString *captureErrors =
        @"window.__thirdDimensionNativeErrors=[];"
         "window.addEventListener('error',function(e){"
           "if(window.__thirdDimensionNativeErrors.length<8)"
             "window.__thirdDimensionNativeErrors.push(String(e.message||'Script load failed'));"
         "});"
         "window.addEventListener('unhandledrejection',function(e){"
           "if(window.__thirdDimensionNativeErrors.length<8)"
             "window.__thirdDimensionNativeErrors.push(String(e.reason||'Unhandled script rejection'));"
         "});";
    [configuration.userContentController addUserScript:[[WKUserScript alloc]
        initWithSource:captureErrors injectionTime:WKUserScriptInjectionTimeAtDocumentStart
        forMainFrameOnly:YES]];

    WKWebView *web = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
    web.navigationDelegate = self;
    web.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    web.opaque = NO;
    web.backgroundColor = GameBackground();
    web.multipleTouchEnabled = YES;
    web.allowsBackForwardNavigationGestures = NO;
    web.allowsLinkPreview = NO;
    web.scrollView.scrollEnabled = NO;
    web.scrollView.bounces = NO;
    web.scrollView.alwaysBounceHorizontal = NO;
    web.scrollView.alwaysBounceVertical = NO;
    web.scrollView.showsHorizontalScrollIndicator = NO;
    web.scrollView.showsVerticalScrollIndicator = NO;
    web.scrollView.delaysContentTouches = NO;
    web.scrollView.canCancelContentTouches = NO;
    web.scrollView.multipleTouchEnabled = YES;
    web.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    web.scrollView.pinchGestureRecognizer.enabled = NO;
    self.webView = web;
    [self.view addSubview:web];

    UIButton *status = [UIButton buttonWithType:UIButtonTypeSystem];
    status.titleLabel.font = [UIFont systemFontOfSize:19 weight:UIFontWeightSemibold];
    status.titleLabel.numberOfLines = 4;
    status.titleLabel.textAlignment = NSTextAlignmentCenter;
    [status setTitleColor:[UIColor colorWithRed:0.88 green:0.98 blue:0.96 alpha:1]
                forState:UIControlStateNormal];
    status.backgroundColor = GameBackground();
    [status addTarget:self action:@selector(loadGame) forControlEvents:UIControlEventTouchUpInside];
    self.statusButton = status;
    [self.view addSubview:status];

    self.entryURL = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html"
                                          subdirectory:@"Game"];
    self.gameDirectory = self.entryURL.URLByDeletingLastPathComponent;
    [self loadGame];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.webView.frame = self.view.bounds;
    // The game covers the display; CSS safe-area insets protect its controls.
    self.statusButton.frame = self.view.bounds;
}

- (void)writeSmokeResult:(NSDictionary *)result {
    if (!self.smokeTest) return;
    NSMutableDictionary *report = [result mutableCopy];
    report[@"bundleIdentifier"] = NSBundle.mainBundle.bundleIdentifier ?: @"";
    report[@"version"] = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    report[@"build"] = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"";
    report[@"nativeViewWidth"] = @(self.view.bounds.size.width);
    report[@"nativeViewHeight"] = @(self.view.bounds.size.height);
    report[@"bundledEntry"] = self.webView.URL.lastPathComponent ?: @"";
    report[@"loadGeneration"] = @(self.loadGeneration);
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:report
                     options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
    NSURL *documents = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                            inDomains:NSUserDomainMask].firstObject;
    NSURL *destination = [documents URLByAppendingPathComponent:@"ThirdDimension-Native-Smoke.json"];
    if (!data || ![data writeToURL:destination options:NSDataWritingAtomic error:&error]) {
        NSLog(@"THIRD_DIMENSION_SMOKE_WRITE_FAILED %@", error.localizedDescription);
    } else {
        NSLog(@"THIRD_DIMENSION_NATIVE_READY %@", [report[@"ready"] boolValue] ? @"YES" : @"NO");
    }
}

- (void)showLoadFailure:(NSString *)reason {
    self.statusButton.hidden = NO;
    self.statusButton.enabled = YES;
    [self.statusButton setTitle:@"Your world couldn’t open.\nTap to try again."
                      forState:UIControlStateNormal];
    [self.view bringSubviewToFront:self.statusButton];
    [self writeSmokeResult:@{@"ready": @NO, @"errors": @[reason ?: @"Unknown startup failure"]}];
}

- (void)loadGame {
    self.loadGeneration += 1;
    self.readinessAttempts = 0;
    self.statusButton.hidden = NO;
    self.statusButton.enabled = NO;
    [self.statusButton setTitle:@"ENTER THE THIRD DIMENSION\nOpening your world…"
                      forState:UIControlStateNormal];
    if (!self.entryURL || !self.gameDirectory) {
        [self showLoadFailure:@"The bundled Game/index.html is missing."];
        return;
    }
    if (self.smokeTest) {
        [self writeSmokeResult:@{@"ready": @NO, @"loading": @YES, @"errors": @[]}];
    }
    [self.webView loadFileURL:self.entryURL allowingReadAccessToURL:self.gameDirectory];
}

- (void)inspectReadinessForGeneration:(NSUInteger)generation {
    if (generation != self.loadGeneration) return;
    __weak GameController *weakSelf = self;
    if (self.appInactive) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [weakSelf inspectReadinessForGeneration:generation]; });
        return;
    }
    self.readinessAttempts += 1;
    NSString *script =
        @"(function(){const g=window.ThirdDimension;"
          "const errors=(window.__thirdDimensionNativeErrors||[]).concat(g&&Array.isArray(g.errors)?g.errors:[]).map(String);"
          "return JSON.parse(JSON.stringify({ready:!!(g&&g.ready===true),"
            "state:g&&typeof g.getState==='function'?g.getState():null,errors:errors}));"
        "})()";
    [self.webView evaluateJavaScript:script completionHandler:^(id value, NSError *error) {
        GameController *controller = weakSelf;
        if (!controller || generation != controller.loadGeneration) return;
        NSDictionary *result = [value isKindOfClass:[NSDictionary class]] ? value : nil;
        NSArray *errors = [result[@"errors"] isKindOfClass:[NSArray class]] ? result[@"errors"] : @[];
        if (error || errors.count) {
            [controller showLoadFailure:error.localizedDescription ?: [errors componentsJoinedByString:@"; "]];
            return;
        }
        if ([result[@"ready"] boolValue] && [result[@"state"] isKindOfClass:[NSDictionary class]]) {
            controller.statusButton.hidden = YES;
            if (controller.appInactive || controller.needsPauseAfterLoad) {
                [controller pauseGame];
                controller.needsPauseAfterLoad = NO;
            }
            [controller writeSmokeResult:result];
            return;
        }
        if (controller.readinessAttempts >= 80) {
            [controller showLoadFailure:@"The local game did not finish initializing within the startup limit."];
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [weakSelf inspectReadinessForGeneration:generation]; });
    }];
}

- (void)pauseGame {
    // Calls the retained alias so backgrounding also clears every held thumb.
    [self.webView evaluateJavaScript:
        @"if(window.Moonhop&&typeof window.Moonhop.nativePause==='function'){window.Moonhop.nativePause();}"
         "else if(window.ThirdDimension&&typeof window.ThirdDimension.nativePause==='function'){window.ThirdDimension.nativePause();}"
                  completionHandler:nil];
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures { return UIRectEdgeBottom; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation { return UIInterfaceOrientationLandscapeRight; }
- (BOOL)shouldAutorotate { return YES; }

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
 decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = action.request.URL;
    NSString *prefix = [self.gameDirectory.URLByStandardizingPath.path stringByAppendingString:@"/"];
    BOOL localFile = url.isFileURL && [url.URLByStandardizingPath.path hasPrefix:prefix];
    BOOL blankPage = [url.absoluteString isEqualToString:@"about:blank"];
    decisionHandler(localFile || blankPage ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    // Navigation alone does not prove that game.js or WebGL initialized.
    [self inspectReadinessForGeneration:self.loadGeneration];
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation
     withError:(NSError *)error {
    if (error.code != NSURLErrorCancelled) [self showLoadFailure:error.localizedDescription];
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self webView:webView didFailProvisionalNavigation:navigation withError:error];
}
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    self.needsPauseAfterLoad = YES;
    [self loadGame];
}
@end

// Same scene/window startup approach as the working second music build. Real
// SDK headers now guarantee the correct NSObject header and subclass layouts.
@interface SceneDelegate : NSObject <UIWindowSceneDelegate>
@property(strong, nonatomic) UIWindow *window;
@end
@implementation SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session
      options:(UISceneConnectionOptions *)options {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [GameController new];
    [self.window makeKeyAndVisible];
}
- (void)sceneWillResignActive:(UIScene *)scene {
    GameController *game = (GameController *)self.window.rootViewController;
    game.appInactive = YES;
    game.needsPauseAfterLoad = YES;
    [game pauseGame];
}
- (void)sceneDidBecomeActive:(UIScene *)scene {
    GameController *game = (GameController *)self.window.rootViewController;
    game.appInactive = NO;
    [game pauseGame];
}
- (void)sceneDidEnterBackground:(UIScene *)scene { [self sceneWillResignActive:scene]; }
@end

@interface AppDelegate : NSObject <UIApplicationDelegate> @end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options { return YES; }
- (UISceneConfiguration *)application:(UIApplication *)application
 configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc]
        initWithName:@"Default Configuration" sessionRole:session.role];
    configuration.sceneClass = [UIWindowScene class];
    configuration.delegateClass = [SceneDelegate class];
    return configuration;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class])); }
}
