#import "MusicCDCase.h"

// The renderer itself is the credited, locally bundled WebGL adaptation. This
// native host owns artwork transfer, public WebKit APIs, and resource/lifetime
// limits. No file URL outside the CDCase resource directory is navigable.
static CGFloat GMCDClamp(CGFloat value) {
    if (value != value) return 0;
    return value < -1 ? -1 : (value > 1 ? 1 : value);
}
static BOOL GMCDReducedMotion(void) {
    return UIAccessibilityIsReduceMotionEnabled() || UIAccessibilityPrefersCrossFadeTransitions();
}
static BOOL GMCDRectsIntersect(CGRect a, CGRect b) {
    return a.size.width > 1 && a.size.height > 1 && b.size.width > 1 && b.size.height > 1 &&
        a.origin.x < b.origin.x+b.size.width && b.origin.x < a.origin.x+a.size.width &&
        a.origin.y < b.origin.y+b.size.height && b.origin.y < a.origin.y+a.size.height;
}
static UIColor *GMCDWhite(CGFloat white, CGFloat alpha) {
    return [UIColor colorWithRed:white green:white blue:white alpha:alpha];
}
static UIInterfaceOrientation GMCDOrientation(UIWindow *window) {
    UIWindowScene *scene = window.windowScene;
    if ([scene respondsToSelector:@selector(effectiveGeometry)]) return scene.effectiveGeometry.interfaceOrientation;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return scene.interfaceOrientation;
#pragma clang diagnostic pop
}

// Every tile remains a CD case, including during startup, outside the live
// renderer budget, or after a WebContent process is reclaimed by the system.
// These ordinary native layers have no timers and retain only bounded artwork.
@interface GMCDCaseFallbackView : UIView
@property(nonatomic, strong) UIView *caseBody;
@property(nonatomic, strong) UIView *spine;
@property(nonatomic, strong) UIView *discRim;
@property(nonatomic, strong) UIImageView *disc;
@property(nonatomic, strong) UIView *hubRing;
@property(nonatomic, strong) UIView *hole;
@property(nonatomic, strong) CAGradientLayer *reflection;
@property(nonatomic, strong) CAGradientLayer *discSheen;
- (void)setArtwork:(UIImage *)artwork;
- (void)applyTheme;
@end
@implementation GMCDCaseFallbackView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.userInteractionEnabled = NO; self.accessibilityElementsHidden = YES;
    self.caseBody = [[UIView alloc] initWithFrame:CGRectZero];
    self.caseBody.layer.cornerRadius = 5; self.caseBody.layer.borderWidth = 1;
    self.caseBody.layer.shadowOffset = CGSizeMake(0,3); self.caseBody.layer.shadowRadius = 5;
    self.caseBody.layer.shadowOpacity = .12;
    [self addSubview:self.caseBody];
    self.discRim = [[UIView alloc] initWithFrame:CGRectZero];
    self.discRim.layer.borderWidth = 1; self.discRim.clipsToBounds = YES;
    [self.caseBody addSubview:self.discRim];
    self.discSheen = [CAGradientLayer layer];
    self.discSheen.startPoint = CGPointMake(0,0); self.discSheen.endPoint = CGPointMake(1,1);
    self.discSheen.locations = @[@0,@.3,@.5,@.7,@1];
    self.discSheen.colors = @[(__bridge id)GMCDWhite(.90,1).CGColor,
        (__bridge id)[UIColor colorWithRed:.70 green:.83 blue:.97 alpha:1].CGColor,
        (__bridge id)GMCDWhite(.97,1).CGColor,
        (__bridge id)[UIColor colorWithRed:.93 green:.73 blue:.83 alpha:1].CGColor,
        (__bridge id)GMCDWhite(.70,1).CGColor];
    [self.discRim.layer addSublayer:self.discSheen];
    self.disc = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.disc.contentMode = 2; self.disc.clipsToBounds = YES;
    [self.discRim addSubview:self.disc];
    self.hubRing = [[UIView alloc] initWithFrame:CGRectZero];
    self.hubRing.layer.borderWidth = 1; [self.caseBody addSubview:self.hubRing];
    self.hole = [[UIView alloc] initWithFrame:CGRectZero];
    self.hole.layer.borderWidth = 1; [self.caseBody addSubview:self.hole];
    self.spine = [[UIView alloc] initWithFrame:CGRectZero];
    self.spine.layer.borderWidth = .6; [self.caseBody addSubview:self.spine];
    self.reflection = [CAGradientLayer layer];
    self.reflection.startPoint = CGPointMake(0,0); self.reflection.endPoint = CGPointMake(1,1);
    self.reflection.locations = @[@0,@.08,@.13,@.45,@.50,@1];
    [self.caseBody.layer addSublayer:self.reflection];
    [self applyTheme];
    return self;
}
- (void)setArtwork:(UIImage *)artwork {
    self.disc.image = artwork;
    self.disc.hidden = artwork == nil;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = GMMin(self.bounds.size.width,self.bounds.size.height)*.97;
    if (side < 1) return;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    self.caseBody.frame = CGRectMake((self.bounds.size.width-side)/2,(self.bounds.size.height-side)/2,side,side);
    CGFloat diameter = side*.80, cx = side*.545, cy = side*.50;
    self.discRim.frame = CGRectMake(cx-diameter/2,cy-diameter/2,diameter,diameter);
    self.discRim.layer.cornerRadius = diameter/2;
    self.discSheen.frame = self.discRim.bounds;
    CGFloat margin = GMMax(1.2,diameter*.018);
    self.disc.frame = CGRectMake(margin,margin,diameter-2*margin,diameter-2*margin);
    self.disc.layer.cornerRadius = (diameter-2*margin)/2;
    CGFloat ring = diameter*.25, hole = diameter*.10;
    self.hubRing.frame = CGRectMake(cx-ring/2,cy-ring/2,ring,ring);
    self.hubRing.layer.cornerRadius = ring/2;
    self.hole.frame = CGRectMake(cx-hole/2,cy-hole/2,hole,hole);
    self.hole.layer.cornerRadius = hole/2;
    self.spine.frame = CGRectMake(side*.035,side*.025,side*.068,side*.95);
    self.spine.layer.cornerRadius = 2;
    self.reflection.frame = self.caseBody.bounds; self.reflection.cornerRadius = 5;
    [CATransaction commit];
}
- (void)applyTheme {
    BOOL dark = self.traitCollection.userInterfaceStyle == 2;
    UIColor *page = [GMPageColor() resolvedColorWithTraitCollection:self.traitCollection];
    self.caseBody.backgroundColor = GMCDWhite(dark ? .34 : .92,dark ? .16 : .27);
    self.caseBody.layer.borderColor = GMCDWhite(dark ? 1 : .38,dark ? .43 : .40).CGColor;
    self.caseBody.layer.shadowColor = [UIColor blackColor].CGColor;
    self.spine.backgroundColor = GMCDWhite(dark ? .03 : .30,.18);
    self.spine.layer.borderColor = GMCDWhite(dark ? 1 : .4,.32).CGColor;
    self.discRim.layer.borderColor = GMCDWhite(.55,.65).CGColor;
    self.hubRing.backgroundColor = GMCDWhite(.82,.68);
    self.hubRing.layer.borderColor = GMCDWhite(1,.60).CGColor;
    self.hole.backgroundColor = page;
    self.hole.layer.borderColor = GMCDWhite(.25,.45).CGColor;
    self.reflection.colors = @[(__bridge id)GMCDWhite(1,.32).CGColor,
        (__bridge id)GMCDWhite(1,.02).CGColor,(__bridge id)GMCDWhite(1,.20).CGColor,
        (__bridge id)GMCDWhite(1,0).CGColor,(__bridge id)GMCDWhite(1,.10).CGColor,
        (__bridge id)GMCDWhite(1,0).CGColor];
}
@end

