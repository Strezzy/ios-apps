// Native interaction and navigation around the locally bundled CD renderer.
// Gesture regions are separate: the case tilts, the bottom strip browses.
#import "MusicCDInspector.h"
#import "MusicCDCase.h"

static BOOL GMCDInspectorMotionAllowed(void) {
    return !UIAccessibilityIsReduceMotionEnabled() && !UIAccessibilityPrefersCrossFadeTransitions();
}
static void GMCDInspectorSetTitle(UIButton *button, NSString *title) {
    if (button.configuration) {
        UIButtonConfiguration *configuration = [button.configuration copy];
        configuration.title = title; button.configuration = configuration;
    } else [button setTitle:title forState:0];
}
static NSString *GMCDInspectorCreditsText(void) {
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"CDCase-ACKNOWLEDGMENTS" withExtension:@"txt"];
    if (!url) return nil;
    // This is a bundled, read-only resource. Show only its actual contents.
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:NULL];
    if (!data.length || data.length > 128*1024) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@interface GMCDCreditsController : UIViewController
@property(nonatomic, copy) NSString *credits;
@property(nonatomic, strong) UIView *backdrop;
@property(nonatomic, strong) UIVisualEffectView *glass;
@property(nonatomic, strong) UITextView *textView;
@property(nonatomic, strong) UILabel *heading;
@property(nonatomic, strong) UIButton *closeButton;
- (void)applyTheme;
@end
@implementation GMCDCreditsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.backdrop = GMNewPageBackdrop(self.view.bounds,NO); [self.view addSubview:self.backdrop];
    self.heading = GMLabel(@"CD Case Credits",17,.6,GMPrimaryTextColor()); self.heading.textAlignment = 1;
    self.closeButton = GMButton(@"xmark",@"Close credits",self,@selector(closeCredits));
    [self.view addSubview:self.heading]; [self.view addSubview:self.closeButton];
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    UIVisualEffect *effect = [glassClass respondsToSelector:@selector(effectWithStyle:)] ? [glassClass effectWithStyle:0] : nil;
    self.glass = [[UIVisualEffectView alloc] initWithEffect:effect ?: [UIBlurEffect effectWithStyle:6]];
    self.glass.layer.cornerRadius = 24; self.glass.clipsToBounds = YES;
    self.glass.userInteractionEnabled = NO; self.glass.accessibilityElementsHidden = YES;
    [self.view addSubview:self.glass];
    self.textView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.textView.editable = NO; self.textView.selectable = YES; self.textView.text = self.credits;
    self.textView.font = GMAppFont(15,0); self.textView.textContainerInset = UIEdgeInsetsMake(20,18,28,18);
    self.textView.alwaysBounceVertical = YES; self.textView.contentInsetAdjustmentBehavior = 2;
    [self.view addSubview:self.textView]; [self applyTheme];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews]; self.backdrop.frame = self.view.bounds;
    CGFloat width = self.view.bounds.size.width, top = self.view.safeAreaInsets.top+12;
    self.closeButton.frame = CGRectMake(self.view.safeAreaInsets.left+16,top,44,44);
    self.heading.frame = CGRectMake(76,top+10,GMMax(0,width-152),24);
    CGRect pane = CGRectMake(self.view.safeAreaInsets.left+14,top+58,
        GMMax(0,width-self.view.safeAreaInsets.left-self.view.safeAreaInsets.right-28),
        GMMax(0,self.view.bounds.size.height-top-self.view.safeAreaInsets.bottom-72));
    self.glass.frame = pane; self.textView.frame = pane;
}
- (void)applyTheme {
    self.overrideUserInterfaceStyle = GMThemeMode == 3 ? 0 : GMThemeMode;
    self.view.backgroundColor = GMPageColor(); self.view.tintColor = GMCurrentAccent();
    self.glass.backgroundColor = [UIColor clearColor]; self.textView.backgroundColor = [UIColor clearColor];
    self.textView.textColor = GMPrimaryTextColor(); self.heading.textColor = GMPrimaryTextColor();
    GMStyleGlassButton(self.closeButton,NO); GMApplyAppFontToViewTree(self.view);
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown;
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous { [super traitCollectionDidChange:previous]; if (self.textView) [self applyTheme]; }
- (void)closeCredits { [self dismissViewControllerAnimated:YES completion:nil]; }
@end

@interface GMCDAlbumInspector ()
@property(nonatomic, weak) GMMusicShell *shell;
@property(nonatomic, copy) NSString *albumIdentifier;
@property(nonatomic, copy) NSString *anchorTrackIdentifier;
@property(nonatomic, copy) NSArray<NSString *> *albumIdentifiers;
@property(nonatomic, copy) NSString *creditsText;
@property(nonatomic, strong) UIView *backdrop;
@property(nonatomic, strong) UIView *faceArea;
@property(nonatomic, strong) GMCDCaseView *caseView;
@property(nonatomic, strong) UIView *browseArea;
@property(nonatomic, strong) UILabel *heading;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *artistLabel;
@property(nonatomic, strong) UILabel *browseHint;
@property(nonatomic, strong) UIButton *closeButton;
@property(nonatomic, strong) UIButton *creditsButton;
@property(nonatomic, strong) UIButton *previousButton;
@property(nonatomic, strong) UIButton *nextButton;
@property(nonatomic, strong) UIButton *caseButton;
@property(nonatomic, strong) UIButton *playButton;
@property(nonatomic, strong) UIPanGestureRecognizer *facePan;
@property(nonatomic) BOOL ownerVisible;
@property(nonatomic) BOOL heldInspection;
@property(nonatomic) BOOL caseOpen;
@property(nonatomic) BOOL userChoseCaseState;
@property(nonatomic) BOOL albumTransitioning;
@property(nonatomic) NSUInteger transitionGeneration;
@property(nonatomic) CGSize lastLayoutSize;
- (GMAlbum *)currentAlbum;
- (void)updateControls;
- (void)updateCaseActivity;
- (void)showAdjacentAlbum:(NSInteger)direction;
- (void)motionPreferencesChanged:(NSNotification *)notification;
@end

@implementation GMCDAlbumInspector
- (instancetype)initWithShell:(GMMusicShell *)shell albumIdentifier:(NSString *)identifier {
    self = [super init];
    if (self) {
        self.shell = shell; self.albumIdentifier = identifier;
        self.albumIdentifiers = [NSArray array];
        self.modalPresentationStyle = 0;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.backdrop = GMNewPageBackdrop(self.view.bounds,NO); [self.view addSubview:self.backdrop];
    self.heading = GMLabel(@"Inspect Album",13,.6,GMSecondaryTextColor()); self.heading.textAlignment = 1;
    self.closeButton = GMButton(@"xmark",@"Close album inspector",self,@selector(closeInspector));
    self.creditsText = GMCDInspectorCreditsText();
    self.creditsButton = GMButton(@"info.circle",@"CD case credits",self,@selector(showCredits));
    self.creditsButton.hidden = !self.creditsText.length;
    self.faceArea = [[UIView alloc] initWithFrame:CGRectZero];
    self.faceArea.isAccessibilityElement = YES;
    self.caseView = [[GMCDCaseView alloc] initWithFrame:CGRectZero presentation:GMCDCasePresentationInspector];
    self.caseView.userInteractionEnabled = NO; [self.faceArea addSubview:self.caseView];
    self.facePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleFacePan:)];
    self.facePan.maximumNumberOfTouches = 1; self.facePan.delegate = self;
    [self.faceArea addGestureRecognizer:self.facePan];
    self.titleLabel = GMLabel(@"",25,.65,GMPrimaryTextColor());
    self.titleLabel.adjustsFontSizeToFitWidth = YES; self.titleLabel.minimumScaleFactor = .65;
    self.artistLabel = GMLabel(@"",17,0,GMSecondaryTextColor());
    self.artistLabel.adjustsFontSizeToFitWidth = YES; self.artistLabel.minimumScaleFactor = .75;
    self.browseArea = [[UIView alloc] initWithFrame:CGRectZero];
    self.browseHint = GMLabel(@"Swipe here to browse",12,0,GMSecondaryTextColor());
    self.browseHint.textAlignment = 1; self.browseHint.numberOfLines = 2; [self.browseArea addSubview:self.browseHint];
    self.browseArea.accessibilityElementsHidden = YES;
    UISwipeGestureRecognizer *left = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(browseSwiped:)];
    left.direction = UISwipeGestureRecognizerDirectionLeft; [self.browseArea addGestureRecognizer:left];
    UISwipeGestureRecognizer *right = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(browseSwiped:)];
    right.direction = UISwipeGestureRecognizerDirectionRight; [self.browseArea addGestureRecognizer:right];
    self.previousButton = GMButton(@"chevron.left",@"Previous album",self,@selector(previousAlbum));
    self.nextButton = GMButton(@"chevron.right",@"Next album",self,@selector(nextAlbum));
    self.caseButton = [UIButton buttonWithType:1];
    [self.caseButton addTarget:self action:@selector(toggleCase) forControlEvents:(1UL<<6)];
    self.playButton = [UIButton buttonWithType:1]; [self.playButton setTitle:@"Play Album" forState:0];
    [self.playButton addTarget:self action:@selector(playAlbum) forControlEvents:(1UL<<6)];
    for (UIView *view in @[self.heading,self.closeButton,self.creditsButton,self.faceArea,self.titleLabel,self.artistLabel,
                           self.browseArea,self.previousButton,self.nextButton,self.caseButton,self.playButton]) [self.view addSubview:view];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(motionPreferencesChanged:) name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(motionPreferencesChanged:) name:UIAccessibilityPrefersCrossFadeTransitionsStatusDidChangeNotification object:nil];
    [self reloadLibrary]; [self applyTheme];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (GMAlbum *)currentAlbum {
    for (GMAlbum *album in self.shell.albums) if ([album.identifier isEqualToString:self.albumIdentifier]) return album;
    return nil;
}
- (void)reloadLibrary {
    NSUInteger oldIndex = [self.albumIdentifiers indexOfObject:self.albumIdentifier ?: @""];
    GMAlbum *album = [self currentAlbum];
    // Metadata edits may rename an album's grouping identifier. Its first
    // local song remains a stable anchor, so inspection follows that album.
    if (!album && self.anchorTrackIdentifier.length) {
        NSInteger anchor = GMTrackIndexForIdentifier(self.shell.player.tracks,self.anchorTrackIdentifier);
        if (anchor != NSNotFound) for (GMAlbum *candidate in self.shell.albums)
            if ([candidate.trackIndexes containsObject:@(anchor)]) { album = candidate; break; }
    }
    NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
    for (GMAlbum *candidate in self.shell.albums) [identifiers addObject:candidate.identifier];
    self.albumIdentifiers = identifiers;
    if (!album && self.shell.albums.count) {
        NSUInteger index = oldIndex == NSNotFound ? 0 : oldIndex;
        if (index >= self.shell.albums.count) index = self.shell.albums.count-1;
        album = self.shell.albums[index];
    }
    self.albumIdentifier = album.identifier;
    NSNumber *first = album.trackIndexes.firstObject;
    NSInteger firstIndex = first ? first.integerValue : -1;
    self.anchorTrackIdentifier = firstIndex >= 0 && firstIndex < (NSInteger)self.shell.player.tracks.count ?
        GMTrackIdentifier(self.shell.player.tracks[(NSUInteger)firstIndex]) : nil;
    self.titleLabel.text = album.title ?: @"No albums";
    self.artistLabel.text = album.artist ?: @"Import songs to start a collection";
    [self.caseView configureWithIdentifier:album.identifier title:album.title ?: @"No albums" artist:album.artist ?: @"Music" artwork:album.artwork];
    [self.caseView setCaseOpen:self.caseOpen animated:NO];
    self.faceArea.accessibilityLabel = album ? [NSString stringWithFormat:@"%@, %@, CD case",album.title,album.artist] : @"No album selected";
    [self updateControls]; [self refreshPlaybackIndicators]; [self updateCaseActivity];
}
- (void)updateControls {
    GMAlbum *album = [self currentAlbum];
    NSUInteger index = [self.albumIdentifiers indexOfObject:self.albumIdentifier ?: @""];
    self.heading.text = album && index != NSNotFound ? [NSString stringWithFormat:@"Album %lu of %lu",(unsigned long)(index+1),(unsigned long)self.albumIdentifiers.count] : @"Inspect Album";
    self.previousButton.enabled = !self.albumTransitioning && index != NSNotFound && index > 0;
    self.nextButton.enabled = !self.albumTransitioning && index != NSNotFound && index+1 < self.albumIdentifiers.count;
    self.caseButton.enabled = album != nil; self.playButton.enabled = album.trackIndexes.count > 0;
    NSString *caseTitle = self.caseOpen ? @"Close Case" : @"Open Case";
    GMCDInspectorSetTitle(self.caseButton,caseTitle); self.caseButton.accessibilityLabel = caseTitle;
    self.faceArea.accessibilityHint = GMCDInspectorMotionAllowed() ? @"Drag to turn the case. Use the buttons below to open it or browse albums." : @"Motion effects are disabled. Use the buttons below to open the case or browse albums.";
    self.faceArea.accessibilityCustomActions = album ? @[[[UIAccessibilityCustomAction alloc] initWithName:caseTitle target:self selector:@selector(accessibilityToggleCase:)]] : [NSArray array];
}
- (void)updateCaseActivity { [self.caseView setActive:self.ownerVisible && [self currentAlbum] != nil]; }
- (void)refreshPlaybackIndicators {
    // This is a browsable display; Play Album is a separate audio action.
    // The Now Playing presentation alone ties its disc to playback pause.
    [self.caseView setPlaying:self.ownerVisible && [self currentAlbum] != nil];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; self.ownerVisible = YES;
    [self reloadLibrary]; [self updateCaseActivity];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated]; self.ownerVisible = NO;
    self.transitionGeneration++; self.albumTransitioning = NO;
    [self finishHeldInspection]; [self.caseView setActive:NO];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.view.bounds.size; UIEdgeInsets safe = self.view.safeAreaInsets;
    BOOL wide = size.width > size.height;
    if (self.lastLayoutSize.width != size.width || self.lastLayoutSize.height != size.height) {
        [self.caseView resetInspectionTiltAnimated:NO];
        if (!self.userChoseCaseState) { self.caseOpen = wide; [self.caseView setCaseOpen:wide animated:NO]; [self updateControls]; }
        self.lastLayoutSize = size;
    }
    self.backdrop.frame = self.view.bounds;
    CGFloat left = safe.left+16, right = size.width-safe.right-16, top = safe.top+10, bottom = size.height-safe.bottom-16;
    self.closeButton.frame = CGRectMake(left,top,44,44); self.creditsButton.frame = CGRectMake(right-44,top,44,44);
    self.heading.frame = CGRectMake(left+56,top+12,GMMax(0,right-left-112),22);
    CGFloat contentTop = top+58;
    if (wide) {
        CGFloat panelWidth = GMMin(278,GMMax(218,(right-left)*.34));
        CGFloat panelX = right-panelWidth;
        self.faceArea.frame = CGRectMake(left-6,contentTop,GMMax(100,panelX-left-10),GMMax(100,bottom-contentTop));
        self.titleLabel.textAlignment = 0; self.artistLabel.textAlignment = 0;
        self.titleLabel.frame = CGRectMake(panelX,contentTop+4,panelWidth,32);
        self.artistLabel.frame = CGRectMake(panelX,contentTop+40,panelWidth,24);
        CGFloat playY = bottom-44, caseY = playY-54, browseY = caseY-54;
        self.previousButton.frame = CGRectMake(panelX,browseY,44,44); self.nextButton.frame = CGRectMake(right-44,browseY,44,44);
        self.browseArea.frame = CGRectMake(panelX+50,browseY,GMMax(0,panelWidth-100),44);
        self.caseButton.frame = CGRectMake(panelX,caseY,panelWidth,44); self.playButton.frame = CGRectMake(panelX,playY,panelWidth,44);
    } else {
        CGFloat controlsY = bottom-100, labelsY = controlsY-64;
        CGFloat artHeight = GMMax(100,labelsY-contentTop-10);
        self.faceArea.frame = CGRectMake(left-6,contentTop,right-left+12,artHeight);
        self.titleLabel.textAlignment = 1; self.artistLabel.textAlignment = 1;
        self.titleLabel.frame = CGRectMake(left,labelsY,right-left,32); self.artistLabel.frame = CGRectMake(left,labelsY+34,right-left,24);
        self.previousButton.frame = CGRectMake(left,controlsY,44,44); self.nextButton.frame = CGRectMake(right-44,controlsY,44,44);
        self.browseArea.frame = CGRectMake(left+52,controlsY,GMMax(0,right-left-104),44);
        CGFloat half = (right-left-12)/2;
        self.caseButton.frame = CGRectMake(left,controlsY+56,half,44); self.playButton.frame = CGRectMake(left+half+12,controlsY+56,half,44);
    }
    self.caseView.frame = self.faceArea.bounds; self.browseHint.frame = self.browseArea.bounds;
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown;
}
- (void)applyTheme {
    self.overrideUserInterfaceStyle = GMThemeMode == 3 ? 0 : GMThemeMode;
    self.view.backgroundColor = GMPageColor(); self.view.tintColor = GMCurrentAccent();
    self.faceArea.backgroundColor = [UIColor clearColor]; self.browseArea.backgroundColor = [UIColor clearColor];
    self.heading.textColor = GMSecondaryTextColor(); self.titleLabel.textColor = GMPrimaryTextColor();
    self.artistLabel.textColor = GMSecondaryTextColor(); self.browseHint.textColor = GMSecondaryTextColor();
    for (UIButton *button in @[self.closeButton,self.creditsButton,self.previousButton,self.nextButton,self.caseButton]) GMStyleGlassButton(button,NO);
    GMStyleGlassButton(self.playButton,YES); [self.caseView applyTheme]; GMApplyAppFontToViewTree(self.view);
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous { [super traitCollectionDidChange:previous]; if (self.caseView) [self applyTheme]; }
- (void)motionPreferencesChanged:(NSNotification *)notification {
    if (![NSThread isMainThread]) { __weak GMCDAlbumInspector *weakSelf = self; dispatch_async(dispatch_get_main_queue(),^{ [weakSelf motionPreferencesChanged:notification]; }); return; }
    [self.caseView resetInspectionTiltAnimated:NO]; [self updateControls];
}
- (void)beginHeldInspection { self.heldInspection = YES; }
- (void)updateHeldInspectionTranslation:(CGPoint)translation {
    if (!self.heldInspection || !GMCDInspectorMotionAllowed()) return;
    CGFloat width = GMMax(160,self.faceArea.bounds.size.width), height = GMMax(160,self.faceArea.bounds.size.height);
    CGFloat x = GMMax(-1,GMMin(1,translation.x/(width*.42)));
    CGFloat y = GMMax(-1,GMMin(1,translation.y/(height*.42)));
    [self.caseView setInspectionTiltX:x y:y];
}
- (void)finishHeldInspection { self.heldInspection = NO; [self.caseView resetInspectionTiltAnimated:YES]; }
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    return gesture != self.facePan || (!self.heldInspection && !self.albumTransitioning && [self currentAlbum] && GMCDInspectorMotionAllowed());
}
- (void)handleFacePan:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [gesture translationInView:self.faceArea];
        CGFloat x = GMMax(-1,GMMin(1,translation.x/GMMax(80,self.faceArea.bounds.size.width*.42)));
        CGFloat y = GMMax(-1,GMMin(1,translation.y/GMMax(80,self.faceArea.bounds.size.height*.42)));
        [self.caseView setInspectionTiltX:x y:y];
    } else [self.caseView resetInspectionTiltAnimated:YES];
}
- (void)previousAlbum { [self showAdjacentAlbum:-1]; }
- (void)nextAlbum { [self showAdjacentAlbum:1]; }
- (void)browseSwiped:(UISwipeGestureRecognizer *)gesture { [self showAdjacentAlbum:gesture.direction == UISwipeGestureRecognizerDirectionLeft ? 1 : -1]; }
- (void)showAdjacentAlbum:(NSInteger)direction {
    if (self.heldInspection || self.albumTransitioning || !self.ownerVisible) return;
    NSUInteger index = [self.albumIdentifiers indexOfObject:self.albumIdentifier ?: @""];
    if (index == NSNotFound || (direction < 0 && !index) || (direction > 0 && index+1 >= self.albumIdentifiers.count)) return;
    NSString *nextIdentifier = self.albumIdentifiers[direction < 0 ? index-1 : index+1];
    [self.caseView resetInspectionTiltAnimated:NO];
    if (!GMCDInspectorMotionAllowed()) { self.albumIdentifier = nextIdentifier; self.anchorTrackIdentifier = nil; [self reloadLibrary]; return; }
    self.albumTransitioning = YES; [self updateControls]; NSUInteger generation = ++self.transitionGeneration;
    __weak GMCDAlbumInspector *weakSelf = self;
    UIViewAnimationOptions options = direction > 0 ? UIViewAnimationOptionTransitionFlipFromRight : UIViewAnimationOptionTransitionFlipFromLeft;
    [UIView transitionWithView:self.faceArea duration:.32 options:options animations:^{
        GMCDAlbumInspector *controller = weakSelf;
        if (!controller || generation != controller.transitionGeneration) return;
        controller.albumIdentifier = nextIdentifier; controller.anchorTrackIdentifier = nil; [controller reloadLibrary];
    } completion:^(BOOL finished) {
        (void)finished; GMCDAlbumInspector *controller = weakSelf;
        if (controller && generation == controller.transitionGeneration) { controller.albumTransitioning = NO; [controller updateControls]; }
    }];
}
- (void)toggleCase {
    if (![self currentAlbum]) return;
    self.userChoseCaseState = YES; self.caseOpen = !self.caseOpen;
    [self.caseView setCaseOpen:self.caseOpen animated:YES]; [self updateControls];
}
- (BOOL)accessibilityToggleCase:(UIAccessibilityCustomAction *)action { (void)action; if (![self currentAlbum]) return NO; [self toggleCase]; return YES; }
- (void)playAlbum {
    GMAlbum *album = [self currentAlbum];
    if (album.trackIndexes.count && [self.shell.player playAllTrackIndexes:album.trackIndexes]) [self refreshPlaybackIndicators];
}
- (void)showCredits {
    if (!self.creditsText.length || self.presentedViewController || !self.view.window) return;
    GMCDCreditsController *controller = [GMCDCreditsController new]; controller.credits = self.creditsText;
    controller.modalPresentationStyle = 0; controller.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:controller animated:YES completion:nil];
}
- (void)closeInspector { [self finishHeldInspection]; [self.caseView setActive:NO]; [self dismissViewControllerAnimated:YES completion:nil]; }
@end
