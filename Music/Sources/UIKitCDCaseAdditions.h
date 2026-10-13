// Narrow public Apple APIs for the offline WebKit CD-case host.
// Included only by MiniSDK.h. Real SDK builds import WebKit/CoreMotion/UIKit.
// Verified against WebKit's public Cocoa headers and Apple's iOS 26 SDK.
#ifndef MUSIC_UIKIT_CD_CASE_ADDITIONS
#define MUSIC_UIKIT_CD_CASE_ADDITIONS

typedef double CFTimeInterval;
extern CFTimeInterval CACurrentMediaTime(void);
extern CGRect CGRectInset(CGRect rect, CGFloat dx, CGFloat dy);

@class WKWebView, WKWebViewConfiguration, WKNavigation, WKNavigationAction;
@class WKUserContentController, WKScriptMessage, WKFrameInfo, WKWebsiteDataStore;
@class NSURLRequest, CMMotionManager, CMDeviceMotion, CMAttitude, NSOperationQueue;

typedef unsigned long long dispatch_time_t;
typedef long long int64_t;
#define DISPATCH_TIME_NOW 0
#define NSEC_PER_SEC 1000000000ull
extern dispatch_time_t dispatch_time(dispatch_time_t when, int64_t delta);
extern void dispatch_after(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t block);
extern void NSLog(NSString *format, ...);
@interface NSError (GMCDDiagnosticCode)
@property(readonly) NSInteger code;
@end
@interface NSURLRequest : NSObject <NSCopying>
@property(readonly, copy) NSURL *URL;
@end
@interface NSURL (GMCDLocalURLs)
@property(readonly, getter=isFileURL) BOOL fileURL;
@property(readonly, copy) NSURL *URLByStandardizingPath;
@property(readonly, copy) NSString *absoluteString;
@end
@interface NSBundle (GMCDLocalResources)
- (id)objectForInfoDictionaryKey:(NSString *)key;
- (NSURL *)URLForResource:(NSString *)name withExtension:(NSString *)extension subdirectory:(NSString *)subpath;
@end
@interface NSMutableDictionary (GMMediaStillCache)
- (void)removeAllObjects;
- (void)removeObjectForKey:(id)key;
@end
@interface NSMapTable (GMMediaPendingFingerprints)
- (void)removeObjectForKey:(id)key;
@end
@interface NSString (GMMediaDigestInput)
- (NSData *)dataUsingEncoding:(NSUInteger)encoding;
@end
@interface NSData (GMCDJSON)
- (instancetype)initWithBase64EncodedString:(NSString *)string options:(NSUInteger)options;
- (NSString *)base64EncodedStringWithOptions:(NSUInteger)options;
@end
@interface NSArray (GMCDInspectionIndex)
- (NSUInteger)indexOfObject:(id)object;
@end
@interface NSNotification (GMCDSceneNotification)
@property(readonly, strong) id object;
@end
@interface NSJSONSerialization : NSObject
+ (NSData *)dataWithJSONObject:(id)object options:(NSUInteger)options error:(NSError **)error;
@end
@interface NSNull : NSObject <NSCopying>
+ (NSNull *)null;
@end
@interface NSHashTable<ObjectType> : NSObject <NSCopying, NSFastEnumeration>
+ (NSHashTable<ObjectType> *)weakObjectsHashTable;
@property(readonly, copy) NSArray<ObjectType> *allObjects;
- (void)addObject:(ObjectType)object;
- (void)removeObject:(ObjectType)object;
- (BOOL)containsObject:(ObjectType)object;
@end
@interface NSOperationQueue : NSObject
@property NSInteger maxConcurrentOperationCount;
@property(copy) NSString *name;
- (void)addOperationWithBlock:(void (^)(void))block;
- (void)cancelAllOperations;
@end
@interface NSLock : NSObject
- (void)lock;
- (void)unlock;
@end