@class GMCDMotionHub;
@interface GMCDScriptProxy : NSObject <WKScriptMessageHandler>
@property(nonatomic, weak) GMCDCaseView *owner;
@end
// Workers retain this small token rather than temporarily retaining a UIView
// off-main. Cancellation also avoids decoding covers for already-reused rows.
@interface GMCDArtworkJob : NSObject
@property(atomic, getter=isCancelled) BOOL cancelled;
@end
@implementation GMCDArtworkJob @end

@interface GMCDCaseView () <WKNavigationDelegate>
@property(nonatomic, readwrite, copy) NSString *representedIdentifier;
@property(nonatomic) GMCDCasePresentation presentation;
@property(nonatomic, strong) GMCDCaseFallbackView *fallback;
@property(nonatomic, strong) UIView *stillView;
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) GMCDScriptProxy *scriptProxy;
@property(nonatomic, strong) NSURL *resourceDirectory;
@property(nonatomic, strong) UIImage *artwork;
@property(nonatomic, strong) GMCDArtworkJob *artworkJob;
@property(nonatomic, copy) NSString *encodedArtwork;
@property(nonatomic) NSUInteger artworkRevision;
@property(nonatomic) NSUInteger encodedRevision;
@property(atomic) NSUInteger encodingGeneration;
@property(nonatomic) NSUInteger rendererGeneration;
@property(nonatomic) NSUInteger rendererArtworkRevision;
@property(nonatomic, strong) NSMutableDictionary<NSString *,id> *pending;
@property(nonatomic, copy) NSArray<NSNumber *> *backgroundComponents;
@property(nonatomic) BOOL ownerActive;
@property(nonatomic) BOOL playing;
@property(nonatomic) BOOL caseOpen;
@property(nonatomic) BOOL bridgeReady;
@property(nonatomic, strong) UILabel *rendererStatusLabel;
@property(nonatomic, copy) NSString *rendererFailureReason;
@property(nonatomic) NSUInteger automaticRetries;
- (void)showRendererStatus:(NSString *)message;
- (void)retryRenderer;
- (void)recordRendererFailure:(NSString *)reason;
- (void)checkBridgeAfterNavigation;
@property(nonatomic) BOOL rendered;
@property(nonatomic) BOOL evaluating;
@property(nonatomic) BOOL encoding;
@property(nonatomic) BOOL failedThisActivation;
@property(nonatomic) CGFloat sensorX;
@property(nonatomic) CGFloat sensorY;
@property(nonatomic) CGFloat inspectionX;
@property(nonatomic) CGFloat inspectionY;
- (BOOL)eligibleForRenderer;
- (void)startRenderer;
- (void)stopRendererKeepingStill:(BOOL)keepStill;
- (void)receiveScriptMessage:(WKScriptMessage *)message;
- (void)flushPending;
- (void)queueMotionState;
- (void)acceptSensorX:(CGFloat)x y:(CGFloat)y;
- (void)motionPreferenceChanged;
- (void)failRenderer;
@end

