// Music — a native, local-file music player.
// Uses public Apple APIs and a bundled, offline WebGL CD-case renderer.
// No network client, analytics, or account.
#if __has_include(<UIKit/UIKit.h>)
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <QuartzCore/QuartzCore.h>
#import <PhotosUI/PhotosUI.h>
#import <ImageIO/ImageIO.h>
#import <CoreText/CoreText.h>
#import <WebKit/WebKit.h>
#import <CoreMotion/CoreMotion.h>
#include <stdlib.h>
#else
#import "MiniSDK.h"
#endif
#import "MusicPersonalization.h"
#import "MusicScrollSettings.h"
#import "MusicScrollAnimations.h"
#import "MusicCDCase.h"

static UIColor *GMColor(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}
static UIColor *GMInk(void) { return GMColor(.94,.96,1,1); }
static CGFloat GMMin(CGFloat a, CGFloat b) { return a < b ? a : b; }
static CGFloat GMMax(CGFloat a, CGFloat b) { return a > b ? a : b; }
static NSArray<NSString *> *GMAudioExtensions(void) {
    return @[@"mp3",@"m4a",@"aac",@"wav",@"aif",@"aiff",@"caf",@"flac",@"mp4"];
}
static NSString *GMTime(NSTimeInterval seconds) {
    if (!(seconds >= 0) || seconds > 1000000) seconds = 0;
    NSInteger n = (NSInteger)seconds;
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(n/60), (long)(n%60)];
}
static UILabel *GMLabel(NSString *text, CGFloat size, CGFloat weight, UIColor *color) {
    UILabel *v = [[UILabel alloc] initWithFrame:CGRectZero];
    v.text = text; v.font = GMAppFont(size,weight);
    v.textColor = color; v.numberOfLines = 1;
    return v;
}
static UIButton *GMButton(NSString *symbol, NSString *label, id target, SEL action) {
    UIButton *b = [UIButton buttonWithType:1];
    [b setImage:[UIImage systemImageNamed:symbol] forState:0];
    b.tintColor = GMInk();
    b.accessibilityLabel = label;
    [b addTarget:target action:action forControlEvents:(1UL << 6)];
    return b;
}

@interface GMTrack : NSObject
@property(strong) NSURL *url;
@property(copy) NSString *title;
@property(copy) NSString *artist;
@property(copy) NSString *album;
@property(copy) NSString *albumArtist;
@property NSInteger trackNumber;
@property NSInteger discNumber;
@property(strong) UIImage *artwork;
@property BOOL demo;
@property BOOL metadataLoaded;
@end
@implementation GMTrack @end

#import "MusicLibraryStore.h"
#import "MusicEditsStore.h"
#import "LibraryUI.h"
#import "MusicAlbumImport.h"
#import "MusicArtworkBackdrop.h"
#import "MusicCDInspector.h"
#import "MusicAppearance.m"
#import "MusicArtwork.m"
#import "MusicLibraryStore.m"
#import "MusicEditsStore.m"
#import "PlaybackIndicator.h"
#import "PlaybackIndicator.m"
#import "MusicArtworkBackdrop.m"
#import "MusicLyrics.h"
#import "MusicLyrics.m"
#import "MusicPersonalization.m"
#import "MusicScrollSettings.m"
#import "MusicScrollAnimations.m"
#import "MusicCDCase.m"

static UIImage *GMPlayerSymbol(NSString *name, CGFloat size) {
    return [UIImage systemImageNamed:name withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size weight:6]];
}

static UIVisualEffectView *GMPlayerRouteSurface(void) {
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    UIVisualEffect *effect = nil;
    if ([glassClass respondsToSelector:@selector(effectWithStyle:)]) {
        UIGlassEffect *glass = [glassClass effectWithStyle:0]; glass.interactive = YES; effect = glass;
    } else effect = [UIBlurEffect effectWithStyle:6];
    UIVisualEffectView *surface = [[UIVisualEffectView alloc] initWithEffect:effect];
    Class corners = NSClassFromString(@"UICornerConfiguration");
    if ([corners respondsToSelector:@selector(capsuleConfiguration)] && [surface respondsToSelector:@selector(setCornerConfiguration:)])
        surface.cornerConfiguration = [corners capsuleConfiguration];
    else { surface.layer.cornerRadius = 24; surface.clipsToBounds = YES; }
    return surface;
}

@interface PlayerController : UIViewController <UIDocumentPickerDelegate,AVAudioPlayerDelegate,UIScrollViewDelegate>
@property(weak) GMMusicShell *shell;
@property(strong) NSMutableArray<GMTrack *> *tracks;
@property(strong) NSURL *musicDirectory;
@property(strong) AVAudioPlayer *player;
@property NSInteger selectedIndex;
@property(copy) NSArray<NSString *> *queueTrackIdentifiers;
@property(copy) NSArray<NSString *> *orderedQueueTrackIdentifiers;
@property NSInteger queuePosition;
@property NSInteger playbackMode; // 0 normal, 1 shuffle, 2 repeat current song.
@property NSUInteger metadataGeneration;
@property BOOL metadataLoading;
@property BOOL seeking;
@property BOOL importing;
@property BOOL resumeAfterInterruption;
@property BOOL playbackRequested;
@property BOOL hasRenderedPlaybackState;
@property BOOL renderedPlaying;
@property(strong) NSTimer *timer;
@property(strong) UILabel *heading;
@property(strong) UILabel *trackTitle;
@property(strong) UILabel *trackArtist;
@property(strong) UILabel *elapsed;
@property(strong) UILabel *remaining;
@property(strong) UIView *artView;
@property(strong) GMCDCaseView *cdCaseView;
@property BOOL artworkOwnerVisible;
@property BOOL playerCaseOpen;
@property BOOL caseTransitionInProgress;
@property(strong) UIScrollView *nowPlayingScroll;
@property(strong) MPVolumeView *volumeView;
@property(strong) AVRoutePickerView *routePicker;
@property(strong) UIVisualEffectView *routeSurface;
@property(strong) UIButton *lyricsButton;
@property(strong) UIButton *modeButton;
@property(strong) GMLyricsStore *lyricsStore;
@property(strong) GMLyricsView *lyricsView;
@property BOOL showingLyrics;
@property(strong) UIViewPropertyAnimator *artworkAnimator;
@property(strong) UIButton *closeButton;
@property(strong) UIButton *playButton;
@property(strong) UIButton *previousButton;
@property(strong) UIButton *nextButton;
@property(strong) UISlider *seekSlider;
@property(strong) GMArtworkBackdrop *artworkBackdrop;
- (void)readMetadataForTrack:(GMTrack *)track;
- (BOOL)selectTrackAtIndex:(NSInteger)index autoplay:(BOOL)autoplay;
- (BOOL)playTrackIndexes:(NSArray<NSNumber *> *)indexes startingAtPosition:(NSInteger)position;
- (BOOL)playAllTrackIndexes:(NSArray<NSNumber *> *)indexes;
- (BOOL)shuffleTrackIndexes:(NSArray<NSNumber *> *)indexes;
- (void)applyTheme;
- (void)togglePlay;
- (void)nextTrack;
- (void)previousTrack;
- (void)importMusic;
- (void)removeTrackAtIndex:(NSInteger)index;
- (void)refreshEditedLibrary;
- (void)updateCurrentSongPresentation;
- (void)updatePlaybackModeControl;
- (void)updateArtworkPlaybackStateAnimated:(BOOL)animated;
- (void)updateCDCaseActivity;
- (void)toggleCDCase;
- (void)showMessage:(NSString *)title message:(NSString *)message;
@end

