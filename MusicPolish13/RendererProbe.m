// Native regression harness. Imports production code, not a mock renderer.
// Probe classes and fixtures are never compiled into the released application.
#define main GMOriginalMain
#import "../Music/Sources/main.m"
#undef main
static GMMusicShell *GMProbeShell;
static NSString *GMProbeDocuments(void){return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;}
static void GMProbeJSON(NSString *name,id object){[[NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[GMProbeDocuments() stringByAppendingPathComponent:name] atomically:YES];}
@interface GMProbeInspector : GMCDAlbumInspector
@property(nonatomic,strong) NSMutableArray *samples;
@property(nonatomic,strong) NSMutableDictionary *checks;
@property(nonatomic,strong) NSTimer *probeTimer;
@property(nonatomic) NSInteger ticks;
@property(nonatomic) NSInteger readyTicks;
@property(nonatomic) NSInteger playerTicks;
@property(nonatomic) NSInteger pendingCaptures;
@property(nonatomic) BOOL sampling;
@property(nonatomic) BOOL finishing;
@property(nonatomic) double initialSpin;
@property(nonatomic) double pausedSpin;
@property(nonatomic) double coldSeconds;
- (void)startPlayerProbe;
- (void)writeResult;
@end
@implementation GMProbeInspector
- (void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];if(self.probeTimer)return;
    self.samples=[NSMutableArray new];self.checks=[NSMutableDictionary new];
    BOOL value=YES;
    NSDictionary *boxed=@{@"oldLogicalExpression":@(value&&value),@"fixedLogicalExpression":[NSNumber numberWithBool:(value&&value)]};
    NSString *json=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:boxed options:0 error:nil] encoding:NSUTF8StringEncoding];
    NSLog(@"BOOLEAN_REGRESSION %@",json);
    self.checks[@"typed_boolean_regression"]=@([json containsString:@"\"oldLogicalExpression\":1"]&&[json containsString:@"\"fixedLogicalExpression\":true"]);
    self.probeTimer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(probe:) userInfo:nil repeats:YES];
}
- (void)capture:(NSString *)name{
    WKWebView *web=self.caseView.webView;if(!web)return;
    self.pendingCaptures++;
    WKSnapshotConfiguration *configuration=[WKSnapshotConfiguration new];configuration.rect=web.bounds;configuration.afterScreenUpdates=YES;
    [web takeSnapshotWithConfiguration:configuration completionHandler:^(UIImage *image,NSError *error){
        if(image)[UIImagePNGRepresentation(image) writeToFile:[GMProbeDocuments() stringByAppendingPathComponent:name] atomically:YES];
        else{NSLog(@"SNAPSHOT_ERROR %@ %@",name,error);self.checks[[name stringByAppendingString:@"_capture"]]=@NO;}
        self.pendingCaptures--;
        // Do not destroy this WKWebView until its asynchronous snapshot has
        // completed. This is a harness lifecycle requirement, not an app fix.
        if([name isEqualToString:@"Native-Next-Album.png"])[self startPlayerProbe];
        if(self.finishing&&self.pendingCaptures==0)[self writeResult];
    }];
}
- (void)probe:(NSTimer *)timer{
    self.ticks++;
    if(self.ticks>130){self.checks[@"timeout"]=@NO;[self finish];return;}
    if(self.sampling||!self.caseView.webView)return;
    self.sampling=YES;
    [self.caseView.webView evaluateJavaScript:@"window.MusicCD ? JSON.stringify(window.MusicCD.diagnostics()) : null" completionHandler:^(id result,NSError *error){
        self.sampling=NO;
        NSDictionary *state=[result isKindOfClass:NSString.class]?[NSJSONSerialization JSONObjectWithData:[result dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]:nil;
        [self.samples addObject:@{@"tick":@(self.ticks),@"nativeRendered":@(self.caseView.rendered),@"nativeReady":@(self.caseView.bridgeReady),@"nativeFirstFrameSeconds":@(self.caseView.firstFrameSeconds),@"warmRenderer":@(self.caseView.usedWarmRenderer),@"failure":self.caseView.rendererFailureReason?:@"",@"state":state?:@{}}];
        GMProbeJSON(@"samples.json",self.samples);
        if(!self.caseView.rendered||![state[@"ready"] boolValue])return;
        if(self.playerTicks>0){[self probePlayer:state];return;}
        NSInteger t=++self.readyTicks;double spin=[state[@"spin"] doubleValue];
        if(t==1){
            self.initialSpin=spin;self.checks[@"native_first_frame"]=@YES;
            self.coldSeconds=self.caseView.firstFrameSeconds;
            self.checks[@"retina_rendering"]=@([state[@"pixelRatio"] doubleValue]>=2);
            self.checks[@"geometry_msaa"]=@([state[@"msaaSamples"] integerValue]>=2);
            self.checks[@"closed_corners_fit"]=@([state[@"fittedExtent"] doubleValue]<.99);
            self.checks[@"in_memory_bootstrap"]=@([self.caseView.webView.URL.absoluteString isEqualToString:@"about:blank"]);
            self.checks[@"real_geometry"]=@([state[@"geometryCount"] integerValue]>=7);
            self.checks[@"artwork_encoded"]=@(self.caseView.encodedArtwork.length>0);
        }
        if(t==4){self.checks[@"disc_spins"]=@(spin>self.initialSpin+.02&&[state[@"playing"] boolValue]);[self capture:@"Native-Closed.png"];}
        if(t==5){self.checks[@"open_button_enabled"]=@(self.caseButton.enabled);[self.caseButton sendActionsForControlEvents:UIControlEventTouchUpInside];}
        if(t==11){
            self.checks[@"open_button_opens_lid"]=@([state[@"open"] boolValue]&&[state[@"phase"] isEqualToString:@"open"]);
            [self capture:@"Native-Open.png"];[self beginHeldInspection];[self updateHeldInspectionTranslation:CGPointMake(90,-35)];
        }
        if(t==15){
            self.checks[@"native_drag_changes_pose"]=@(fabs([state[@"tiltX"] doubleValue])+fabs([state[@"tiltY"] doubleValue])>.1);
            [self capture:@"Native-Tilt.png"];[self finishHeldInspection];[self.caseButton sendActionsForControlEvents:UIControlEventTouchUpInside];
        }
        if(t==21){
            self.checks[@"close_button_closes_lid"]=@(![state[@"open"] boolValue]&&[state[@"phase"] isEqualToString:@"rest"]);
            [self.nextButton sendActionsForControlEvents:UIControlEventTouchUpInside];
        }
        if(t==25){
            self.checks[@"next_album_updates_disc"]=@([self.caseView.representedIdentifier isEqualToString:GMProbeShell.albums[1].identifier]);
            [self capture:@"Native-Next-Album.png"];
        }
    }];
}
- (void)startPlayerProbe{
    [self.caseView setActive:NO];[self.caseView removeFromSuperview];
    self.caseView=[[GMCDCaseView alloc] initWithFrame:self.faceArea.bounds presentation:GMCDCasePresentationPlayer];self.caseView.userInteractionEnabled=NO;
    [self.caseView configureWithIdentifier:@"playback-probe" title:@"Playback" artist:@"Test" artwork:GMProbeShell.albums.firstObject.artwork];
    [self.faceArea addSubview:self.caseView];[self.caseView setPlaying:YES];[self.caseView setActive:YES];self.playerTicks=1;
}
- (void)probePlayer:(NSDictionary *)state{
    NSInteger t=self.playerTicks++;double spin=[state[@"spin"] doubleValue];
    if(t==1){self.initialSpin=spin;
        self.checks[@"hero_reuses_compiled_renderer"]=@(self.caseView.usedWarmRenderer && GMCDSharedHub().rendererAllocations==1);
        self.checks[@"correct_artwork_ticket"]=@([state[@"epoch"] isEqual:self.caseView.renderTicket] && ![state[@"artToken"] isEqual:@"pending"]);
        GMProbeJSON(@"loading-times.json",@{@"coldHeroSeconds":@(self.coldSeconds),@"warmHeroSeconds":@(self.caseView.firstFrameSeconds),@"rendererAllocations":@(GMCDSharedHub().rendererAllocations),@"rendererReuses":@(GMCDSharedHub().rendererReuses),@"environment":@"iOS simulator; not physical iPhone timing"});
    }
    if(t==4){self.checks[@"player_spins_while_playing"]=@(spin>self.initialSpin+.02&&[state[@"playing"] boolValue]);[self.caseView setPlaying:NO];}
    if(t==9)self.pausedSpin=spin;
    if(t==12){self.checks[@"pause_stops_disc"]=@(fabs(spin-self.pausedSpin)<.005&&![state[@"playing"] boolValue]);[self.caseView setPlaying:YES];self.initialSpin=spin;}
    if(t==16){self.checks[@"resume_restarts_disc"]=@(spin>self.initialSpin+.02&&[state[@"playing"] boolValue]);[self.caseView acceptSensorX:.55 y:-.35];}
    if(t==19){
        self.checks[@"motion_bridge_changes_pose"]=@(fabs([state[@"tiltX"] doubleValue])+fabs([state[@"tiltY"] doubleValue])>.1);
        self.checks[@"no_renderer_failure"]=@(![state[@"failed"] boolValue]&&!self.caseView.failedThisActivation);
        [self capture:@"Native-Player.png"];
    }
    if(t==20){[self.caseView setCaseOpen:YES animated:NO];[self.caseView setInspectionTiltX:1 y:1];}
    if(t==23){self.checks[@"open_extreme_corners_fit"]=@([state[@"fittedExtent"] doubleValue]<.99);[self capture:@"Native-Open-Extreme.png"];[self.caseView setInspectionTiltX:-1 y:-1];}
    if(t==26){self.checks[@"opposite_extreme_corners_fit"]=@([state[@"fittedExtent"] doubleValue]<.99);[self.caseView setCaseOpen:NO animated:NO];}
    if(t>=29 && self.pendingCaptures==0){self.checks[@"closed_extreme_corners_fit"]=@([state[@"fittedExtent"] doubleValue]<.99);
        [self.caseView setActive:NO];
        self.checks[@"idle_cache_bounded"]=@(GMCDSharedHub().warmRenderers.count<=9);
        [GMCDSharedHub() memoryWarning:nil];
        self.checks[@"memory_warning_releases_cache"]=@(GMCDSharedHub().warmRenderers.count==0);
        [self finish];
    }
}
- (void)finish{
    [self.probeTimer invalidate];self.probeTimer=nil;self.finishing=YES;
    if(self.pendingCaptures==0)[self writeResult];
}
- (void)writeResult{
    BOOL passed=self.checks.count>=14;for(NSNumber *value in self.checks.allValues)passed=passed&&value.boolValue;
    GMProbeJSON(@"result.json",@{@"passed":@(passed),@"checks":self.checks,@"samples":self.samples,@"operatingSystem":NSProcessInfo.processInfo.operatingSystemVersionString,@"physicalDeviceTested":@NO});
    NSLog(@"RENDERER_RESULT %@",self.checks);
}
@end
@interface GMProbeScene : NSObject <UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation GMProbeScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options{
    GMProbeShell=[GMMusicShell new];[GMProbeShell loadViewIfNeeded];NSMutableArray *tracks=[NSMutableArray new];
    NSArray *covers=@[@"IconAuroraPreview",@"IconChromePreview",@"IconNoirPreview",@"AppIcon1024",@"IconSignalPreview",@"IconIvoryPreview"];
    for(NSInteger i=0;i<6;i++){
        GMTrack *t=[GMTrack new];t.title=[NSString stringWithFormat:@"Track %ld",(long)i+1];t.artist=@"Renderer Test";t.album=[NSString stringWithFormat:@"Album %ld",(long)i+1];t.albumArtist=t.artist;t.metadataLoaded=YES;
        t.url=[[NSBundle mainBundle] URLForResource:@"Glass-Study" withExtension:@"wav"];t.artwork=[UIImage imageNamed:covers[i]];t.trackNumber=1;t.discNumber=1;[tracks addObject:t];
    }
    GMProbeShell.player.tracks=tracks;GMProbeShell.albums=GMAlbumsForTracks(tracks);
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController=[[GMProbeInspector alloc] initWithShell:GMProbeShell albumIdentifier:GMProbeShell.albums.firstObject.identifier];[self.window makeKeyAndVisible];
}
@end
@interface GMProbeApp : NSObject <UIApplicationDelegate> @end
@implementation GMProbeApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options{GMLoadPersonalization();return YES;}
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options{
    UISceneConfiguration *c=[[UISceneConfiguration alloc] initWithName:@"Probe" sessionRole:session.role];c.delegateClass=GMProbeScene.class;return c;
}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(GMProbeApp.class));}}