// One coordinator, weak views, one dedicated sensor queue, one bounded artwork
// encoder queue. WebKit's nonpersistent store is shared, GPU contexts are not.
@interface GMCDMotionHub : NSObject
@property(nonatomic, strong) NSHashTable<GMCDCaseView *> *views;
@property(nonatomic, strong) NSHashTable<UIScene *> *pausedScenes;
@property(nonatomic, strong) NSOperationQueue *motionQueue;
@property(nonatomic, strong) NSOperationQueue *artworkQueue;
@property(nonatomic, strong) CMMotionManager *motionManager;
@property(nonatomic, strong) WKWebsiteDataStore *dataStore;
@property(nonatomic, strong) NSLock *sampleLock;
@property(nonatomic, strong) CMAttitude *referenceAttitude;
@property(nonatomic) NSUInteger motionGeneration;
@property(nonatomic) CGFloat latestX;
@property(nonatomic) CGFloat latestY;
@property(nonatomic) BOOL deliveryPending;
@property(nonatomic) BOOL reconciling;
@property(nonatomic) BOOL applicationSuspended;
@property(nonatomic) BOOL sensorFailed;
@property(nonatomic) UIInterfaceOrientation motionOrientation;
- (void)reconcile;
- (void)updateMotionDemand;
@end
static GMCDMotionHub *GMCDSharedHub(void) {
    // All callers that create or configure UIKit views run on the main queue.
    static GMCDMotionHub *hub;
    if (!hub) hub = [GMCDMotionHub new];
    return hub;
}
@implementation GMCDMotionHub
- (instancetype)init {
    self = [super init]; if (!self) return nil;
    self.views = [NSHashTable weakObjectsHashTable];
    self.pausedScenes = [NSHashTable weakObjectsHashTable];
    self.motionQueue = [NSOperationQueue new]; self.motionQueue.maxConcurrentOperationCount = 1;
    self.motionQueue.name = @"Music.CDCase.Motion";
    self.artworkQueue = [NSOperationQueue new]; self.artworkQueue.maxConcurrentOperationCount = 1;
    self.artworkQueue.name = @"Music.CDCase.Artwork";
    self.sampleLock = [NSLock new];
    self.dataStore = [WKWebsiteDataStore nonPersistentDataStore];
    UIApplication *application = [UIApplication sharedApplication];
    self.applicationSuspended = application.applicationState != UIApplicationStateActive;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(applicationPaused:) name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(applicationPaused:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:self selector:@selector(applicationResumed:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(scenePaused:) name:UISceneWillDeactivateNotification object:nil];
    [center addObserver:self selector:@selector(sceneResumed:) name:UISceneDidActivateNotification object:nil];
    [center addObserver:self selector:@selector(preferenceChanged:) name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(preferenceChanged:) name:UIAccessibilityPrefersCrossFadeTransitionsStatusDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(memoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    return self;
}
- (void)applicationPaused:(NSNotification *)notification {
    self.applicationSuspended = YES; [self reconcile];
}
- (void)applicationResumed:(NSNotification *)notification {
    self.applicationSuspended = NO; self.sensorFailed = NO;
    for (GMCDCaseView *view in self.views.allObjects) view.failedThisActivation = NO;
    [self reconcile];
}
- (void)scenePaused:(NSNotification *)notification {
    if (notification.object) [self.pausedScenes addObject:notification.object];
    [self reconcile];
}
- (void)sceneResumed:(NSNotification *)notification {
    if (notification.object) [self.pausedScenes removeObject:notification.object];
    [self reconcile];
}
- (void)preferenceChanged:(NSNotification *)notification {
    if (![NSThread isMainThread]) {
        __weak GMCDMotionHub *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(),^{ [weakSelf preferenceChanged:nil]; });
        return;
    }
    for (GMCDCaseView *view in self.views.allObjects) [view motionPreferenceChanged];
    [self updateMotionDemand];
}
- (void)memoryWarning:(NSNotification *)notification {
    for (GMCDCaseView *view in self.views.allObjects) {
        view.failedThisActivation = YES;
        [view stopRendererKeepingStill:NO];
        [view.stillView removeFromSuperview]; view.stillView = nil;
        view.encodedArtwork = nil; view.encodedRevision = 0;
    }
    [self updateMotionDemand];
}
- (void)reconcile {
    if (self.reconciling) return;
    self.reconciling = YES;
    NSArray<GMCDCaseView *> *views = self.views.allObjects;
    GMCDCaseView *hero = nil;
    // Preserve an existing hero unless an inspector needs its one slot.
    for (GMCDCaseView *view in views) {
        if (![view eligibleForRenderer] || view.presentation == GMCDCasePresentationGrid) continue;
        if (!hero || view.presentation > hero.presentation ||
            (view.presentation == hero.presentation && view.webView && !hero.webView)) hero = view;
    }
    NSUInteger grids = 0;
    for (GMCDCaseView *view in views) {
        BOOL keep = [view eligibleForRenderer] &&
            (view.presentation == GMCDCasePresentationGrid || view == hero);
        if (view.webView && !keep) [view stopRendererKeepingStill:YES];
        if (view.webView && view.presentation == GMCDCasePresentationGrid) grids++;
    }
    if (hero && !hero.webView) [hero startRenderer];
    for (GMCDCaseView *view in views) {
        if (grids >= 6) break;
        if (view.presentation == GMCDCasePresentationGrid && !view.webView && [view eligibleForRenderer]) {
            [view startRenderer]; if (view.webView) grids++;
        }
    }
    self.reconciling = NO;
    [self updateMotionDemand];
}
- (void)stopMotion {
    [self.sampleLock lock];
    self.motionGeneration++; self.deliveryPending = NO;
    self.referenceAttitude = nil; self.latestX = 0; self.latestY = 0;
    [self.sampleLock unlock];
    [self.motionManager stopDeviceMotionUpdates];
    // CMMotionManager cancels operations in its queue, which is deliberately
    // private and never used for image work or UIKit's main operation queue.
    for (GMCDCaseView *view in self.views.allObjects) [view acceptSensorX:0 y:0];
}
- (void)updateMotionDemand {
    BOOL demand = NO;
    UIInterfaceOrientation orientation = UIInterfaceOrientationUnknown;
    NSInteger priority = -1;
    if (!self.applicationSuspended && !GMCDReducedMotion() && !self.sensorFailed) {
        for (GMCDCaseView *view in self.views.allObjects) {
            if (view.webView && view.rendered && [view eligibleForRenderer]) {
                demand = YES;
                if (view.presentation > priority) { orientation = GMCDOrientation(view.window); priority = view.presentation; }
            }
        }
    }
    if (orientation != UIInterfaceOrientationUnknown && orientation != self.motionOrientation) {
        self.motionOrientation = orientation;
        // The shared baseline belongs to the screen orientation. Restart once
        // on a real rotation so queued portrait samples cannot saturate a
        // landscape inspector, and all views use the same new reference.
        if (self.motionManager.deviceMotionActive) [self stopMotion];
    }
    if (!demand) {
        if (self.motionManager.deviceMotionActive) [self stopMotion];
        return;
    }
    if (!self.motionManager) self.motionManager = [CMMotionManager new];
    if (!self.motionManager.deviceMotionAvailable || self.motionManager.deviceMotionActive) return;
    self.motionManager.deviceMotionUpdateInterval = 1.0/30.0;
    [self.sampleLock lock];
    NSUInteger generation = ++self.motionGeneration;
    self.referenceAttitude = nil; self.deliveryPending = NO;
    [self.sampleLock unlock];
    __weak GMCDMotionHub *weakSelf = self;
    [self.motionManager startDeviceMotionUpdatesToQueue:self.motionQueue withHandler:^(CMDeviceMotion *motion, NSError *error) {
        GMCDMotionHub *hub = weakSelf; if (!hub) return;
        if (!motion || error) {
            dispatch_async(dispatch_get_main_queue(),^{
                GMCDMotionHub *current = weakSelf;
                if (!current || generation != current.motionGeneration) return;
                current.sensorFailed = YES; [current stopMotion];
            });
            return;
        }
        [hub.sampleLock lock];
        if (generation != hub.motionGeneration) { [hub.sampleLock unlock]; return; }
        if (!hub.referenceAttitude) hub.referenceAttitude = [motion.attitude copy];
        CMAttitude *relative = [motion.attitude copy];
        [relative multiplyByInverseOfAttitude:hub.referenceAttitude];
        // Apple's device roll is around its top-to-bottom (screen Y) axis;
        // pitch is around its side-to-side (screen X) axis. Keep the hub's
        // values in horizontal/yaw and vertical/pitch order, like native drag.
        CGFloat x = GMCDClamp(relative.roll/.60), y = GMCDClamp(relative.pitch/.60);
        hub.latestX = hub.latestX*.72+x*.28; hub.latestY = hub.latestY*.72+y*.28;
        if (hub.deliveryPending) { [hub.sampleLock unlock]; return; }
        hub.deliveryPending = YES;
        [hub.sampleLock unlock];
        dispatch_async(dispatch_get_main_queue(),^{
            GMCDMotionHub *current = weakSelf; if (!current) return;
            [current updateMotionDemand];
            [current.sampleLock lock];
            if (generation != current.motionGeneration) { [current.sampleLock unlock]; return; }
            CGFloat latestX = current.latestX, latestY = current.latestY;
            current.deliveryPending = NO;
            [current.sampleLock unlock];
            for (GMCDCaseView *view in current.views.allObjects)
                if (view.webView && [view eligibleForRenderer]) [view acceptSensorX:latestX y:latestY];
        });
    }];
}
@end

static NSString *GMCDEncodedArtwork(UIImage *artwork, NSUInteger maximumPixels) {
    if (!artwork.CGImage || artwork.size.width <= 0 || artwork.size.height <= 0) return nil;
    CGFloat side = GMMin(maximumPixels,GMMin(artwork.size.width*artwork.scale,artwork.size.height*artwork.scale));
    if (side < 1) return nil;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1; format.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side,side) format:format];
    UIImage *bounded = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor whiteColor] setFill]; [context fillRect:CGRectMake(0,0,side,side)];
        CGFloat factor = GMMax(side/artwork.size.width,side/artwork.size.height);
        CGFloat width = artwork.size.width*factor, height = artwork.size.height*factor;
        [artwork drawInRect:CGRectMake((side-width)/2,(side-height)/2,width,height)];
    }];
    NSData *data = UIImageJPEGRepresentation(bounded,.84);
    if (data.length > 1024*1024) data = UIImageJPEGRepresentation(bounded,.64);
    if (!data || data.length > 2*1024*1024) return nil;
    return [@"data:image/jpeg;base64," stringByAppendingString:[data base64EncodedStringWithOptions:0]];
}

