// Exercises the real native shell, AVAudioPlayer, and bundled WebKit renderer.
#define main GMOriginalMain
#import "../Music/Sources/main.m"
#undef main
static void After(double seconds, void (^block)(void)) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(seconds*NSEC_PER_SEC)),dispatch_get_main_queue(),block); }
@interface TransitionProbe : NSObject <UIWindowSceneDelegate>
@property(strong) UIWindow *window;
@property(strong) GMMusicShell *shell;
@property(strong) NSMutableDictionary *checks;
@property(strong) WKWebView *originalWeb;
@property(strong) GMCDCaseView *detail;
@property(nonatomic) double pausedSpin;
@property(nonatomic) NSInteger attempts;
@end
@implementation TransitionProbe
- (void)check:(NSString *)key value:(BOOL)value { self.checks[key]=@(value && (!self.checks[key] || [self.checks[key] boolValue])); NSLog(@"CHECK %@ %@",key,value?@"PASS":@"FAIL"); }
- (void)state:(GMCDCaseView *)view then:(void (^)(NSDictionary *))block {
    if (!view.webView) { [self check:@"renderer_present" value:NO]; block(@{}); return; }
    [view.webView evaluateJavaScript:@"JSON.stringify(window.MusicCD.diagnostics())" completionHandler:^(id result,NSError *error){
        NSDictionary *state=[result isKindOfClass:NSString.class]?[NSJSONSerialization JSONObjectWithData:[result dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]:nil;
        [self check:@"bridge_readable" value:state!=nil && !error]; block(state?:@{});
    }];
}
- (void)capture:(NSString *)name {
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:self.window.bounds.size];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){[self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:NO];}];
    [UIImagePNGRepresentation(image) writeToFile:[self.documents stringByAppendingPathComponent:name] atomically:YES];
}
- (NSString *)documents { return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject; }
- (void)finish {
    BOOL passed=self.checks.count>15;
    for(NSNumber *value in self.checks.allValues) passed=passed&&value.boolValue;
    NSDictionary *report=@{@"passed":@(passed),@"checks":self.checks,@"physicalDeviceTested":@NO,
        @"rendererAllocations":@(GMCDSharedHub().rendererAllocations),@"rendererReuses":@(GMCDSharedHub().rendererReuses)};
    [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[self.documents stringByAppendingPathComponent:@"result.json"] atomically:YES];
}
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.checks=[NSMutableDictionary new];
    self.shell=[GMMusicShell new]; [self.shell loadViewIfNeeded];
    NSMutableArray *tracks=[NSMutableArray new];
    for(NSInteger i=0;i<18;i++) {
        GMTrack *t=[GMTrack new]; t.title=[NSString stringWithFormat:@"Song %02ld",(long)i]; t.album=[NSString stringWithFormat:@"Album %02ld",(long)i];
        t.artist=@"Music"; t.albumArtist=t.artist; t.metadataLoaded=YES;
        NSString *file=[self.documents stringByAppendingPathComponent:[NSString stringWithFormat:@"track%ld.wav",(long)i]];
        [[NSFileManager defaultManager] copyItemAtPath:[[NSBundle mainBundle] pathForResource:@"fixture" ofType:@"wav"] toPath:file error:nil];
        t.url=[NSURL fileURLWithPath:file]; t.artwork=[UIImage imageNamed:i%2?@"IconAuroraPreview":@"IconChromePreview"]; [tracks addObject:t];
    }
    self.shell.player.tracks=tracks; [self.shell reloadLibrary];
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene]; self.window.rootViewController=self.shell; [self.window makeKeyAndVisible];
    After(1,^{[self waitWarm];});
    After(150,^{if(![[NSFileManager defaultManager] fileExistsAtPath:[self.documents stringByAppendingPathComponent:@"result.json"]]){[self check:@"timeout" value:NO];[self finish];}});
}
- (void)waitWarm {
    GMCDCaseView *hero=self.shell.player.cdCaseView;
    if(!hero.readyForDisplay && ++self.attempts<60){After(1,^{[self waitWarm];});return;}
    NSLog(@"WARM active=%d prewarming=%d eligible=%d window=%@ hostAlpha=%f size=%@ failure=%@",hero.ownerActive,hero.prewarming,[hero eligibleForRenderer],hero.window,hero.superview.alpha,NSStringFromCGRect(hero.bounds),hero.rendererFailureReason);
    [self check:@"hero_prewarmed" value:hero.readyForDisplay && hero.prewarming];
    self.originalWeb=hero.webView;
    [self state:hero then:^(NSDictionary *state){
        [self check:@"warm_has_no_spin" value:![state[@"playing"] boolValue] && ![state[@"scheduled"] boolValue]];
        [self check:@"warm_has_no_motion_subscription" value:!GMCDSharedHub().motionManager.deviceMotionActive];
        UITableView *table=self.shell.songsController.table;
        BOOL staticRows=table.visibleCells.count>3;
        for(GMBrowseSongCell *cell in table.visibleCells) staticRows=staticRows && !cell.rowCase.hidden && !cell.rowCase.webView && !cell.rowCase.encoding && cell.rowImage.hidden;
        [self check:@"songs_are_static_cases" value:staticRows]; [self capture:@"Songs.png"];
        [self.shell.songsController tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
        After(.35,^{
            [self check:@"song_starts_player_transition" value:self.shell.player.caseTransitionInProgress && self.shell.player.player.isPlaying];
            [self check:@"same_webview_during_flight" value:self.shell.player.cdCaseView.webView==self.originalWeb];
            [self capture:@"Transition.png"];
        });
        After(5,^{[self checkPlayer];});
    }];
}
- (void)checkPlayer {
    PlayerController *player=self.shell.player; GMCDCaseView *hero=player.cdCaseView;
    [self state:hero then:^(NSDictionary *state){
        [self check:@"song_opens_now_playing" value:player.presentingViewController!=nil && !player.caseTransitionInProgress];
        [self check:@"hero_attached_to_player" value:hero.superview==player.artView && hero.webView==self.originalWeb && hero.readyForDisplay];
        [self check:@"playing_opens_and_spins" value:[state[@"open"] boolValue] && [state[@"playing"] boolValue] && [state[@"phase"] isEqual:@"open"]];
        [self check:@"correct_song_art_ready" value:[state[@"artToken"] isEqual:[NSString stringWithFormat:@"%lu",(unsigned long)hero.artworkRevision]]];
        [self capture:@"Player-Open.png"];
        [player nextTrack];
        After(.5,^{[self state:hero then:^(NSDictionary *next){
            [self check:@"next_track_keeps_spinning" value:player.player.isPlaying && [next[@"playing"] boolValue]];
            [player previousTrack];
            After(.5,^{[self state:hero then:^(NSDictionary *previous){
                [self check:@"previous_track_keeps_spinning" value:player.player.isPlaying && [previous[@"playing"] boolValue]];
                [player pause];
            }];});
        }];});
        After(4,^{[self state:hero then:^(NSDictionary *paused){
            [self check:@"pause_closes_and_stops" value:![paused[@"open"] boolValue] && ![paused[@"playing"] boolValue] && [paused[@"phase"] isEqual:@"rest"]];
            self.pausedSpin=[paused[@"spin"] doubleValue]; [hero acceptSensorX:.5 y:-.3];
            After(1,^{[self state:hero then:^(NSDictionary *tilted){
                [self check:@"paused_disc_stays_still" value:fabs([tilted[@"spin"] doubleValue]-self.pausedSpin)<.01];
                [self check:@"paused_case_keeps_gyro" value:fabs([tilted[@"tiltX"] doubleValue])>.01 && fabs([tilted[@"tiltY"] doubleValue])>.01];
                [self capture:@"Player-Paused.png"]; [player play];
                After(.2,^{[player pause];After(.2,^{[player play];});});
                After(5,^{[self state:hero then:^(NSDictionary *resumed){
                    [self check:@"rapid_play_pause_settles_open" value:[resumed[@"open"] boolValue] && [resumed[@"phase"] isEqual:@"open"]];
                    [player closeNowPlaying]; After(1,^{[self checkGrid];});
                }];});
            }];});
        }];});
    }];
}
- (void)checkGrid {
    [self check:@"dismissal_retains_warm_renderer" value:self.shell.player.cdCaseView.prewarming && self.shell.player.cdCaseView.webView==self.originalWeb];
    self.shell.selectedIndex=1;
    After(1,^{
        BOOL staticGrid=YES; NSInteger tiles=0;
        for(GMAlbumGridCell *cell in self.shell.albumsController.table.visibleCells) {
            for(GMAlbumTile *tile in @[cell.leftTile,cell.rightTile]) {
                if(tile.hidden)continue; tiles++; staticGrid=staticGrid && !tile.caseView.webView && tile.caseView.presentation==GMCDCasePresentationStatic;
            }
        }
        [self check:@"album_grid_zero_webgl" value:staticGrid && tiles>=4];
        [self check:@"native_tabs_preserved" value:self.shell.viewControllers.count==5]; [self capture:@"Albums.png"];
        [self.shell.albumsController.table setContentOffset:CGPointMake(0,500) animated:NO];
        [self.shell.albumsController.table setContentOffset:CGPointZero animated:NO];
        GMBrowsePushSongs(self.shell.albumsController,self.shell.albums.firstObject.identifier,nil,nil);
        After(3,^{
            UINavigationController *nav=self.shell.selectedViewController;
            GMBrowseSongsController *detail=(GMBrowseSongsController *)nav.topViewController;
            self.detail=detail.collectionHeader.caseView;
            [self check:@"album_detail_uses_hero" value:!self.detail.hidden && self.detail.webView!=nil && detail.collectionHeader.cover.hidden];
            [detail.collectionHeader toggleCase];
            After(4,^{[self state:self.detail then:^(NSDictionary *state){
                [self check:@"album_detail_manual_open" value:[state[@"open"] boolValue]]; [self capture:@"Album-Detail.png"];
                [detail.collectionHeader toggleCase];
                After(3,^{[self state:self.detail then:^(NSDictionary *closed){
                    [self check:@"album_detail_manual_close" value:![closed[@"open"] boolValue]];
                    [self finish];
                }];});
            }];});
        });
    });
}
@end
@interface ProbeDelegate : NSObject <UIApplicationDelegate> @end
@implementation ProbeDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options { return YES; }
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *c=[[UISceneConfiguration alloc] initWithName:@"Probe" sessionRole:session.role]; c.delegateClass=TransitionProbe.class; return c;
}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(ProbeDelegate.class));}}