typedef NSInteger WKNavigationActionPolicy;
enum { WKNavigationActionPolicyCancel = 0, WKNavigationActionPolicyAllow = 1 };
@protocol WKNavigationDelegate <NSObject>
@optional
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler;
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation;
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error;
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error;
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView;
@end
@protocol WKScriptMessageHandler <NSObject>
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message;
@end
@interface WKFrameInfo : NSObject <NSCopying>
@property(readonly, getter=isMainFrame) BOOL mainFrame;
@property(readonly, copy) NSURLRequest *request;
@end
@interface WKScriptMessage : NSObject
@property(readonly, copy) id body;
@property(readonly, weak) WKWebView *webView;
@property(readonly, copy) WKFrameInfo *frameInfo;
@property(readonly, copy) NSString *name;
@end
@interface WKNavigation : NSObject @end
@interface WKNavigationAction : NSObject
@property(readonly, copy) NSURLRequest *request;
@property(readonly, copy) WKFrameInfo *targetFrame;
@end
typedef NSInteger WKUserScriptInjectionTime;
enum { WKUserScriptInjectionTimeAtDocumentStart = 0, WKUserScriptInjectionTimeAtDocumentEnd = 1 };
@interface WKUserScript : NSObject
- (instancetype)initWithSource:(NSString *)source injectionTime:(WKUserScriptInjectionTime)injectionTime forMainFrameOnly:(BOOL)forMainFrameOnly;
@end
@interface WKUserContentController : NSObject
- (void)addUserScript:(WKUserScript *)userScript;
- (void)addScriptMessageHandler:(id<WKScriptMessageHandler>)scriptMessageHandler name:(NSString *)name;
- (void)removeScriptMessageHandlerForName:(NSString *)name;
@end
@interface WKWebsiteDataStore : NSObject
+ (WKWebsiteDataStore *)nonPersistentDataStore;
@end
@interface WKWebViewConfiguration : NSObject <NSCopying>
@property(nonatomic, strong) WKUserContentController *userContentController;
@property(nonatomic, strong) WKWebsiteDataStore *websiteDataStore;
@end
@interface WKWebView : UIView
- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration;
@property(nonatomic, readonly, copy) WKWebViewConfiguration *configuration;
@property(nonatomic, weak) id<WKNavigationDelegate> navigationDelegate;
@property(nonatomic, readonly, strong) UIScrollView *scrollView;
@property(nonatomic) BOOL allowsBackForwardNavigationGestures;
@property(nonatomic) BOOL allowsLinkPreview;
@property(nonatomic, copy) UIColor *underPageBackgroundColor;
- (WKNavigation *)loadFileURL:(NSURL *)URL allowingReadAccessToURL:(NSURL *)readAccessURL;
- (WKNavigation *)loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL;
- (void)evaluateJavaScript:(NSString *)javaScriptString completionHandler:(void (^)(id result, NSError *error))completionHandler;
- (void)stopLoading;
@end
// WKProcessPool is deliberately omitted: deprecated since iOS 15 because
// multiple pools no longer affect process allocation. The host shares a
// nonpersistent data store; each WebGL view still owns its own GPU resources.

@interface CMAttitude : NSObject <NSCopying>
@property(readonly, nonatomic) double roll;
@property(readonly, nonatomic) double pitch;
- (void)multiplyByInverseOfAttitude:(CMAttitude *)attitude;
@end
@interface CMLogItem : NSObject
@property(readonly, nonatomic) NSTimeInterval timestamp;
@end
@interface CMDeviceMotion : CMLogItem
@property(readonly, nonatomic) CMAttitude *attitude;
@end
typedef void (^CMDeviceMotionHandler)(CMDeviceMotion *motion, NSError *error);
@interface CMMotionManager : NSObject
@property(assign, nonatomic) NSTimeInterval deviceMotionUpdateInterval;
@property(readonly, nonatomic, getter=isDeviceMotionAvailable) BOOL deviceMotionAvailable;
@property(readonly, nonatomic, getter=isDeviceMotionActive) BOOL deviceMotionActive;
- (void)startDeviceMotionUpdatesToQueue:(NSOperationQueue *)queue withHandler:(CMDeviceMotionHandler)handler;
- (void)stopDeviceMotionUpdates;
@end

typedef NSInteger UIApplicationState;
enum { UIApplicationStateActive = 0, UIApplicationStateInactive = 1, UIApplicationStateBackground = 2 };
@interface UIApplication (GMCDApplicationState)
@property(nonatomic, readonly) UIApplicationState applicationState;
@end
extern NSString *const UIApplicationDidBecomeActiveNotification;
extern NSString *const UIApplicationWillResignActiveNotification;
extern NSString *const UIApplicationDidReceiveMemoryWarningNotification;
extern NSString *const UISceneDidActivateNotification;
extern NSString *const UISceneWillDeactivateNotification;
extern NSString *const UIAccessibilityPrefersCrossFadeTransitionsStatusDidChangeNotification;
typedef NSInteger UISceneActivationState;
enum { UISceneActivationStateUnattached = -1, UISceneActivationStateForegroundActive = 0,
       UISceneActivationStateForegroundInactive = 1, UISceneActivationStateBackground = 2 };
@interface UIScene (GMCDSceneState)
@property(nonatomic, readonly) UISceneActivationState activationState;
@end
@interface UIWindow (GMCDWindowScene)
@property(nonatomic, weak) UIWindowScene *windowScene;
@end