@implementation PlayerController
- (void)viewDidLoad {
    [super viewDidLoad];
    // The shell retains this controller while it is offscreen. Audio and the
    // document library therefore survive tab changes and modal dismissal.
    self.overrideUserInterfaceStyle = 2;
    self.view.backgroundColor = GMColor(.09,.055,.075,1);
    self.selectedIndex = -1;
    self.tracks = [NSMutableArray array];
    self.artworkBackdrop = [[GMArtworkBackdrop alloc] initWithFrame:self.view.bounds];
    self.artworkBackdrop.autoresizingMask = (1UL<<1)|(1UL<<4);
    [self.view addSubview:self.artworkBackdrop];

    self.closeButton = GMButton(@"chevron.down",@"Close Now Playing",self,@selector(closeNowPlaying));
    [self.closeButton setImage:GMPlayerSymbol(@"chevron.down",19) forState:0];
    [self.view addSubview:self.closeButton];
    self.heading = GMLabel(@"Now Playing",12,.6,GMColor(1,1,1,.65));
    self.heading.textAlignment = 1;
    [self.view addSubview:self.heading];
    self.nowPlayingScroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.nowPlayingScroll.showsVerticalScrollIndicator = NO;
    self.nowPlayingScroll.delegate = self;
    [self.view addSubview:self.nowPlayingScroll];

    self.artView = [[UIView alloc] initWithFrame:CGRectZero];
    self.artView.backgroundColor = [UIColor clearColor];
    self.artView.isAccessibilityElement = YES;
    self.artView.accessibilityHint = @"Open the CD case with the accessibility action.";
    self.cdCaseView = [[GMCDCaseView alloc] initWithFrame:CGRectZero presentation:GMCDCasePresentationPlayer];
    self.cdCaseView.userInteractionEnabled = NO;
    [self.artView addSubview:self.cdCaseView];
    UITapGestureRecognizer *caseTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleCDCase)];
    [self.artView addGestureRecognizer:caseTap];
    [self.nowPlayingScroll addSubview:self.artView];
    NSURL *documents = [[[NSFileManager defaultManager] URLsForDirectory:9 inDomains:1] firstObject];
    self.lyricsStore = [[GMLyricsStore alloc] initWithFileURL:[documents URLByAppendingPathComponent:@"MusicLyrics.plist"]];
    self.lyricsView = [[GMLyricsView alloc] initWithFrame:CGRectZero];
    self.lyricsView.store = self.lyricsStore; self.lyricsView.presenter = self;
    self.lyricsView.hidden = YES;
    [self.nowPlayingScroll addSubview:self.lyricsView];
    self.trackTitle = GMLabel(@"Glass Study",25,.65,GMInk());
    self.trackTitle.adjustsFontSizeToFitWidth = YES; self.trackTitle.minimumScaleFactor = .65;
    self.trackArtist = GMLabel(@"Original demo",20,0,GMColor(1,1,1,.60));
    [self.nowPlayingScroll addSubview:self.trackTitle];
    [self.nowPlayingScroll addSubview:self.trackArtist];

    self.seekSlider = [[UISlider alloc] initWithFrame:CGRectZero];
    self.seekSlider.minimumValue = 0; self.seekSlider.maximumValue = 1;
    self.seekSlider.minimumTrackTintColor = GMColor(1,1,1,.75);
    self.seekSlider.maximumTrackTintColor = GMColor(1,1,1,.17);
    self.seekSlider.thumbTintColor = GMInk(); self.seekSlider.accessibilityLabel = @"Playback position";
    [self.seekSlider addTarget:self action:@selector(beginSeek) forControlEvents:1];
    [self.seekSlider addTarget:self action:@selector(seekChanged) forControlEvents:(1UL<<12)];
    [self.seekSlider addTarget:self action:@selector(endSeek) forControlEvents:((1UL<<6)|(1UL<<7)|(1UL<<8))];
    [self.nowPlayingScroll addSubview:self.seekSlider];
    self.elapsed = GMLabel(@"0:00",12,0,GMColor(1,1,1,.5));
    self.remaining = GMLabel(@"−0:00",12,0,GMColor(1,1,1,.5));
    self.remaining.textAlignment = 2;
    self.elapsed.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:0];
    self.remaining.font = self.elapsed.font;
    [self.nowPlayingScroll addSubview:self.elapsed];
    [self.nowPlayingScroll addSubview:self.remaining];

    self.previousButton = GMButton(@"backward.end.fill",@"Previous track",self,@selector(previousTrack));
    self.playButton = GMButton(@"play.fill",@"Play",self,@selector(togglePlay));
    self.nextButton = GMButton(@"forward.end.fill",@"Next track",self,@selector(nextTrack));
    [self.previousButton setImage:GMPlayerSymbol(@"backward.end.fill",28) forState:0];
    [self.playButton setImage:GMPlayerSymbol(@"play.fill",38) forState:0];
    [self.nextButton setImage:GMPlayerSymbol(@"forward.end.fill",28) forState:0];
    [self.nowPlayingScroll addSubview:self.previousButton];
    [self.nowPlayingScroll addSubview:self.playButton];
    [self.nowPlayingScroll addSubview:self.nextButton];
    self.volumeView = [[MPVolumeView alloc] initWithFrame:CGRectZero];
    self.volumeView.tintColor = GMColor(1,1,1,.80);
    self.volumeView.showsVolumeSlider = YES; self.volumeView.showsRouteButton = NO;
    [self.nowPlayingScroll addSubview:self.volumeView];
    self.lyricsButton = GMButton(@"quote.bubble",@"Show lyrics",self,@selector(toggleLyrics));
    self.modeButton = GMButton(@"shuffle",@"Playback mode",self,@selector(cyclePlaybackMode));
    self.routeSurface = GMPlayerRouteSurface();
    self.routePicker = [[AVRoutePickerView alloc] initWithFrame:CGRectZero];
    self.routePicker.prioritizesVideoDevices = NO;
    self.routePicker.accessibilityLabel = @"AirPlay";
    [self.routeSurface.contentView addSubview:self.routePicker];
    [self.nowPlayingScroll addSubview:self.lyricsButton];
    [self.nowPlayingScroll addSubview:self.routeSurface];
    [self.nowPlayingScroll addSubview:self.modeButton];

    [self applyTheme];
    [self prepareLibrary];
    [self loadLibrary];
    [self configureAudio];
    [self configureRemoteCommands];
    if (self.tracks.count) [self selectTrackAtIndex:0 autoplay:NO];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:.35 target:self selector:@selector(tick) userInfo:nil repeats:YES];
}
- (void)applyTheme {
    self.overrideUserInterfaceStyle = GMThemeMode == 3 ? 0 : GMThemeMode;
    self.view.backgroundColor = GMPageColor(); self.view.tintColor = GMCurrentAccent();
    [self.artworkBackdrop applyTheme];
    self.trackTitle.textColor = GMPrimaryTextColor(); self.trackArtist.textColor = GMSecondaryTextColor();
    self.heading.textColor = GMSecondaryTextColor();
    self.elapsed.textColor = GMSecondaryTextColor(); self.remaining.textColor = GMSecondaryTextColor();
    self.artView.backgroundColor = [UIColor clearColor]; [self.cdCaseView applyTheme];
    self.seekSlider.minimumTrackTintColor = GMCurrentAccent();
    self.seekSlider.maximumTrackTintColor = GMSeparatorColor(); self.seekSlider.thumbTintColor = GMCurrentAccent();
    self.volumeView.tintColor = GMCurrentAccent();
    self.routePicker.tintColor = GMCurrentAccent(); self.routePicker.activeTintColor = GMCurrentAccent();
    GMStyleGlassButton(self.closeButton,NO); GMStyleGlassButton(self.previousButton,NO);
    GMStyleGlassButton(self.nextButton,NO); GMStyleGlassButton(self.playButton,YES);
    GMStyleGlassButton(self.lyricsButton,self.showingLyrics);
    [self updatePlaybackModeControl]; [self.lyricsView applyTheme];
    GMApplyAppFontToViewTree(self.view);
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection]; [self applyTheme];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    CGFloat safeTop = self.view.safeAreaInsets.top, safeBottom = self.view.safeAreaInsets.bottom;
    CGFloat inset = GMMax(32,(w-420)/2), contentW = GMMax(120,w-2*inset);
    self.artworkBackdrop.frame = self.view.bounds;
    self.closeButton.frame = CGRectMake(16,safeTop+14,44,44);
    self.heading.frame = CGRectMake(64,safeTop+25,w-128,22);
    CGFloat availableHeight = GMMax(80,h-safeTop-safeBottom-72);
    self.nowPlayingScroll.frame = CGRectMake(0,safeTop+72,w,availableHeight);
    CGFloat artSize = GMMin(contentW,GMMax(170,availableHeight-388));
    // Keep layout independent of the scale used by the play/pause spring.
    self.artView.bounds = CGRectMake(0,0,artSize,artSize);
    self.artView.center = CGPointMake(w/2,12+artSize/2);
    if (self.cdCaseView.superview == self.artView) self.cdCaseView.frame = self.artView.bounds;
    self.lyricsView.frame = CGRectMake(inset,12,contentW,artSize);
    CGFloat titleY = artSize+38;
    self.trackTitle.frame = CGRectMake(inset,titleY,contentW,32);
    self.trackArtist.frame = CGRectMake(inset,titleY+35,contentW,26);
    CGFloat seekY = titleY+76;
    self.seekSlider.frame = CGRectMake(inset,seekY,contentW,30);
    self.elapsed.frame = CGRectMake(inset+2,seekY+32,86,18);
    self.remaining.frame = CGRectMake(w-inset-88,seekY+32,86,18);
    CGFloat transportY = seekY+65;
    self.playButton.frame = CGRectMake(w/2-38,transportY,76,76);
    self.previousButton.frame = CGRectMake(inset,transportY+4,70,68);
    self.nextButton.frame = CGRectMake(w-inset-70,transportY+4,70,68);
    CGFloat volumeY = transportY+93;
    self.volumeView.frame = CGRectMake(inset,volumeY,contentW,36);
    CGFloat utilityY = volumeY+48;
    self.lyricsButton.frame = CGRectMake(inset+12,utilityY,48,48);
    self.routeSurface.frame = CGRectMake(w/2-24,utilityY,48,48);
    self.routePicker.frame = CGRectMake(0,0,48,48);
    self.modeButton.frame = CGRectMake(w-inset-60,utilityY,48,48);
    self.nowPlayingScroll.contentSize = CGSizeMake(w,GMMax(availableHeight,utilityY+64));
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateArtworkPlaybackStateAnimated:NO];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.artworkOwnerVisible = YES;
    if (!self.caseTransitionInProgress && self.cdCaseView.superview != self.artView)
        [self.cdCaseView moveToHost:self.artView frame:self.artView.bounds prewarming:NO];
    [self updateCDCaseActivity];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.artworkOwnerVisible = NO;
    if (!self.caseTransitionInProgress) [self.cdCaseView setActive:NO];
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.nowPlayingScroll) [self updateCDCaseActivity];
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait;
}
- (void)viewSafeAreaInsetsDidChange { [super viewSafeAreaInsetsDidChange]; [self.view setNeedsLayout]; }
- (void)closeNowPlaying { self.caseTransitionInProgress = YES; [self dismissViewControllerAnimated:YES completion:nil]; }
- (UIViewController *)visiblePresenter {
    UIViewController *presenter = self.shell ?: self;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    return presenter;
}
- (void)prepareLibrary {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *documents = [[fm URLsForDirectory:9 inDomains:1] firstObject];
    self.musicDirectory = [documents URLByAppendingPathComponent:@"Music"];
    NSError *error = nil;
    if (![fm createDirectoryAtURL:self.musicDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
        [self showMessage:@"Storage unavailable" message:error.localizedDescription];
    }
}
- (void)loadLibrary {
    NSURL *oldURL = nil;
    if (self.selectedIndex >= 0 && self.selectedIndex < (NSInteger)self.tracks.count) oldURL = self.tracks[self.selectedIndex].url;
    NSMutableDictionary *knownTracks = [NSMutableDictionary dictionary];
    for (GMTrack *track in self.tracks) if (track.url.path) knownTracks[track.url.path] = track;
    [self.tracks removeAllObjects];
    NSArray *extensions = GMAudioExtensions();
    NSArray *files = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.musicDirectory.path error:NULL] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *filename in files) {
        if ([filename hasPrefix:@"."] || ![extensions containsObject:filename.pathExtension.lowercaseString]) continue;
        NSURL *url = [self.musicDirectory URLByAppendingPathComponent:filename];
        GMTrack *track = knownTracks[url.path];
        if (!track) {
            track = [GMTrack new]; track.url = url;
            track.title = filename.stringByDeletingPathExtension; track.artist = @"Unknown Artist";
            track.album = @"Unknown Album";
        }
        [self.shell.editsStore applyToTrack:track];
        [self.tracks addObject:track];
    }
    NSURL *demoURL = [[NSBundle mainBundle] URLForResource:@"Glass-Study" withExtension:@"wav"];
    if (demoURL) {
        GMTrack *demo = knownTracks[demoURL.path];
        if (!demo) {
            demo = [GMTrack new]; demo.url = demoURL; demo.title = @"Glass Study";
            demo.artist = @"Music"; demo.album = @"Included Demo"; demo.albumArtist = @"Music";
            demo.trackNumber = 1; demo.discNumber = 1; demo.demo = YES; demo.metadataLoaded = YES;
        }
        [self.shell.editsStore applyToTrack:demo];
        if (![self.shell.editsStore isTrackHidden:demo]) [self.tracks addObject:demo];
    }
    self.selectedIndex = -1;
    for (NSUInteger i=0; i<self.tracks.count; i++) {
        if (oldURL && [self.tracks[i].url.path isEqualToString:oldURL.path]) { self.selectedIndex = (NSInteger)i; break; }
    }
    [self.shell reloadLibrary];
    [self preloadMetadata];
}
- (void)preloadMetadata {
    NSUInteger generation = ++self.metadataGeneration;
    NSMutableArray<GMTrack *> *pending = [NSMutableArray array];
    for (GMTrack *track in self.tracks) {
        if (track.metadataLoaded) continue;
        GMTrack *copy = [GMTrack new];
        copy.url = track.url; copy.title = track.title; copy.artist = track.artist;
        copy.album = track.album; copy.albumArtist = track.albumArtist;
        [pending addObject:copy];
    }
    self.metadataLoading = pending.count > 0;
    if (!pending.count) return;
    // Read independent metadata objects off the main thread. Only the main
    // callback publishes to the library, keeping launch and controls responsive.
    dispatch_async(dispatch_get_global_queue(0,0),^{
        @autoreleasepool {
            for (GMTrack *copy in pending) [self readMetadataForTrack:copy];
            dispatch_async(dispatch_get_main_queue(),^{
                if (generation != self.metadataGeneration) return;
                for (GMTrack *copy in pending) {
                    NSInteger index = GMTrackIndexForIdentifier(self.tracks,GMTrackIdentifier(copy));
                    if (index == NSNotFound) continue;
                    GMTrack *track = self.tracks[(NSUInteger)index];
                    if (track.metadataLoaded) continue;
                    track.title = copy.title; track.artist = copy.artist;
                    track.album = copy.album; track.albumArtist = copy.albumArtist;
                    track.trackNumber = copy.trackNumber; track.discNumber = copy.discNumber;
                    track.artwork = copy.artwork; track.metadataLoaded = YES;
                    [self.shell.editsStore applyToTrack:track];
                }
                self.metadataLoading = NO;
                [self refreshEditedLibrary];
            });
        }
    });
}
- (void)configureAudio {
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:NULL];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(audioInterrupted:) name:AVAudioSessionInterruptionNotification object:nil];
    [center addObserver:self selector:@selector(audioRouteChanged:) name:AVAudioSessionRouteChangeNotification object:nil];
}
- (void)configureRemoteCommands {
    MPRemoteCommandCenter *c = [MPRemoteCommandCenter sharedCommandCenter];
    [c.playCommand addTarget:self action:@selector(remotePlay:)];
    [c.pauseCommand addTarget:self action:@selector(remotePause:)];
    [c.togglePlayPauseCommand addTarget:self action:@selector(remoteToggle:)];
    [c.nextTrackCommand addTarget:self action:@selector(remoteNext:)];
    [c.previousTrackCommand addTarget:self action:@selector(remotePrevious:)];
    [c.changePlaybackPositionCommand addTarget:self action:@selector(remoteSeek:)];
    c.playCommand.enabled = YES; c.pauseCommand.enabled = YES;
    c.togglePlayPauseCommand.enabled = YES; c.nextTrackCommand.enabled = YES;
    c.previousTrackCommand.enabled = YES; c.changePlaybackPositionCommand.enabled = YES;
}
- (void)readMetadataForTrack:(GMTrack *)track {
    if (track.metadataLoaded) return;
    track.metadataLoaded = YES;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:track.url options:nil];
    for (AVMetadataItem *item in asset.commonMetadata) {
        NSString *key = item.commonKey;
        if ([key isEqualToString:@"title"] && item.stringValue.length) track.title = item.stringValue;
        if ([key isEqualToString:@"artist"] && item.stringValue.length) track.artist = item.stringValue;
        if ([key isEqualToString:@"albumName"] && item.stringValue.length) track.album = item.stringValue;
        if ([key isEqualToString:@"artwork"] && item.dataValue) track.artwork = GMArtworkFromData(item.dataValue);
    }
    for (AVMetadataItem *item in asset.metadata) {
        NSString *identifier = item.identifier;
        if ([identifier isEqualToString:AVMetadataIdentifieriTunesMetadataAlbumArtist] || [identifier isEqualToString:AVMetadataIdentifierID3MetadataBand]) {
            if (item.stringValue.length) track.albumArtist = item.stringValue;
        }
        BOOL trackItem = [identifier isEqualToString:AVMetadataIdentifierID3MetadataTrackNumber] || [identifier isEqualToString:AVMetadataIdentifieriTunesMetadataTrackNumber];
        BOOL discItem = [identifier isEqualToString:AVMetadataIdentifierID3MetadataPartOfASet] || [identifier isEqualToString:AVMetadataIdentifieriTunesMetadataDiscNumber];
        if (!trackItem && !discItem) continue;
        NSInteger number = item.numberValue.integerValue;
        if (number <= 0) number = item.stringValue.integerValue;
        BOOL iTunesPair = [identifier isEqualToString:AVMetadataIdentifieriTunesMetadataTrackNumber] || [identifier isEqualToString:AVMetadataIdentifieriTunesMetadataDiscNumber];
        NSData *data = iTunesPair ? item.dataValue : nil;
        if (number <= 0 && data.length >= 4 && data.length <= 32) {
            // trkn/disk tuples begin with a reserved 16-bit field, then the
            // big-endian index. Copy only a validated four-byte prefix.
            unsigned char bytes[4] = {0,0,0,0}; [data getBytes:bytes length:4];
            number = ((NSInteger)bytes[2]<<8) | bytes[3];
        }
        if (number > 0 && number <= 100000) {
            if (trackItem) track.trackNumber = number;
            if (discItem) track.discNumber = number;
        }
    }
    if (!track.album.length) track.album = @"Unknown Album";
    if (!track.albumArtist.length) track.albumArtist = track.artist;
}
- (BOOL)installQueue:(NSArray<NSNumber *> *)indexes startingAtPosition:(NSInteger)position autoplay:(BOOL)autoplay {
    if (position < 0 || position >= (NSInteger)indexes.count) return NO;
    NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
    for (NSNumber *number in indexes) {
        if (![number isKindOfClass:[NSNumber class]]) return NO;
        NSInteger index = number.integerValue;
        if (index < 0 || index >= (NSInteger)self.tracks.count) return NO;
        NSString *identifier = GMTrackIdentifier(self.tracks[(NSUInteger)index]);
        if (!identifier.length) return NO;
        [identifiers addObject:identifier];
    }
    NSArray *previousQueue = self.queueTrackIdentifiers;
    NSArray *previousOrderedQueue = self.orderedQueueTrackIdentifiers;
    NSInteger previousPosition = self.queuePosition;
    self.orderedQueueTrackIdentifiers = identifiers;
    self.queueTrackIdentifiers = identifiers; self.queuePosition = position;
    if (![self loadTrackAtIndex:indexes[(NSUInteger)position].integerValue autoplay:autoplay]) {
        self.queueTrackIdentifiers = previousQueue; self.orderedQueueTrackIdentifiers = previousOrderedQueue;
        self.queuePosition = previousPosition;
        return NO;
    }
    if (self.playbackMode == 1) [self rebuildQueueForPlaybackMode];
    return YES;
}
- (BOOL)selectTrackAtIndex:(NSInteger)index autoplay:(BOOL)autoplay {
    NSMutableArray<NSNumber *> *indexes = [NSMutableArray array];
    for (NSUInteger i=0;i<self.tracks.count;i++) [indexes addObject:@(i)];
    return [self installQueue:indexes startingAtPosition:index autoplay:autoplay];
}
- (BOOL)playTrackIndexes:(NSArray<NSNumber *> *)indexes startingAtPosition:(NSInteger)position {
    return [self installQueue:indexes startingAtPosition:position autoplay:YES];
}
- (BOOL)playAllTrackIndexes:(NSArray<NSNumber *> *)indexes {
    if (!indexes.count) return NO;
    NSInteger previousMode = self.playbackMode;
    self.playbackMode = 0;
    BOOL result = [self installQueue:indexes startingAtPosition:0 autoplay:YES];
    if (!result) self.playbackMode = previousMode;
    self.player.numberOfLoops = self.playbackMode == 2 ? -1 : 0;
    [self updatePlaybackModeControl];
    return result;
}
- (BOOL)shuffleTrackIndexes:(NSArray<NSNumber *> *)indexes {
    if (!indexes.count) return NO;
    NSInteger previousMode = self.playbackMode;
    self.playbackMode = 1;
    NSUInteger first = arc4random_uniform((unsigned int)indexes.count);
    BOOL result = [self installQueue:indexes startingAtPosition:(NSInteger)first autoplay:YES];
    if (!result) self.playbackMode = previousMode;
    self.player.numberOfLoops = self.playbackMode == 2 ? -1 : 0;
    [self updatePlaybackModeControl];
    return result;
}
- (void)rebuildQueueForPlaybackMode {
    NSString *current = self.selectedIndex >= 0 && self.selectedIndex < (NSInteger)self.tracks.count ?
        GMTrackIdentifier(self.tracks[(NSUInteger)self.selectedIndex]) : nil;
    NSMutableArray<NSString *> *ordered = [NSMutableArray array];
    NSArray<NSString *> *source = self.orderedQueueTrackIdentifiers ?: self.queueTrackIdentifiers;
    for (NSString *identifier in source)
        if (GMTrackIndexForIdentifier(self.tracks,identifier) != NSNotFound && ![ordered containsObject:identifier])
            [ordered addObject:identifier];
    if (!ordered.count) for (GMTrack *track in self.tracks) [ordered addObject:GMTrackIdentifier(track)];
    if (current.length && ![ordered containsObject:current]) [ordered addObject:current];
    self.orderedQueueTrackIdentifiers = ordered;
    if (self.playbackMode == 1) {
        NSMutableArray<NSString *> *upcoming = [NSMutableArray array];
        for (NSString *identifier in ordered) if (![identifier isEqualToString:current]) [upcoming addObject:identifier];
        for (NSUInteger remaining=upcoming.count;remaining>1;remaining--)
            [upcoming exchangeObjectAtIndex:remaining-1 withObjectAtIndex:arc4random_uniform((unsigned int)remaining)];
        NSMutableArray *shuffled = [NSMutableArray array];
        if (current.length) [shuffled addObject:current];
        for (NSString *identifier in upcoming) [shuffled addObject:identifier];
        self.queueTrackIdentifiers = shuffled;
    } else self.queueTrackIdentifiers = ordered;
    self.queuePosition = [self positionInQueue:[self liveQueueIndexes]];
}
- (void)cyclePlaybackMode {
    self.playbackMode = (self.playbackMode+1)%3;
    self.player.numberOfLoops = self.playbackMode == 2 ? -1 : 0;
    [self rebuildQueueForPlaybackMode];
    [self updatePlaybackModeControl];
}
- (void)updatePlaybackModeControl {
    if (!self.modeButton) return;
    GMStyleGlassButton(self.modeButton,self.playbackMode != 0);
    GMSetButtonImage(self.modeButton,GMPlayerSymbol(self.playbackMode == 2 ? @"repeat.1" : @"shuffle",21));
    if (self.playbackMode == 0) {
        UIButtonConfiguration *configuration = [self.modeButton.configuration copy];
        configuration.baseForegroundColor = GMSecondaryTextColor();
        self.modeButton.configuration = configuration;
    }
    self.modeButton.accessibilityLabel = @"Playback mode";
    self.modeButton.accessibilityValue = self.playbackMode == 1 ? @"Shuffle" : self.playbackMode == 2 ? @"Repeat this song" : @"Off";
    self.modeButton.accessibilityHint = self.playbackMode == 0 ? @"Tap to shuffle" : self.playbackMode == 1 ? @"Tap to repeat this song" : @"Tap to turn off shuffle and repeat";
    self.modeButton.enabled = self.tracks.count > 0;
}
- (NSArray<NSNumber *> *)liveQueueIndexes {
    NSMutableArray<NSNumber *> *indexes = [NSMutableArray array];
    for (NSString *identifier in self.queueTrackIdentifiers) {
        NSInteger index = GMTrackIndexForIdentifier(self.tracks,identifier);
        if (index != NSNotFound) [indexes addObject:@(index)];
    }
    if (!indexes.count) for (NSUInteger i=0;i<self.tracks.count;i++) [indexes addObject:@(i)];
    return indexes;
}
- (NSInteger)positionInQueue:(NSArray<NSNumber *> *)indexes {
    for (NSUInteger i=0;i<indexes.count;i++) if (indexes[i].integerValue == self.selectedIndex) return (NSInteger)i;
    return -1;
}
- (BOOL)loadTrackAtIndex:(NSInteger)index autoplay:(BOOL)autoplay {
    if (index < 0 || index >= (NSInteger)self.tracks.count) return NO;
    GMTrack *track = self.tracks[index];
    NSError *error = nil;
    AVAudioPlayer *newPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:track.url error:&error];
    if (!newPlayer) {
        [self showMessage:@"Couldn't play this file" message:error.localizedDescription ?: @"Try an unprotected MP3, M4A, WAV, or AIFF audio file."];
        return NO;
    }
    [self.player stop]; self.playbackRequested = NO; self.resumeAfterInterruption = NO;
    self.player = newPlayer; self.player.delegate = self;
    self.player.numberOfLoops = self.playbackMode == 2 ? -1 : 0;
    self.selectedIndex = index; self.seeking = NO;
    [self readMetadataForTrack:track];
    [self.shell.editsStore applyToTrack:track];
    [self updateCurrentSongPresentation];
    self.seekSlider.maximumValue = (float)GMMax(self.player.duration,.01); self.seekSlider.value = 0;
    [self.player prepareToPlay];
    if (autoplay) [self play]; else [self refreshPlayback];
    [self.shell reloadLibrary];
    return YES;
}
- (void)play {
    if (!self.player && self.tracks.count) { [self selectTrackAtIndex:0 autoplay:YES]; return; }
    if (!self.player) return;
    NSError *error = nil;
    if (![[AVAudioSession sharedInstance] setActive:YES error:&error]) {
        self.playbackRequested = NO;
        [self refreshPlayback];
        [self showMessage:@"Audio unavailable" message:error.localizedDescription]; return;
    }
    if (self.player.currentTime >= self.player.duration-.05) self.player.currentTime = 0;
    self.playbackRequested = [self.player play];
    if (!self.playbackRequested) { [self showMessage:@"Couldn't start playback" message:@"Try importing another local audio file."]; }
    [self refreshPlayback];
}
- (void)pause {
    self.playbackRequested = NO; self.resumeAfterInterruption = NO;
    [self.player pause]; [self refreshPlayback];
}
- (void)togglePlay { if (self.player.isPlaying) [self pause]; else [self play]; }
- (void)previousTrack {
    NSArray<NSNumber *> *indexes = [self liveQueueIndexes];
    if (!indexes.count) return;
    if (self.player.currentTime > 3) { self.player.currentTime = 0; [self refreshPlayback]; return; }
    NSInteger position = [self positionInQueue:indexes];
    NSInteger previous = position > 0 ? position-1 : (NSInteger)indexes.count-1;
    [self loadTrackAtIndex:indexes[(NSUInteger)previous].integerValue autoplay:YES];
}
- (void)nextTrack {
    NSArray<NSNumber *> *indexes = [self liveQueueIndexes];
    if (!indexes.count) return;
    NSInteger position = ([self positionInQueue:indexes]+1)%(NSInteger)indexes.count;
    [self loadTrackAtIndex:indexes[(NSUInteger)position].integerValue autoplay:YES];
}
- (void)syncPlaybackControls {
    // A replacement AVAudioPlayer can already be playing while the button
    // still shows Pause. Always resync the case, even when its glyph is unchanged.
    BOOL playing = self.player.isPlaying;
    [self.cdCaseView setPlaying:playing];
    if (self.hasRenderedPlaybackState && self.renderedPlaying == playing) return;
    self.hasRenderedPlaybackState = YES; self.renderedPlaying = playing;
    self.playerCaseOpen = playing;
    [self.cdCaseView setCaseOpen:playing animated:YES];
    GMSetButtonImage(self.playButton,GMPlayerSymbol(playing?@"pause.fill":@"play.fill",38));
    self.playButton.accessibilityLabel = playing?@"Pause":@"Play";
    [self updateArtworkPlaybackStateAnimated:YES];
    [self updateNowPlaying];
    [self.shell refreshPlaybackState];
    UIViewController *presented = [self visiblePresenter];
    if ([presented isKindOfClass:[GMCDAlbumInspector class]]) [(GMCDAlbumInspector *)presented refreshPlaybackIndicators];
}
- (void)refreshPlayback {
    [self syncPlaybackControls];
    self.seekSlider.enabled = self.player != nil;
    [self tick]; [self updateNowPlaying]; [self.shell refreshPlaybackState];
}
- (void)tick {
    // Also reconcile after delayed audio-session changes or remote commands.
    // Reconfigure glyphs only when the actual playback state changes.
    [self syncPlaybackControls];
    if (self.showingLyrics) [self.lyricsView updatePlaybackTime:self.player.currentTime];
    if (!self.seeking) {
        self.seekSlider.value = (float)self.player.currentTime;
        self.elapsed.text = GMTime(self.player.currentTime);
        self.remaining.text = [@"−" stringByAppendingString:GMTime(self.player.duration-self.player.currentTime)];
        self.seekSlider.accessibilityValue = [NSString stringWithFormat:@"%@ of %@",GMTime(self.player.currentTime),GMTime(self.player.duration)];
    }
}
- (void)beginSeek { self.seeking = YES; }
- (void)seekChanged {
    // Value changed also fires for VoiceOver adjustment without a touch-down.
    if (!self.seeking) self.player.currentTime = self.seekSlider.value;
    self.elapsed.text = GMTime(self.seekSlider.value);
    self.remaining.text = [@"−" stringByAppendingString:GMTime(self.player.duration-self.seekSlider.value)];
    if (!self.seeking) [self updateNowPlaying];
}
- (void)endSeek {
    self.player.currentTime = GMMin(self.seekSlider.value,self.player.duration);
    self.seeking = NO; [self tick]; [self updateNowPlaying];
}
- (void)updateNowPlaying {
    if (self.selectedIndex<0 || self.selectedIndex>=(NSInteger)self.tracks.count || !self.player) return;
    GMTrack *t = self.tracks[self.selectedIndex];
    NSMutableDictionary *info = [@{
        MPMediaItemPropertyTitle:t.title ?: @"Local audio",
        MPMediaItemPropertyArtist:t.artist ?: @"Music",
        MPMediaItemPropertyPlaybackDuration:@(self.player.duration),
        MPNowPlayingInfoPropertyElapsedPlaybackTime:@(self.player.currentTime),
        MPNowPlayingInfoPropertyPlaybackRate:@(self.player.isPlaying?1.0:0.0),
        MPNowPlayingInfoPropertyDefaultPlaybackRate:@1.0
    } mutableCopy];
    UIImage *image = t.artwork;
    if (image) info[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithBoundsSize:CGSizeMake(600,600) requestHandler:^UIImage *(CGSize size) { return image; }];
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
}
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    if (player != self.player) return;
    if (flag && self.playbackMode == 2) { self.player.currentTime = 0; [self play]; return; }
    NSArray<NSNumber *> *indexes = [self liveQueueIndexes];
    NSInteger next = [self positionInQueue:indexes]+1;
    if (next >= 0 && next < (NSInteger)indexes.count) {
        if (![self loadTrackAtIndex:indexes[(NSUInteger)next].integerValue autoplay:YES]) {
            self.playbackRequested = NO; self.resumeAfterInterruption = NO; [self refreshPlayback];
        }
    } else { self.playbackRequested = NO; self.resumeAfterInterruption = NO; self.player.currentTime = 0; [self refreshPlayback]; }
}
- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error {
    if (player != self.player) return;
    [self pause]; [self showMessage:@"Audio file error" message:error.localizedDescription];
}
- (void)audioInterrupted:(NSNotification *)note {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(),^{ [self audioInterrupted:note]; });
        return;
    }
    NSUInteger type = [note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    if (type == 1) {
        // iOS can stop the player before it delivers the interruption notification.
        self.resumeAfterInterruption = self.playbackRequested;
        [self.player pause]; [self refreshPlayback];
    } else {
        NSUInteger options = [note.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
        BOOL shouldResume = self.resumeAfterInterruption && (options&1);
        self.resumeAfterInterruption = NO;
        if (shouldResume) [self play];
        else { self.playbackRequested = NO; [self refreshPlayback]; }
    }
}
- (void)audioRouteChanged:(NSNotification *)note {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(),^{ [self audioRouteChanged:note]; });
        return;
    }
    if ([note.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue] == 2) [self pause];
}
- (NSInteger)remotePlay:(MPRemoteCommandEvent *)event { dispatch_async(dispatch_get_main_queue(),^{[self play];}); return 0; }
- (NSInteger)remotePause:(MPRemoteCommandEvent *)event { dispatch_async(dispatch_get_main_queue(),^{[self pause];}); return 0; }
- (NSInteger)remoteToggle:(MPRemoteCommandEvent *)event { dispatch_async(dispatch_get_main_queue(),^{[self togglePlay];}); return 0; }
- (NSInteger)remoteNext:(MPRemoteCommandEvent *)event { dispatch_async(dispatch_get_main_queue(),^{[self nextTrack];}); return 0; }
- (NSInteger)remotePrevious:(MPRemoteCommandEvent *)event { dispatch_async(dispatch_get_main_queue(),^{[self previousTrack];}); return 0; }
- (NSInteger)remoteSeek:(MPChangePlaybackPositionCommandEvent *)event {
    NSTimeInterval position = event.positionTime;
    dispatch_async(dispatch_get_main_queue(),^{self.player.currentTime=GMMax(0,GMMin(position,self.player.duration));[self refreshPlayback];});
    return 0;
}
- (void)importMusic {
    UIViewController *presenter = [self visiblePresenter];
    if (self.importing || [presenter isKindOfClass:[UIDocumentPickerViewController class]] || [presenter isKindOfClass:[UIAlertController class]]) return;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeAudio] asCopy:YES];
    picker.delegate = self; picker.allowsMultipleSelection = YES;
    [presenter presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (!urls.count) return;
    self.importing = YES;
    [self.shell reloadLibrary];
    NSURL *destinationDirectory = self.musicDirectory;
    NSArray *extensions = GMAudioExtensions();
    dispatch_async(dispatch_get_global_queue(0,0),^{
        @autoreleasepool {
            NSFileManager *fm = [NSFileManager defaultManager];
            NSMutableArray *failures = [NSMutableArray array];
            NSURL *firstImportedURL = nil;
            for (NSURL *url in urls) {
                NSString *name = url.lastPathComponent;
                if (![extensions containsObject:name.pathExtension.lowercaseString]) {
                    [failures addObject:[NSString stringWithFormat:@"%@: This audio format isn't supported. Try MP3, M4A, AAC, WAV, AIFF, CAF, or FLAC.",name]];
                    continue;
                }
                BOOL access = [url startAccessingSecurityScopedResource];
                NSString *base = name.stringByDeletingPathExtension;
                NSString *ext = name.pathExtension;
                NSURL *dest = [destinationDirectory URLByAppendingPathComponent:name];
                NSUInteger suffix = 2;
                while ([fm fileExistsAtPath:dest.path]) {
                    NSString *alternate = ext.length ? [NSString stringWithFormat:@"%@ (%lu).%@",base,(unsigned long)suffix,ext] : [NSString stringWithFormat:@"%@ (%lu)",base,(unsigned long)suffix];
                    dest = [destinationDirectory URLByAppendingPathComponent:alternate]; suffix++;
                }
                NSError *error = nil;
                if (![fm copyItemAtURL:url toURL:dest error:&error]) [failures addObject:[NSString stringWithFormat:@"%@: %@",name,error.localizedDescription ?: @"Couldn't copy this file."]];
                else if (!firstImportedURL) firstImportedURL = dest;
                if (access) [url stopAccessingSecurityScopedResource];
            }
            dispatch_async(dispatch_get_main_queue(),^{
                BOOL wasDemo = self.selectedIndex>=0 && self.selectedIndex<(NSInteger)self.tracks.count && self.tracks[self.selectedIndex].demo;
                BOOL wasPlaying = self.player.isPlaying;
                self.importing = NO;
                [self loadLibrary];
                if (firstImportedURL && (wasDemo || self.selectedIndex<0) && !wasPlaying) {
                    for (NSUInteger i=0;i<self.tracks.count;i++) if ([self.tracks[i].url.path isEqualToString:firstImportedURL.path]) { [self selectTrackAtIndex:(NSInteger)i autoplay:NO]; break; }
                }
                if (failures.count) [self showMessage:@"Some files weren't imported" message:failures.firstObject];
            });
        }
    });
}
- (void)refreshEditedLibrary {
    if (self.selectedIndex >= 0 && self.selectedIndex < (NSInteger)self.tracks.count) {
        GMTrack *track = self.tracks[(NSUInteger)self.selectedIndex];
        [self.shell.editsStore applyToTrack:track];
    }
    [self updateCurrentSongPresentation];
    [self updateNowPlaying]; [self.shell reloadLibrary];
}
- (void)updateCurrentSongPresentation {
    GMTrack *track = self.selectedIndex >= 0 && self.selectedIndex < (NSInteger)self.tracks.count ?
        self.tracks[(NSUInteger)self.selectedIndex] : nil;
    self.trackTitle.text = track.title ?: @"Choose a song";
    self.trackArtist.text = track.artist ?: @"Music";
    [self.cdCaseView configureWithIdentifier:GMTrackIdentifier(track) title:track.title ?: @"Choose a song"
                                    artist:track.artist ?: @"Music" artwork:track.artwork];
    self.artView.accessibilityLabel = [NSString stringWithFormat:@"%@, CD case",track.title ?: @"Choose a song"];
    self.artView.accessibilityCustomActions = @[[[UIAccessibilityCustomAction alloc] initWithName:self.playerCaseOpen ? @"Close CD Case" : @"Open CD Case" target:self selector:@selector(accessibilityToggleCDCase:)]];
    [self updateCDCaseActivity];
    // The shared palette also animates visible Dynamic pages while this full
    // player is offscreen. Each backdrop decides its own window visibility.
    [self.artworkBackdrop setArtwork:track.artwork animated:YES];
    [self.lyricsView configureForSongIdentifier:GMTrackIdentifier(track) title:track.title ?: @"Choose a song"];
    self.lyricsButton.enabled = track != nil;
    [self updatePlaybackModeControl];
}
- (void)toggleLyrics {
    self.showingLyrics = !self.showingLyrics;
    // The lyrics pane keeps its real glass controls at full opacity. Only
    // artwork visibility changes; no effect-view ancestor is cross-faded.
    self.artView.hidden = self.showingLyrics;
    self.lyricsView.hidden = !self.showingLyrics;
    self.lyricsButton.accessibilityLabel = self.showingLyrics ? @"Show album artwork" : @"Show lyrics";
    GMStyleGlassButton(self.lyricsButton,self.showingLyrics);
    [self updateArtworkPlaybackStateAnimated:NO];
    if (self.showingLyrics) [self.lyricsView updatePlaybackTime:self.player.currentTime];
}
- (void)updateCDCaseActivity {
    BOOL hasTrack = self.selectedIndex >= 0 && self.selectedIndex < (NSInteger)self.tracks.count;
    [self.cdCaseView setPlaying:self.player.isPlaying];
    if (!self.caseTransitionInProgress) [self.cdCaseView setCaseOpen:self.playerCaseOpen animated:YES];
    if (!self.caseTransitionInProgress && !self.cdCaseView.prewarming)
        [self.cdCaseView setActive:self.artworkOwnerVisible && !self.showingLyrics && hasTrack];
}
- (void)toggleCDCase {
    if (self.showingLyrics || self.selectedIndex < 0 || self.selectedIndex >= (NSInteger)self.tracks.count) return;
    self.playerCaseOpen = !self.playerCaseOpen;
    [self.cdCaseView setCaseOpen:self.playerCaseOpen animated:YES];
    self.artView.accessibilityCustomActions = @[[[UIAccessibilityCustomAction alloc] initWithName:self.playerCaseOpen ? @"Close CD Case" : @"Open CD Case" target:self selector:@selector(accessibilityToggleCDCase:)]];
}
- (BOOL)accessibilityToggleCDCase:(UIAccessibilityCustomAction *)action {
    (void)action;
    if (self.selectedIndex < 0 || self.selectedIndex >= (NSInteger)self.tracks.count) return NO;
    [self toggleCDCase]; return YES;
}
- (void)updateArtworkPlaybackStateAnimated:(BOOL)animated {
    [self updateCDCaseActivity];
    if (self.caseTransitionInProgress) return;
    UIViewPropertyAnimator *previous = self.artworkAnimator;
    self.artworkAnimator = nil;
    if (previous.state == UIViewAnimatingStateActive) {
        [previous stopAnimation:NO]; [previous finishAnimationAtPosition:UIViewAnimatingPositionCurrent];
    }
    CGFloat scale = self.player.isPlaying ? 1 : .90;
    BOOL motion = animated && self.view.window && !self.showingLyrics &&
        !UIAccessibilityIsReduceMotionEnabled() && !UIAccessibilityPrefersCrossFadeTransitions();
    if (!motion) { self.artView.transform = CGAffineTransformMakeScale(scale,scale); return; }
    __weak PlayerController *weakSelf = self;
    UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc] initWithDuration:.50 dampingRatio:.76 animations:^{
        weakSelf.artView.transform = CGAffineTransformMakeScale(scale,scale);
    }];
    __weak UIViewPropertyAnimator *weakAnimator = animator;
    [animator addCompletion:^(UIViewAnimatingPosition position) {
        PlayerController *controller = weakSelf;
        if (controller.artworkAnimator == weakAnimator && position == UIViewAnimatingPositionEnd) controller.artworkAnimator = nil;
    }];
    self.artworkAnimator = animator; [animator startAnimation];
}
- (void)removeTrackAtIndex:(NSInteger)index {
    if (self.importing || index<0 || index>=(NSInteger)self.tracks.count) return;
    GMTrack *t = self.tracks[(NSUInteger)index];
    NSError *error = nil;
    BOOL removed = t.demo ? [self.shell.editsStore hideTrack:t error:&error] : [[NSFileManager defaultManager] removeItemAtURL:t.url error:&error];
    if (!removed) {
        [self showMessage:@"Couldn't remove this track" message:error.localizedDescription];
        return;
    }
    BOOL deletedCurrent = index == self.selectedIndex;
    if (deletedCurrent) {
        [self.player stop]; self.player = nil;
        self.playbackRequested = NO; self.resumeAfterInterruption = NO;
    }
    [self loadLibrary];
    if (deletedCurrent && self.tracks.count) [self selectTrackAtIndex:0 autoplay:NO];
    else {
        if (!self.tracks.count) {
            [self updateCurrentSongPresentation];
            [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
        }
        [self refreshPlayback];
    }
}
- (void)showMessage:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(),^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message ?: @"Please try again." preferredStyle:1];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:0 handler:nil]];
        UIViewController *presenter = [self visiblePresenter];
        if ([presenter isKindOfClass:[UIDocumentPickerViewController class]]) {
            [presenter dismissViewControllerAnimated:YES completion:^{
                [[self visiblePresenter] presentViewController:alert animated:YES completion:nil];
            }];
        } else if (![presenter isKindOfClass:[UIAlertController class]]) {
            [presenter presentViewController:alert animated:YES completion:nil];
        }
    });
}
@end

// One translation unit keeps all screens on the same playback engine.
#import "BrowseUI.h"
#import "BrowseUI.m"
#import "MusicCDInspector.m"
#import "MusicAlbumImport.m"
#import "MusicPlayerTransition.m"
#import "LibraryUI.m"
#import "MusicEditingUI.m"

// The full-screen CD inspector opts into landscape independently. Ordinary
// iPhone navigation keeps the portrait behavior of the approved builds.
@implementation GMMusicShell (GMCDOrientationPolicy)
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait;
}
@end

@interface SceneDelegate : NSObject <UIWindowSceneDelegate>
@property(strong) UIWindow *window;
@end
@implementation SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [GMMusicShell new];
    [self.window makeKeyAndVisible];
}
@end
@interface AppDelegate : NSObject <UIApplicationDelegate> @end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    GMLoadPersonalization();
    return YES;
}
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:session.role];
    configuration.sceneClass = [UIWindowScene class];
    configuration.delegateClass = [SceneDelegate class];
    return configuration;
}
@end
int main(int argc,char **argv) {
    @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass([AppDelegate class])); }
}
