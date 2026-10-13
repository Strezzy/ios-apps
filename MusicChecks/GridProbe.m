// Test-only full Albums screen. Uses production cells, visibility lifecycle,
// shared renderer scheduling and the native tab bar, not a separate web page.
#define main GMOriginalMain
#import "../Music/Sources/main.m"
#undef main

@interface GMGridProbeScene : NSObject <UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) GMMusicShell *shell;
@property(nonatomic,strong) NSMutableDictionary *initialSpins;
@property(nonatomic,strong) NSMutableArray *history;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic) BOOL busy;
@property(nonatomic) NSInteger ticks;
@end
@implementation GMGridProbeScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.shell=[GMMusicShell new];[self.shell loadViewIfNeeded];
    NSMutableArray *tracks=[NSMutableArray new];
    NSArray *covers=@[@"IconAuroraPreview",@"IconChromePreview",@"IconNoirPreview",@"AppIcon1024",@"IconSignalPreview",@"IconIvoryPreview"];
    for(NSInteger i=0;i<6;i++){
        GMTrack *track=[GMTrack new];track.title=[NSString stringWithFormat:@"Track %ld",(long)i+1];
        track.artist=@"Music";track.album=[NSString stringWithFormat:@"Collection %ld",(long)i+1];
        track.albumArtist=track.artist;track.metadataLoaded=YES;
        track.url=[NSURL fileURLWithPath:[NSString stringWithFormat:@"/tmp/fixture-%ld.wav",(long)i]];
        track.artwork=[UIImage imageNamed:covers[i]];track.trackNumber=1;track.discNumber=1;[tracks addObject:track];
    }
    self.shell.player.tracks=tracks;self.shell.albums=GMAlbumsForTracks(tracks);
    self.shell.selectedIndex=1;
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];self.window.rootViewController=self.shell;
    [self.window makeKeyAndVisible];[self.shell.albumsController.table reloadData];
    self.initialSpins=[NSMutableDictionary new];self.history=[NSMutableArray new];
    self.timer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
}
- (void)tick:(NSTimer *)timer {
    self.ticks++;
    if(self.busy)return;
    self.busy=YES;
    NSMutableArray *samples=[NSMutableArray new];dispatch_group_t group=dispatch_group_create();
    for(GMCDCaseView *view in GMCDSharedHub().views.allObjects){
        if(view.presentation!=GMCDCasePresentationGrid || !view.ownerActive || !view.window)continue;
        NSString *key=view.representedIdentifier;
        NSMutableDictionary *sample=[@{@"identifier":key?:@"",@"rendered":@(view.rendered),@"width":@(view.bounds.size.width),@"height":@(view.bounds.size.height),@"eligible":@([view eligibleForRenderer]),@"webView":@(view.webView!=nil)} mutableCopy];
        [samples addObject:sample];if(!view.webView)continue;
        dispatch_group_enter(group);
        [view.webView evaluateJavaScript:@"window.MusicCD ? JSON.stringify(window.MusicCD.diagnostics()) : null" completionHandler:^(id result,NSError *error){
            NSDictionary *state=[result isKindOfClass:NSString.class] ? [NSJSONSerialization JSONObjectWithData:[result dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
            sample[@"state"]=state?:@{};
            if(state[@"spin"]&&!self.initialSpins[key])self.initialSpins[key]=state[@"spin"];
            dispatch_group_leave(group);
        }];
    }
    dispatch_group_notify(group,dispatch_get_main_queue(),^{
        self.busy=NO;[self.history addObject:@{@"tick":@(self.ticks),@"cases":samples}];
        BOOL passed=samples.count>=4;
        for(NSDictionary *sample in samples){
            NSDictionary *state=sample[@"state"];
            passed=passed && [sample[@"rendered"] boolValue] && [state[@"ready"] boolValue] && [state[@"playing"] boolValue] && ![state[@"failed"] boolValue] && [sample[@"width"] doubleValue]>=175 && ([state[@"spin"] doubleValue]-[self.initialSpins[sample[@"identifier"]] doubleValue])>.04;
        }
        NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
        [[NSJSONSerialization dataWithJSONObject:self.history options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[documents stringByAppendingPathComponent:@"grid-samples.json"] atomically:YES];
        if(passed||self.ticks>=120){
            [timer invalidate];self.timer=nil;
            NSDictionary *result=@{@"passed":@(passed),@"visibleCaseCount":@(samples.count),@"ticks":@(self.ticks),@"nativeTabCount":@(self.shell.viewControllers.count),@"cases":samples,@"physicalDeviceTested":@NO};
            [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[documents stringByAppendingPathComponent:@"grid-result.json"] atomically:YES];
            NSLog(@"GRID_RESULT %@",result);
        }
    });
}
@end
@interface GMGridProbeApp : NSObject <UIApplicationDelegate> @end
@implementation GMGridProbeApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {GMLoadPersonalization();return YES;}
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration=[[UISceneConfiguration alloc] initWithName:@"GridProbe" sessionRole:session.role];configuration.delegateClass=GMGridProbeScene.class;return configuration;
}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(GMGridProbeApp.class));}}