// Public orientation and gesture APIs used by the native inspector.
typedef NSInteger UIInterfaceOrientation;
enum { UIInterfaceOrientationUnknown = 0, UIInterfaceOrientationPortrait = 1,
       UIInterfaceOrientationPortraitUpsideDown = 2, UIInterfaceOrientationLandscapeLeft = 4,
       UIInterfaceOrientationLandscapeRight = 3 };
typedef NSUInteger UIInterfaceOrientationMask;
enum { UIInterfaceOrientationMaskPortrait = 1UL << 1,
       UIInterfaceOrientationMaskPortraitUpsideDown = 1UL << 2,
       UIInterfaceOrientationMaskLandscapeLeft = 1UL << 4,
       UIInterfaceOrientationMaskLandscapeRight = 1UL << 3,
       UIInterfaceOrientationMaskLandscape = (1UL << 4) | (1UL << 3),
       UIInterfaceOrientationMaskAll = 30,
       UIInterfaceOrientationMaskAllButUpsideDown = 26 };
@interface UIWindowSceneGeometry : NSObject <NSCopying>
@property(nonatomic, readonly) UIInterfaceOrientation interfaceOrientation;
@end
@interface UIWindowScene (GMCDOrientation)
@property(nonatomic, readonly) UIWindowSceneGeometry *effectiveGeometry;
@property(nonatomic, readonly) UIInterfaceOrientation interfaceOrientation;
@end
@interface UIViewController (GMCDOrientation)
@property(nonatomic, readonly) UIInterfaceOrientationMask supportedInterfaceOrientations;
@property(nonatomic, readonly) UIInterfaceOrientation preferredInterfaceOrientationForPresentation;
@property(nonatomic, readonly) BOOL shouldAutorotate;
- (void)setNeedsUpdateOfSupportedInterfaceOrientations;
@end
typedef NSInteger UIUserInterfaceIdiom;
enum { UIUserInterfaceIdiomUnspecified = -1, UIUserInterfaceIdiomPhone = 0, UIUserInterfaceIdiomPad = 1 };
@interface UITraitCollection (GMCDDeviceIdiom)
@property(nonatomic, readonly) UIUserInterfaceIdiom userInterfaceIdiom;
@end
@interface UILongPressGestureRecognizer : UIGestureRecognizer
@property(nonatomic) NSTimeInterval minimumPressDuration;
@property(nonatomic) CGFloat allowableMovement;
@property(nonatomic) NSUInteger numberOfTouchesRequired;
@end
typedef NSUInteger UISwipeGestureRecognizerDirection;
enum { UISwipeGestureRecognizerDirectionRight = 1, UISwipeGestureRecognizerDirectionLeft = 2,
       UISwipeGestureRecognizerDirectionUp = 4, UISwipeGestureRecognizerDirectionDown = 8 };
@interface UISwipeGestureRecognizer : UIGestureRecognizer
@property(nonatomic) UISwipeGestureRecognizerDirection direction;
@property(nonatomic) NSUInteger numberOfTouchesRequired;
@end
@protocol UIScrollViewDelegate <NSObject>
@optional
- (void)scrollViewDidScroll:(UIScrollView *)scrollView;
@end
@interface UIScrollView (GMCDPlayerVisibility)
@property(nonatomic, weak) id<UIScrollViewDelegate> delegate;
@end
enum { UIViewAnimationOptionTransitionFlipFromLeft = 1UL << 20,
       UIViewAnimationOptionTransitionFlipFromRight = 2UL << 20 };
@interface UIView (GMCDAlbumTransition)
+ (void)transitionWithView:(UIView *)view duration:(NSTimeInterval)duration options:(UIViewAnimationOptions)options animations:(void (^)(void))animations completion:(void (^)(BOOL finished))completion;
@end

@protocol UIViewControllerContextTransitioning <NSObject>
@property(nonatomic, readonly) UIView *containerView;
@property(nonatomic, readonly) BOOL transitionWasCancelled;
- (CGRect)finalFrameForViewController:(UIViewController *)controller;
- (UIView *)viewForKey:(NSString *)key;
- (void)completeTransition:(BOOL)completed;
@end
@protocol UIViewControllerAnimatedTransitioning <NSObject>
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)context;
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context;
@end
@protocol UIViewControllerTransitioningDelegate <NSObject>
@optional
- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source;
- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed;
@end
@interface UIViewController (GMPlayerTransition)
@property(nonatomic, weak) id<UIViewControllerTransitioningDelegate> transitioningDelegate;
@end
typedef unsigned long long UIAccessibilityTraits;
extern const UIAccessibilityTraits UIAccessibilityTraitButton;
@interface UIView (GMPlayerCoordinates)
@property(nonatomic) UIAccessibilityTraits accessibilityTraits;
- (CGRect)convertRect:(CGRect)rect fromView:(UIView *)view;
@end
extern NSString *const UITransitionContextToViewKey;
#endif
