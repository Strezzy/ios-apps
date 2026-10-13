// Test harness only. Production sources and WKWebView, no replacement renderer.
#define main GMOriginalMain
#import "../Music/Sources/main.m"
#undef main

static NSString *PolishDocuments(void) { return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject; }
@interface PolishCase : GMCDCaseView
@property(nonatomic) CFTimeInterval presentedAt;
@end
@implementation PolishCase
- (void)receiveScriptMessage:(WKScriptMessage *)message {
    [super receiveScriptMessage:message];
    if ([message.body isKindOfClass:NSDictionary.class] && [message.body[@"type"] isEqual:@"presented"] && self.rendered && !self.warmParked) self.presentedAt=CACurrentMediaTime();
}
@end
@interface PolishRoot : UIViewController
@property(nonatomic,strong) PolishCase *cd;
@property(nonatomic,strong) PolishCase *donor;
@property(nonatomic,strong) WKWebView *originalWeb;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,strong) NSMutableDictionary *checks;
@property(nonatomic,strong) NSMutableDictionary *metrics;
@property(nonatomic,strong) NSMutableArray *history;
@property(nonatomic) NSInteger phase;
@property(nonatomic) NSInteger phaseTicks;
@property(nonatomic) NSInteger ticks;
@property(nonatomic) NSUInteger coldStarts;
@property(nonatomic) NSUInteger token;
@property(nonatomic) NSUInteger parkedFrames;
@property(nonatomic) BOOL busy;
@property(nonatomic) CFTimeInterval startedAt;
@end
@implementation PolishRoot
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.checks=[NSMutableDictionary new]; self.metrics=[NSMutableDictionary new]; self.history=[NSMutableArray new];
    self.cd=[[PolishCase alloc] initWithFrame:CGRectMake(20,180,196,196) presentation:GMCDCasePresentationGrid];
    [self.cd configureWithIdentifier:@"polish-a" title:@"Aurora" artist:@"Music" artwork:[UIImage imageNamed:@"IconAuroraPreview"]];
    [self.view addSubview:self.cd]; self.startedAt=CACurrentMediaTime();
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; [self.cd setActive:YES];
    if (!self.timer) self.timer=[NSTimer scheduledTimerWithTimeInterval:.5 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
}
- (void)finish {
    [self.timer invalidate]; self.timer=nil;
    BOOL passed=self.checks.count>=14; for (NSNumber *n in self.checks.allValues) passed=passed&&n.boolValue;
    NSDictionary *result=@{@"passed":@(passed),@"checks":self.checks,@"metrics":self.metrics,@"samples":self.history,@"physicalDeviceTested":@NO,@"runtime":NSProcessInfo.processInfo.operatingSystemVersionString};
    [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[PolishDocuments() stringByAppendingPathComponent:@"polish-result.json"] atomically:YES];
    NSLog(@"POLISH_RESULT %@",result);
}
- (void)advance:(NSInteger)phase {self.phase=phase;self.phaseTicks=0;}
- (void)tick:(NSTimer *)timer {
    if (++self.ticks>300) {self.checks[@"timeout"]=@NO;[self finish];return;}
    if (self.phase==9) {
        if (++self.phaseTicks>=44) {
            self.checks[@"idle_renderer_released"]=@(self.cd.webView==nil);
            [GMCDSharedHub() memoryWarning:nil];
            BOOL released=YES;for(GMCDCaseView *view in GMCDSharedHub().views.allObjects) released=released&&(view.webView==nil);
            self.checks[@"memory_warning_releases_renderers"]=@(released);[self finish];
        }
        return;
    }
    if(self.busy||!self.cd.webView)return; self.busy=YES;
    [self.cd.webView evaluateJavaScript:@"window.MusicCD ? JSON.stringify(window.MusicCD.diagnostics()) : null" completionHandler:^(id value,NSError *error){
        self.busy=NO;
        NSDictionary *state=[value isKindOfClass:NSString.class]?[NSJSONSerialization JSONObjectWithData:[value dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]:nil;
        if (!state) return;
        [self.history addObject:@{@"tick":@(self.ticks),@"phase":@(self.phase),@"rendered":@(self.cd.rendered),@"state":state}];
        if(self.phase==0 && self.cd.rendered) {
            self.metrics[@"coldFirstArtworkMilliseconds"]=@((self.cd.presentedAt-self.startedAt)*1000);
            self.metrics[@"gridPixelRatio"]=state[@"pixelRatio"]?:@0;
            self.metrics[@"msaaSamples"]=state[@"msaaSamples"]?:@0;
            self.metrics[@"reflectionRoomSize"]=state[@"roomSize"]?:@0;
            self.checks[@"correct_artwork_acknowledged"]=@([state[@"presentedToken"] unsignedIntegerValue]==self.cd.requestToken && self.cd.encodedRevision==self.cd.artworkRevision);
            self.checks[@"grid_density_2x"]=@([state[@"pixelRatio"] doubleValue]>=1.99);
            self.checks[@"supported_multisampling"]=@([state[@"msaaSamples"] integerValue]>=2);
            self.checks[@"reflection_detail_256"]=@([state[@"roomSize"] integerValue]==256);
            self.checks[@"refraction_samples"]=@([state[@"refractionSamples"] integerValue]==2);
            self.originalWeb=self.cd.webView;self.coldStarts=self.cd.coldStarts;
            [self.cd setActive:NO];[self advance:1];return;
        }
        if(self.phase==1 && ++self.phaseTicks>=4) {
            self.checks[@"parked_inactive"]=@(![state[@"active"] boolValue] && ![state[@"scheduled"] boolValue]);
            self.checks[@"parked_buffers_released"]=@([state[@"width"] integerValue]==1 && [state[@"height"] integerValue]==1);
            self.parkedFrames=[state[@"frameCount"] unsignedIntegerValue];[self advance:2];return;
        }
        if(self.phase==2 && ++self.phaseTicks>=4) {
            self.checks[@"parked_frames_stopped"]=@([state[@"frameCount"] unsignedIntegerValue]==self.parkedFrames);
            self.startedAt=CACurrentMediaTime();self.cd.presentedAt=0;[self.cd setActive:YES];[self advance:3];return;
        }
        if(self.phase==3 && self.cd.rendered && self.cd.presentedAt>0) {
            self.metrics[@"warmFirstArtworkMilliseconds"]=@((self.cd.presentedAt-self.startedAt)*1000);
            self.checks[@"warm_same_webview"]=@(self.cd.webView==self.originalWeb && self.cd.warmStarts>=1);
            self.checks[@"warm_no_new_cold_start"]=@(self.cd.coldStarts==self.coldStarts);
            self.token=self.cd.requestToken;[self.cd prepareForReuse];
            [self.cd configureWithIdentifier:@"polish-b" title:@"Chrome" artist:@"Music" artwork:[UIImage imageNamed:@"IconChromePreview"]];
            [self.cd setActive:YES];[self advance:4];return;
        }
        if(self.phase==4 && self.cd.rendered && self.cd.requestToken!=self.token) {
            self.checks[@"recycled_cover_acknowledged"]=@([state[@"presentedToken"] unsignedIntegerValue]==self.cd.requestToken && [self.cd.representedIdentifier isEqual:@"polish-b"] && self.cd.encodedRevision==self.cd.artworkRevision);
            self.checks[@"recycled_webview_reused"]=@(self.cd.webView==self.originalWeb && self.cd.coldStarts==self.coldStarts);
            [self.cd setInspectionTiltX:1 y:1];[self.cd setCaseOpen:YES animated:YES];[self advance:5];return;
        }
        if(self.phase==5 && ++self.phaseTicks>=16 && [state[@"phase"] isEqual:@"open"]) {
            self.checks[@"open_tilt_fits_viewport"]=@([state[@"clippedCorners"] integerValue]==0 && [state[@"maxProjectedExtent"] doubleValue]<=.966);
            self.metrics[@"maximumOpenProjectedExtent"]=state[@"maxProjectedExtent"]?:@0;
            self.donor=self.cd;[self.donor setActive:NO];[self.donor removeFromSuperview];
            self.cd=[[PolishCase alloc] initWithFrame:CGRectMake(20,180,196,196) presentation:GMCDCasePresentationGrid];
            [self.cd configureWithIdentifier:@"polish-c" title:@"Signal" artist:@"Music" artwork:[UIImage imageNamed:@"IconSignalPreview"]];
            [self.view addSubview:self.cd];[self.cd setActive:YES];[self advance:6];return;
        }
        if(self.phase==6 && self.cd.rendered) {
            self.checks[@"donor_page_transferred"]=@(self.cd.webView==self.originalWeb && self.donor.webView==nil && self.cd.coldStarts==0);
            self.checks[@"donor_new_cover_acknowledged"]=@([state[@"presentedToken"] unsignedIntegerValue]==self.cd.requestToken && [self.cd.representedIdentifier isEqual:@"polish-c"]);
            [self.cd setInspectionTiltX:-1 y:-1];[self advance:7];return;
        }
        if(self.phase==7 && ++self.phaseTicks>=6) {
            self.checks[@"closed_tilt_fits_viewport"]=@([state[@"clippedCorners"] integerValue]==0 && [state[@"maxProjectedExtent"] doubleValue]<=.966);
            self.checks[@"no_renderer_failure"]=@(!self.cd.failedThisActivation && ![state[@"failed"] boolValue]);
            NSUInteger grids=0,heroes=0;
            for(GMCDCaseView *view in GMCDSharedHub().views.allObjects) if(view.webView){if(view.presentation==GMCDCasePresentationGrid)grids++;else heroes++;}
            self.checks[@"bounded_renderer_count"]=@(grids<=6 && heroes<=1);
            [self.cd setActive:NO];[self advance:9];return;
        }
    }];
}
@end
@interface PolishScene : NSObject <UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation PolishScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];self.window.rootViewController=[PolishRoot new];[self.window makeKeyAndVisible];
}
@end
@interface PolishApp : NSObject <UIApplicationDelegate> @end
@implementation PolishApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options{GMLoadPersonalization();return YES;}
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options{UISceneConfiguration *c=[[UISceneConfiguration alloc] initWithName:@"Polish" sessionRole:session.role];c.delegateClass=PolishScene.class;return c;}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(PolishApp.class));}}
