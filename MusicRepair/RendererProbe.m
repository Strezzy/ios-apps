// Native regression harness. Imports the production implementation, not a mock
// renderer. No probe classes or fixture media are compiled into the released app.
#define main GMOriginalMain
#import "../Music/Sources/main.m"
#undef main

static GMMusicShell *GMProbeShell;
static NSString *GMProbeDocuments(void) { return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject; }
static void GMProbeJSON(NSString *name,id object) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:[GMProbeDocuments() stringByAppendingPathComponent:name] atomically:YES];
}
@interface GMProbeInspector : GMCDAlbumInspector
@property(nonatomic,strong) NSMutableArray *samples;
@property(nonatomic,strong) NSMutableDictionary *checks;
@property(nonatomic,strong) NSTimer *probeTimer;
@property(nonatomic) NSInteger ticks;
@property(nonatomic) NSInteger readyTicks;
@property(nonatomic) NSInteger playerTicks;
@property(nonatomic) BOOL sampling;
@property(nonatomic) double initialSpin;
@property(nonatomic) double pausedSpin;
@end
@implementation GMProbeInspector
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if(self.probeTimer)return;
    self.samples=[NSMutableArray new];self.checks=[NSMutableDictionary new];
    BOOL value=YES;
    NSDictionary *boxed=@{@"oldLogicalExpression":@(value && value),@"fixedLogicalExpression":[NSNumber numberWithBool:(value && value)]};
    NSData *bytes=[NSJSONSerialization dataWithJSONObject:boxed options:0 error:nil];
    NSString *json=[[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];
    NSLog(@"BOOLEAN_REGRESSION %@",json);
    self.checks[@"typed_boolean_regression"]=@([json containsString:@"\"oldLogicalExpression\":1"] && [json containsString:@"\"fixedLogicalExpression\":true"]);
    self.probeTimer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(probe:) userInfo:nil repeats:YES];
}
- (void)capture:(NSString *)name {
    WKWebView *web=self.caseView.webView;
    if(!web)return;
    WKSnapshotConfiguration *configuration=[WKSnapshotConfiguration new];
    configuration.rect=web.bounds; configuration.afterScreenUpdates=YES;
    [web takeSnapshotWithConfiguration:configuration completionHandler:^(UIImage *image,NSError *error){
        if(image) [UIImagePNGRepresentation(image) writeToFile:[GMProbeDocuments() stringByAppendingPathComponent:name] atomically:YES];
        else NSLog(@"SNAPSHOT_ERROR %@ %@",name,error);
    }];
}
- (void)probe:(NSTimer *)timer {
    self.ticks++;
    if(self.ticks>130) { self.checks[@"timeout"]=@NO; [self finish]; return; }
    if(self.sampling||!self.caseView.webView)return;
    self.sampling=YES;
    [self.caseView.webView evaluateJavaScript:@"window.MusicCD ? JSON.stringify(window.MusicCD.diagnostics()) : null" completionHandler:^(id result,NSError *error){
        self.sampling=NO;
        NSDictionary *state=[result isKindOfClass:NSString.class] ? [NSJSONSerialization JSONObjectWithData:[result dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
        NSMutableDictionary *sample=[@{@"tick":@(self.ticks),@"nativeRendered":@(self.caseView.rendered),@"nativeReady":@(self.caseView.bridgeReady),@"failure":self.caseView.rendererFailureReason?:@"",@"state":state?:@{}} mutableCopy];
        [self.samples addObject:sample];
        NSLog(@"RENDERER_SAMPLE %@",sample);
        GMProbeJSON(@"samples.json",self.samples);
        if(!self.caseView.rendered||![state[@"ready"] boolValue])return;
        if(self.playerTicks>0) { [self probePlayer:state]; return; }
        self.readyTicks++;
        NSInteger t=self.readyTicks;
        double spin=[state[@"spin"] doubleValue];
        if(t==1){
            self.initialSpin=spin;
            self.checks[@"native_first_frame"]=@YES;
            self.checks[@"in_memory_bootstrap"]=@([self.caseView.webView.URL.absoluteString isEqualToString:@"about:blank"]);
            self.checks[@"real_geometry"]=@([state[@"geometryCount"] integerValue]>=7);
            self.checks[@"artwork_encoded"]=@(self.caseView.encodedArtwork.length>0);
        }
        if(t==4){
            self.checks[@"disc_spins"]=@(spin>self.initialSpin+.02 && [state[@"playing"] boolValue]);
            [self capture:@"Native-Closed.png"];
        }
        if(t==5){
            self.checks[@"open_button_enabled"]=@(self.caseButton.enabled);
            [self.caseButton sendActionsForControlEvents:UIControlEventTouchUpInside];
        }
        if(t==11){
            self.checks[@"open_button_opens_lid"]=@([state[@"open"] boolValue] && [state[@"phase"] isEqualToString:@"open"]);
            [self capture:@"Native-Open.png"];
            [self beginHeldInspection]; [self updateHeldInspectionTranslation:CGPointMake(90,-35)];
        }
        if(t==15){
            self.checks[@"native_drag_changes_pose"]=@(fabs([state[@"tiltX"] doubleValue])+fabs([state[@"tiltY"] doubleValue])>.1);
            [self capture:@"Native-Tilt.png"];
            [self finishHeldInspection];
            [self.caseButton sendActionsForControlEvents:UIControlEventTouchUpInside];
        }
        if(t==21){
            self.checks[@"close_button_closes_lid"]=@(![state[@"open"] boolValue] && [state[@"phase"] isEqualToString:@"rest"]);
            [self.nextButton sendActionsForControlEvents:UIControlEventTouchUpInside];
        }
        if(t==25){
            self.checks[@"next_album_updates_disc"]=@([self.caseView.representedIdentifier isEqualToString:GMProbeShell.albums[1].identifier]);
            [self capture:@"Native-Next-Album.png"];
            [self.caseView setActive:NO]; [self.caseView removeFromSuperview];
            self.caseView=[[GMCDCaseView alloc] initWithFrame:self.faceArea.bounds presentation:GMCDCasePresentationPlayer];
            self.caseView.userInteractionEnabled=NO;
            [self.caseView configureWithIdentifier:@"playback-probe" title:@"Playback" artist:@"Test" artwork:GMProbeShell.albums.firstObject.artwork];
            [self.faceArea addSubview:self.caseView];
            [self.caseView setPlaying:YES]; [self.caseView setActive:YES]; self.playerTicks=1;
        }
    }];
}
- (void)probePlayer:(NSDictionary *)state {
    NSInteger t=self.playerTicks++;
    double spin=[state[@"spin"] doubleValue];
    if(t==1) self.initialSpin=spin;
    if(t==4){
        self.checks[@"player_spins_while_playing"]=@(spin>self.initialSpin+.02 && [state[@"playing"] boolValue]);
        [self.caseView setPlaying:NO];
    }
    if(t==9)self.pausedSpin=spin;
    if(t==12){
        self.checks[@"pause_stops_disc"]=@(fabs(spin-self.pausedSpin)<.005 && ![state[@"playing"] boolValue]);
        [self.caseView setPlaying:YES];self.initialSpin=spin;
    }
    if(t==16){
        self.checks[@"resume_restarts_disc"]=@(spin>self.initialSpin+.02 && [state[@"playing"] boolValue]);
        [self.caseView acceptSensorX:.55 y:-.35];
    }
    if(t==19){
        self.checks[@"motion_bridge_changes_pose"]=@(fabs([state[@"tiltX"] doubleValue])+fabs([state[@"tiltY"] doubleValue])>.1);
        self.checks[@"no_renderer_failure"]=@(![state[@"failed"] boolValue] && !self.caseView.failedThisActivation);
        [self capture:@"Native-Player.png"];
        [self finish];
    }
}
- (void)finish {
    [self.probeTimer invalidate];self.probeTimer=nil;
    BOOL passed=self.checks.count>=14;
    for(NSNumber *value in self.checks.allValues)passed=passed&&value.boolValue;
    GMProbeJSON(@"result.json",@{@"passed":@(passed),@"checks":self.checks,@"samples":self.samples,@"physicalDeviceTested":@NO});
    NSLog(@"RENDERER_RESULT %@",self.checks);
}
@end

@interface GMProbeScene : NSObject <UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation GMProbeScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    GMProbeShell=[GMMusicShell new];[GMProbeShell loadViewIfNeeded];
    NSMutableArray *tracks=[NSMutableArray new];
    NSArray *covers=@[@"IconAuroraPreview",@"IconChromePreview",@"IconNoirPreview",@"AppIcon1024",@"IconSignalPreview",@"IconIvoryPreview"];
    for(NSInteger i=0;i<6;i++){
        GMTrack *t=[GMTrack new];t.title=[NSString stringWithFormat:@"Track %ld",(long)i+1];t.artist=@"Renderer Test";
        t.album=[NSString stringWithFormat:@"Album %ld",(long)i+1];t.albumArtist=t.artist;t.metadataLoaded=YES;
        t.url=[[NSBundle mainBundle] URLForResource:@"Glass-Study" withExtension:@"wav"];
        t.artwork=[UIImage imageNamed:covers[i]];t.trackNumber=1;t.discNumber=1;[tracks addObject:t];
    }
    GMProbeShell.player.tracks=tracks;GMProbeShell.albums=GMAlbumsForTracks(tracks);
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController=[[GMProbeInspector alloc] initWithShell:GMProbeShell albumIdentifier:GMProbeShell.albums.firstObject.identifier];
    [self.window makeKeyAndVisible];
}
@end
@interface GMProbeApp : NSObject <UIApplicationDelegate> @end
@implementation GMProbeApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {GMLoadPersonalization();return YES;}
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *c=[[UISceneConfiguration alloc] initWithName:@"Probe" sessionRole:session.role];c.delegateClass=GMProbeScene.class;return c;
}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(GMProbeApp.class));}}