@implementation GMCDScriptProxy
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    [self.owner receiveScriptMessage:message];
}
@end

@implementation GMCDCaseView
- (instancetype)initWithFrame:(CGRect)frame presentation:(GMCDCasePresentation)presentation {
    self = [super initWithFrame:frame]; if (!self) return nil;
    self.presentation = presentation; self.backgroundColor = [UIColor clearColor];
    self.opaque = NO; self.isAccessibilityElement = NO;
    self.representedIdentifier = @""; self.artworkRevision = 1;
    self.pending = [NSMutableDictionary dictionary];
    self.fallback = [[GMCDCaseFallbackView alloc] initWithFrame:self.bounds];
    [self addSubview:self.fallback];
    self.rendererStatusLabel = GMLabel(@"",11,.4,GMSecondaryTextColor());
    self.rendererStatusLabel.textAlignment = 1; self.rendererStatusLabel.numberOfLines = 2;
    self.rendererStatusLabel.userInteractionEnabled = NO; self.rendererStatusLabel.hidden = YES;
    [self addSubview:self.rendererStatusLabel];
    [GMCDSharedHub().views addObject:self];
    [self applyTheme];
    return self;
}
- (void)dealloc {
    // Neither the coordinator's weak registry nor the script proxy retains us.
    self.encodingGeneration++;
    self.artworkJob.cancelled = YES;
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"musicCD"];
    self.webView.navigationDelegate = nil;
    [self.webView stopLoading];
    GMCDMotionHub *hub = GMCDSharedHub();
    [hub.views removeObject:self];
    dispatch_async(dispatch_get_main_queue(),^{ [hub reconcile]; });
}
- (void)configureWithIdentifier:(NSString *)identifier title:(NSString *)title artist:(NSString *)artist artwork:(UIImage *)artwork {
    NSString *stable = identifier ?: @"";
    BOOL changed = ![self.representedIdentifier isEqualToString:stable] || self.artwork != artwork;
    self.representedIdentifier = stable;
    self.accessibilityLabel = [NSString stringWithFormat:@"CD case, %@%@%@",title ?: @"Album",artist.length ? @", " : @"",artist ?: @""];
    [self.fallback setArtwork:artwork];
    if (!changed) return;
    self.artwork = artwork; self.artworkRevision++;
    self.artworkJob.cancelled = YES; self.artworkJob = nil;
    self.encodingGeneration++; self.encoding = NO;
    self.encodedArtwork = nil; self.encodedRevision = 0;
    self.failedThisActivation = NO;
    [self.stillView removeFromSuperview]; self.stillView = nil;
    if (!self.rendered) self.fallback.hidden = NO;
    if (self.webView) [self ensureEncodedArtwork];
    [GMCDSharedHub() reconcile];
}
- (BOOL)eligibleForRenderer {
    if (!self.ownerActive || self.failedThisActivation || !self.window ||
        GMCDSharedHub().applicationSuspended || self.hidden || self.bounds.size.width < 2 || self.bounds.size.height < 2) return NO;
    UIWindowScene *scene = self.window.windowScene;
    if (scene && (scene.activationState != UISceneActivationStateForegroundActive ||
        [GMCDSharedHub().pausedScenes containsObject:scene])) return NO;
    CGRect visible = [self convertRect:self.bounds toView:self.window];
    if (!GMCDRectsIntersect(visible,self.window.bounds)) return NO;
    for (UIView *parent = self.superview; parent; parent = parent.superview) {
        if (parent.hidden || parent.alpha < .01) return NO;
        if (parent.clipsToBounds && !GMCDRectsIntersect(visible,[parent convertRect:parent.bounds toView:self.window])) return NO;
    }
    return YES;
}
- (void)setActive:(BOOL)active {
    if (self.ownerActive == active) { [GMCDSharedHub() reconcile]; return; }
    self.ownerActive = active;
    if (active) self.failedThisActivation = NO;
    [GMCDSharedHub() reconcile];
}
- (void)setPlaying:(BOOL)playing {
    if (_playing == playing) return;
    _playing = playing; [self queueMotionState];
}
- (void)setCaseOpen:(BOOL)open animated:(BOOL)animated {
    if (self.failedThisActivation && animated) [self retryRenderer];
    if (self.caseOpen == open && self.rendered) return;
    self.caseOpen = open;
    self.pending[@"open"] = @(open);
    self.pending[@"animateOpen"] = [NSNumber numberWithBool:(animated && !GMCDReducedMotion())];
    [self flushPending];
}
- (void)setInspectionTiltX:(CGFloat)x y:(CGFloat)y {
    self.inspectionX = GMCDClamp(x); self.inspectionY = GMCDClamp(y);
    self.pending[@"animateTilt"] = @YES;
    [self queueMotionState];
}
- (void)resetInspectionTiltAnimated:(BOOL)animated {
    self.inspectionX = 0; self.inspectionY = 0;
    self.pending[@"animateTilt"] = [NSNumber numberWithBool:(animated && !GMCDReducedMotion())];
    [self queueMotionState];
}
- (void)acceptSensorX:(CGFloat)x y:(CGFloat)y {
    // Core Motion uses device axes; map them into the inspector's actual scene
    // orientation rather than assuming the iPhone remains in portrait.
    UIInterfaceOrientation orientation = GMCDOrientation(self.window);
    if (orientation == UIInterfaceOrientationLandscapeLeft) { CGFloat swap = x; x = -y; y = swap; }
    else if (orientation == UIInterfaceOrientationLandscapeRight) { CGFloat swap = x; x = y; y = -swap; }
    else if (orientation == UIInterfaceOrientationPortraitUpsideDown) { x = -x; y = -y; }
    if (GMCDReducedMotion()) x = y = 0;
    if (self.sensorX == x && self.sensorY == y) return;
    self.sensorX = x; self.sensorY = y;
    self.pending[@"animateTilt"] = @YES;
    [self queueMotionState];
}
- (void)queueMotionState {
    BOOL reduced = GMCDReducedMotion();
    BOOL active = self.webView != nil && [self eligibleForRenderer];
    BOOL spin = self.presentation == GMCDCasePresentationPlayer ? self.playing : YES;
    self.pending[@"active"] = @(active);
    self.pending[@"playing"] = [NSNumber numberWithBool:(active && spin && !reduced)];
    self.pending[@"reducedMotion"] = @(reduced);
    // Public input is screen-space drag: X horizontal, Y vertical. The local
    // renderer uses tiltX for pitch and tiltY for yaw.
    self.pending[@"tiltX"] = @(GMCDClamp(self.inspectionY+(reduced ? 0 : self.sensorY)));
    self.pending[@"tiltY"] = @(GMCDClamp(self.inspectionX+(reduced ? 0 : self.sensorX)));
    [self flushPending];
}
- (void)motionPreferenceChanged {
    self.sensorX = self.sensorY = 0;
    [self queueMotionState];
}
- (void)applyTheme {
    [self.fallback applyTheme];
    CGFloat r=0,g=0,b=0;
    GMReadRGB(GMPageColor(),self.traitCollection,&r,&g,&b);
    NSArray *components = @[@(r),@(g),@(b)];
    if (![self.backgroundComponents isEqual:components]) {
        self.backgroundComponents = components;
        self.pending[@"background"] = components;
        [self.stillView removeFromSuperview]; self.stillView = nil;
        if (!self.rendered) self.fallback.hidden = NO;
        [self flushPending];
    }
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection]; [self applyTheme];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.webView.frame = self.bounds; self.fallback.frame = self.bounds; self.stillView.frame = self.bounds;
    self.rendererStatusLabel.frame = CGRectMake(4,GMMax(0,self.bounds.size.height-28),GMMax(0,self.bounds.size.width-8),28);
    [GMCDSharedHub() reconcile];
}
- (void)didMoveToWindow {
    [super didMoveToWindow]; [self applyTheme]; [GMCDSharedHub() reconcile];
}
- (void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
    if (self.fallback) [GMCDSharedHub() reconcile];
}
- (void)prepareForReuse {
    self.ownerActive = NO; [self stopRendererKeepingStill:NO];
    self.representedIdentifier = @""; self.artwork = nil;
    self.artworkRevision++; self.encodingGeneration++; self.encoding = NO;
    self.artworkJob.cancelled = YES; self.artworkJob = nil;
    self.encodedArtwork = nil; self.encodedRevision = 0;
    self.caseOpen = NO; self.inspectionX = self.inspectionY = 0; self.sensorX = self.sensorY = 0;
    self.failedThisActivation = NO; self.automaticRetries = 0; self.rendererFailureReason = nil;
    [self showRendererStatus:nil];
    [self.stillView removeFromSuperview]; self.stillView = nil;
    [self.fallback setArtwork:nil]; self.fallback.hidden = NO;
    self.pending = [NSMutableDictionary dictionary];
    [GMCDSharedHub() reconcile];
}
- (void)ensureEncodedArtwork {
    if (self.encodedRevision == self.artworkRevision || self.encoding) return;
    if (!self.artwork.CGImage) {
        self.encodedArtwork = nil; self.encodedRevision = self.artworkRevision;
        self.pending[@"art"] = [NSNull null]; [self flushPending]; return;
    }
    self.encoding = YES;
    NSUInteger generation = ++self.encodingGeneration, revision = self.artworkRevision;
    NSUInteger maximum = self.presentation == GMCDCasePresentationGrid ? 512 : 1024;
    UIImage *artwork = self.artwork;
    GMCDArtworkJob *job = [GMCDArtworkJob new]; self.artworkJob = job;
    __weak GMCDCaseView *weakSelf = self;
    [GMCDSharedHub().artworkQueue addOperationWithBlock:^{
        @autoreleasepool {
            if (job.cancelled) return;
            NSString *encoded = GMCDEncodedArtwork(artwork,maximum);
            if (job.cancelled) return;
            dispatch_async(dispatch_get_main_queue(),^{
                GMCDCaseView *view = weakSelf;
                if (!view || view.encodingGeneration != generation || view.artworkRevision != revision) return;
                view.artworkJob = nil;
                view.encoding = NO; view.encodedArtwork = encoded; view.encodedRevision = revision;
                view.pending[@"art"] = encoded ?: (id)[NSNull null];
                [view flushPending];
            });
        }
    }];
}
- (void)startRenderer {
    if (self.webView || ![self eligibleForRenderer]) return;
    // The guest app reads its own signed, bundled JavaScript. WebContent does
    // not need permission to traverse a LiveContainer guest's bundle path.
    NSURL *scriptURL = [[NSBundle mainBundle] URLForResource:@"music-cd" withExtension:@"js" subdirectory:@"CDCase"];
    NSData *scriptData = scriptURL ? [NSData dataWithContentsOfURL:scriptURL options:0 error:NULL] : nil;
    NSString *source = scriptData.length && scriptData.length < 4*1024*1024 ? [[NSString alloc] initWithData:scriptData encoding:4] : nil;
    if (!source.length) { [self recordRendererFailure:@"bundled-renderer-missing"]; [self failRenderer]; return; }
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    configuration.websiteDataStore = GMCDSharedHub().dataStore;
    WKUserContentController *controller = [WKUserContentController new];
    self.scriptProxy = [GMCDScriptProxy new]; self.scriptProxy.owner = self;
    [controller addScriptMessageHandler:self.scriptProxy name:@"musicCD"];
    [controller addUserScript:[[WKUserScript alloc] initWithSource:source injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES]];
    configuration.userContentController = controller;
    WKWebView *web = [[WKWebView alloc] initWithFrame:self.bounds configuration:configuration];
    web.userInteractionEnabled = NO; web.accessibilityElementsHidden = YES;
    web.opaque = NO; web.backgroundColor = [UIColor clearColor];
    web.underPageBackgroundColor = [UIColor clearColor];
    web.scrollView.backgroundColor = [UIColor clearColor]; web.scrollView.scrollEnabled = NO;
    web.scrollView.contentInsetAdjustmentBehavior = 2;
    web.scrollView.showsVerticalScrollIndicator = NO; web.scrollView.showsHorizontalScrollIndicator = NO;
    web.allowsBackForwardNavigationGestures = NO; web.allowsLinkPreview = NO; web.navigationDelegate = self;
    self.webView = web; self.rendererGeneration++; self.rendererArtworkRevision = self.artworkRevision;
    self.bridgeReady = NO; self.rendered = NO; self.evaluating = NO; self.rendererFailureReason = nil;
    // The real renderer must not be occluded by its own placeholder while
    // waiting for WebKit's first-frame acknowledgement.
    [self addSubview:web]; [self bringSubviewToFront:self.rendererStatusLabel];
    [self showRendererStatus:@"Loading 3D case…"];
    self.pending = [NSMutableDictionary dictionary];
    self.pending[@"quality"] = self.presentation == GMCDCasePresentationGrid ? @"grid" : @"hero";
    self.pending[@"background"] = self.backgroundComponents ?: @[@1,@1,@1];
    self.pending[@"open"] = @(self.caseOpen); self.pending[@"animateOpen"] = @NO;
    self.pending[@"art"] = self.encodedArtwork ?: (id)[NSNull null];
    [self queueMotionState]; [self ensureEncodedArtwork];
    NSString *html = @"<!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no'><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src data:; connect-src 'none'; font-src 'none'; media-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'\"><style>html,body,#case{position:absolute;inset:0;width:100%;height:100%;margin:0;padding:0;overflow:hidden;background:transparent;touch-action:none;-webkit-user-select:none}canvas{display:block;width:100%;height:100%;background:transparent}</style></head><body><div id='case'></div></body></html>";
    [web loadHTMLString:html baseURL:nil];
    NSUInteger generation = self.rendererGeneration;
    __weak GMCDCaseView *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(60*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        GMCDCaseView *view = weakSelf;
        if (!view || view.rendererGeneration != generation || view.rendered || !view.ownerActive) return;
        [view recordRendererFailure:@"first-frame-timeout"]; [view failRenderer];
    });
}
- (void)showRendererStatus:(NSString *)message {
    self.rendererStatusLabel.text = message; self.rendererStatusLabel.hidden = !message.length;
    [self setNeedsLayout];
}
- (void)recordRendererFailure:(NSString *)reason {
    self.rendererFailureReason = reason ?: @"unknown-renderer-error";
    NSLog(@"Music CD renderer: %@",self.rendererFailureReason);
}
- (void)retryRenderer {
    self.failedThisActivation = NO; self.automaticRetries = 0;
    [self stopRendererKeepingStill:NO]; [GMCDSharedHub() reconcile];
}
- (void)checkBridgeAfterNavigation {
    NSUInteger generation = self.rendererGeneration;
    __weak GMCDCaseView *weakSelf = self;
    [self.webView evaluateJavaScript:@"typeof window.MusicCD === 'object'" completionHandler:^(id result,NSError *error) {
        GMCDCaseView *view = weakSelf;
        if (!view || view.rendererGeneration != generation) return;
        if (!error && [result respondsToSelector:@selector(boolValue)] && [result boolValue]) {
            view.bridgeReady = YES; [view queueMotionState]; [view flushPending];
        } else { [view recordRendererFailure:@"bootstrap-not-installed"]; [view failRenderer]; }
    }];
}
- (void)stopRendererKeepingStill:(BOOL)keepStill {
    WKWebView *web = self.webView;
    if (!web) {
        if (!keepStill) { [self.stillView removeFromSuperview]; self.stillView = nil; self.fallback.hidden = NO; }
        return;
    }
    // A render-server snapshot is synchronous and does not keep an asynchronous
    // WebKit snapshot request/context alive after the slot has been released.
    BOOL artworkMatches = self.rendererArtworkRevision == self.artworkRevision;
    UIView *still = keepStill && self.rendered && artworkMatches && web.window ? [web snapshotViewAfterScreenUpdates:NO] : nil;
    if (still) {
        still.userInteractionEnabled = NO; still.accessibilityElementsHidden = YES; still.frame = self.bounds;
        [self.stillView removeFromSuperview]; self.stillView = still;
        [self addSubview:still];
    } else if (!keepStill) { [self.stillView removeFromSuperview]; self.stillView = nil; }
    self.fallback.hidden = self.stillView != nil;
    self.rendererGeneration++; self.encodingGeneration++; self.encoding = NO;
    self.artworkJob.cancelled = YES; self.artworkJob = nil;
    self.bridgeReady = NO; self.rendered = NO; self.evaluating = NO;
    self.scriptProxy.owner = nil;
    [web.configuration.userContentController removeScriptMessageHandlerForName:@"musicCD"];
    web.navigationDelegate = nil;
    [web evaluateJavaScript:@"if(window.MusicCD){window.MusicCD.receive({active:false});}void 0;" completionHandler:nil];
    [web stopLoading]; [web removeFromSuperview];
    self.webView = nil; self.scriptProxy = nil;
    self.pending = [NSMutableDictionary dictionary];
}
- (void)flushPending {
    if (!self.webView || !self.bridgeReady || self.evaluating || !self.pending.count) return;
    // Commands and first-frame rendering must not wait for artwork decoding.
    // The separately queued data image replaces the initial disc when ready.
    NSDictionary *payload = [self.pending copy];
    self.pending = [NSMutableDictionary dictionary];
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    NSString *json = data ? [[NSString alloc] initWithData:data encoding:4] : nil;
    if (!json) { [self failRenderer]; return; }
    NSString *script = [NSString stringWithFormat:@"window.MusicCD.receive(%@);void 0;",json];
    self.evaluating = YES;
    NSUInteger generation = self.rendererGeneration;
    __weak GMCDCaseView *weakSelf = self;
    [self.webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        GMCDCaseView *view = weakSelf;
        if (!view || view.rendererGeneration != generation || !view.webView) return;
        view.evaluating = NO;
        if (error) { [view recordRendererFailure:[NSString stringWithFormat:@"javascript-%ld",(long)error.code]]; [view failRenderer]; return; }
        [view flushPending];
    }];
}
- (void)receiveScriptMessage:(WKScriptMessage *)message {
    if (message.webView != self.webView || !message.frameInfo.mainFrame ||
        ![message.name isEqualToString:@"musicCD"] || ![message.body isKindOfClass:[NSDictionary class]]) return;
    NSString *type = ((NSDictionary *)message.body)[@"type"];
    if (![type isKindOfClass:[NSString class]]) return;
    if ([type isEqualToString:@"ready"]) { self.bridgeReady = YES; [self flushPending]; }
    else if ([type isEqualToString:@"rendered"]) {
        self.rendered = YES;
        [self.stillView removeFromSuperview]; self.stillView = nil;
        self.fallback.hidden = YES; self.automaticRetries = 0; [self showRendererStatus:nil];
        [GMCDSharedHub() updateMotionDemand];
    } else if ([type isEqualToString:@"failed"]) {
        id reason = ((NSDictionary *)message.body)[@"reason"];
        [self recordRendererFailure:[reason isKindOfClass:[NSString class]] ? reason : @"webgl-initialization"];
        [self failRenderer];
    }
    // artFallback is nonfatal: the renderer uses its bundled generated disc.
}
- (void)failRenderer {
    self.failedThisActivation = YES;
    [self stopRendererKeepingStill:NO];
    [self showRendererStatus:@"3D case unavailable"];
    [GMCDSharedHub() reconcile];
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = action.request.URL;
    BOOL local = webView == self.webView && [url.absoluteString isEqualToString:@"about:blank"];
    decisionHandler(local ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (webView == self.webView) [self checkBridgeAfterNavigation];
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (webView == self.webView) [self failRenderer];
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (webView == self.webView) [self failRenderer];
}
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    if (webView != self.webView) return;
    [self recordRendererFailure:@"web-content-process-terminated"]; [self failRenderer];
    if (self.automaticRetries >= 1) return;
    self.automaticRetries++;
    NSUInteger generation = self.rendererGeneration;
    __weak GMCDCaseView *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.8*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        GMCDCaseView *view = weakSelf;
        if (!view || view.rendererGeneration != generation || !view.ownerActive) return;
        view.failedThisActivation = NO; [GMCDSharedHub() reconcile];
    });
}
@end
