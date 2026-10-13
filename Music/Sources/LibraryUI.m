// Five native tabs, a shared mini-player, and local appearance preferences.
@class GMSettingsController, GMCompactPlayerView;
@interface GMMusicShell ()
@property(strong) GMSongsController *songsController;
@property(strong) GMAlbumsController *albumsController;
@property(strong) GMPlaylistsController *playlistsController;
@property(strong) GMSearchController *searchController;
@property(strong) GMSettingsController *settingsController;
@property(strong) GMAlbumImporter *albumImporter;
@property(strong) GMCompactPlayerView *compactPlayer;
@property(strong) id nativeAccessory;
@property(strong) UIVisualEffectView *fallbackAccessory;
@property NSInteger lastSelectedIndex;
@property(strong) UIView *caseWarmHost;
@property(strong) GMPlayerCaseTransition *caseTransition;
- (void)savePreferences;
@end

static void GMConfigureArtwork(UIImageView *view, GMTrack *track) {
    view.image = track.artwork ?: [UIImage systemImageNamed:@"music.note"];
    view.contentMode = track.artwork ? 2 : 1;
    view.tintColor = GMCurrentAccent(); view.backgroundColor = GMCardColor();
}

@interface GMAppearanceCell : UITableViewCell
@property(strong) UISegmentedControl *segments;
@end
@implementation GMAppearanceCell
- (id)initWithStyle:(NSInteger)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (!self) return nil;
    self.selectionStyle = 0;
    self.segments = [[UISegmentedControl alloc] initWithItems:@[@"System",@"Dark",@"Light",@"Dynamic"]];
    self.segments.accessibilityLabel = @"Appearance";
    [self.contentView addSubview:self.segments];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.segments.frame = CGRectMake(12,(self.contentView.bounds.size.height-36)/2,GMMax(0,self.contentView.bounds.size.width-24),36);
}
@end

@interface GMSettingsController : GMBrowseTableController <UIColorPickerViewControllerDelegate>
- (void)reloadSettings;
@end
@implementation GMSettingsController
- (void)viewDidLoad {
    self.tableStyle = 2;
    [super viewDidLoad];
    self.title = @"Settings"; self.navigationItem.rightBarButtonItem = nil;
}
- (void)reloadSettings { [self.table reloadData]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 4; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 5;
    if (section == 1) return 2;
    if (section == 2) return 4;
    return 1;
}
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 0 && path.row == 0) return 72;
    if (path.section == 0 && path.row == 4) return 166;
    return 58;
}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Appearance" : section == 1 ? @"Accent Color" : section == 2 ? @"On This Device" : @"About";
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Dynamic blends the playing artwork’s colors throughout Music. Text contrast follows your iPhone’s light or dark appearance.";
    if (section == 1) return @"Your color is used throughout Music, including buttons, highlights, and playback controls.";
    if (section == 2) return @"Imported audio and playlists are saved on this device. The included demo is separate from the song count.";
    return @"Your music. Offline. No account or subscription needed.";
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 0 && path.row == 0) {
        GMAppearanceCell *cell = [table dequeueReusableCellWithIdentifier:@"Appearance"];
        if (!cell) {
            cell = [[GMAppearanceCell alloc] initWithStyle:0 reuseIdentifier:@"Appearance"];
            [cell.segments addTarget:self action:@selector(appearanceChanged:) forControlEvents:(1UL<<12)];
        }
        // Saved System=0, Light=1, Dark=2, Dynamic=3. Keep earlier preferences.
        NSInteger mode = self.shell.appearanceMode;
        cell.segments.selectedSegmentIndex = mode == 2 ? 1 : mode == 1 ? 2 : mode;
        cell.backgroundColor = GMCardColor(); cell.tintColor = GMCurrentAccent();
        return cell;
    }
    if (path.section == 0 && path.row == 4) {
        GMScrollStyleCell *cell = [table dequeueReusableCellWithIdentifier:@"ScrollStyle"];
        if (!cell) cell = [[GMScrollStyleCell alloc] initWithStyle:0 reuseIdentifier:@"ScrollStyle"];
        cell.presenter = self; [cell refreshStyle]; [cell applyTheme];
        return cell;
    }
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"Setting"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:1 reuseIdentifier:@"Setting"];
    cell.backgroundColor = GMCardColor(); cell.tintColor = GMCurrentAccent();
    cell.textLabel.textColor = GMPrimaryTextColor();
    cell.detailTextLabel.textColor = GMSecondaryTextColor();
    cell.detailTextLabel.text = nil; cell.selectionStyle = 0; cell.accessoryType = 0;
    cell.accessoryView = nil; cell.imageView.image = nil;
    if (path.section == 0 && path.row == 1) {
        cell.textLabel.text=@"Font"; cell.selectionStyle=3; cell.accessoryType=1;
        cell.detailTextLabel.text=GMSharedPersonalization().selectedFontName ?: @"System";
        if (!cell.detailTextLabel.text.length) cell.detailTextLabel.text=@"System";
        cell.imageView.image=[UIImage systemImageNamed:@"textformat"];
    } else if (path.section == 0 && path.row == 2) {
        cell.textLabel.text=@"App Icon"; cell.selectionStyle=3; cell.accessoryType=1;
        cell.detailTextLabel.text=@"6 styles + custom";
        cell.imageView.image=[UIImage systemImageNamed:@"app.badge"];
    } else if (path.section == 0 && path.row == 3) {
        cell.textLabel.text = @"Scrolling Animations";
        UISwitch *toggle = [UISwitch new];
        [toggle setOn:[GMScrollSettings sharedSettings].enabled animated:NO];
        toggle.onTintColor = GMCurrentAccent();
        toggle.accessibilityLabel = @"Scrolling Animations";
        toggle.accessibilityHint = @"Animate music rows while scrolling.";
        [toggle addTarget:self action:@selector(scrollingAnimationsChanged:) forControlEvents:(1UL<<12)];
        cell.accessoryView = toggle;
    } else if (path.section == 1 && path.row == 0) {
        cell.textLabel.text = @"Choose Color"; cell.selectionStyle = 3;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"#%02X%02X%02X",(unsigned)(GMAccentComponents[0]*255+.5),(unsigned)(GMAccentComponents[1]*255+.5),(unsigned)(GMAccentComponents[2]*255+.5)];
        UIView *swatch = [[UIView alloc] initWithFrame:CGRectMake(0,0,30,30)];
        swatch.backgroundColor = GMCurrentAccent(); swatch.layer.cornerRadius = 15;
        swatch.layer.borderWidth = 1; swatch.layer.borderColor = GMSeparatorColor().CGColor;
        cell.accessoryView = swatch;
        cell.accessibilityHint = @"Open the color picker";
    } else if (path.section == 1) {
        cell.textLabel.text = @"Reset Accent Color"; cell.textLabel.textColor = GMCurrentAccent(); cell.selectionStyle = 3;
    } else if (path.section == 2 && path.row == 0) {
        cell.textLabel.text = self.shell.player.importing ? @"Importing…" : @"Import Songs";
        cell.textLabel.textColor = GMCurrentAccent(); cell.selectionStyle = 3;
        cell.imageView.image = [UIImage systemImageNamed:@"plus"]; cell.imageView.tintColor = GMCurrentAccent();
    } else if (path.section == 2 && path.row == 1) {
        cell.textLabel.text = self.shell.player.importing ? @"Importing…" : @"Import Album";
        cell.textLabel.textColor=GMCurrentAccent(); cell.selectionStyle=3;
        cell.imageView.image=[UIImage systemImageNamed:@"square.stack"];
    } else if (path.section == 2 && path.row == 2) {
        NSUInteger count = 0;
        for (GMTrack *track in self.shell.player.tracks) if (!track.demo) count++;
        cell.textLabel.text = @"Imported Songs";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu",(unsigned long)count];
    } else if (path.section == 2) {
        cell.textLabel.text = @"Playlists";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu",(unsigned long)self.shell.playlistStore.playlists.count];
    } else {
        cell.textLabel.text = @"Music"; cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ (%@)",[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]];
    }
    GMApplyAppFontToViewTree(cell.contentView);
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == 0 && path.row == 1) {
        GMFontSettingsController *fonts=[GMFontSettingsController new];
        [self.navigationController pushViewController:fonts animated:YES];
    } else if (path.section == 0 && path.row == 2) {
        if (self.presentedViewController) return;
        UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:[GMIconPickerController new]];
        navigation.modalPresentationStyle=1;
        navigation.sheetPresentationController.detents=@[[UISheetPresentationControllerDetent largeDetent]];
        navigation.sheetPresentationController.preferredCornerRadius=30;
        [self presentViewController:navigation animated:YES completion:nil];
    } else if (path.section == 1 && path.row == 0) [self chooseColor];
    else if (path.section == 1 && path.row == 1) [self.shell setAccentColor:GMColor(.98,.18,.32,1) persist:YES];
    else if (path.section == 2 && path.row == 0) [self.shell importSongs];
    else if (path.section == 2 && path.row == 1) [self.shell importAlbum];
}
- (void)appearanceChanged:(UISegmentedControl *)control {
    NSInteger index = control.selectedSegmentIndex;
    NSInteger mode = index == 1 ? 2 : index == 2 ? 1 : index;
    [self.shell setAppearanceMode:mode persist:YES];
}
- (void)scrollingAnimationsChanged:(UISwitch *)control {
    GMScrollSettings *settings = [GMScrollSettings sharedSettings];
    NSError *error = nil;
    if (![settings setAnimationsEnabled:control.on error:&error]) {
        [control setOn:settings.enabled animated:YES];
        [self.shell.player showMessage:@"Couldn't Save Scrolling" message:error.localizedDescription ?: @"Your previous scrolling setting is unchanged."];
    }
}
- (void)chooseColor {
    if (self.presentedViewController) return;
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.delegate = self; picker.selectedColor = GMCurrentAccent(); picker.supportsAlpha = NO;
    picker.title = @"Accent Color";
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)colorPickerViewController:(UIColorPickerViewController *)picker didSelectColor:(UIColor *)color continuously:(BOOL)continuously {
    [self.shell setAccentColor:color persist:!continuously];
}
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)picker {
    [self.shell setAccentColor:picker.selectedColor persist:YES];
}
@end

// Keep a comfortable 44-point touch area around the smaller glass controls.
@class UIEvent;
@interface GMCompactTransportButton : UIButton @end
@implementation GMCompactTransportButton
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || !self.userInteractionEnabled || !self.enabled) return NO;
    CGRect bounds = self.bounds;
    CGFloat extraX = GMMax(0,(44-bounds.size.width)/2);
    CGFloat extraY = GMMax(0,(44-bounds.size.height)/2);
    return point.x >= bounds.origin.x-extraX && point.x <= bounds.origin.x+bounds.size.width+extraX &&
           point.y >= bounds.origin.y-extraY && point.y <= bounds.origin.y+bounds.size.height+extraY;
}
@end

@interface GMCompactPlayerView : UIView
@property(weak) GMMusicShell *shell;
@property(strong) UIButton *bodyButton;
@property(strong) UIImageView *cover;
@property(strong) UILabel *titleLabel;
@property(strong) UILabel *artistLabel;
@property(strong) UIButton *playButton;
@property(strong) UIButton *nextButton;
@property BOOL compactPresentation;
- (void)refresh;
- (void)applyTheme;
- (void)updateNativeAccessoryEnvironment;
@end
@implementation GMCompactPlayerView
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.bodyButton = [UIButton buttonWithType:0];
    self.bodyButton.accessibilityLabel = @"Open Now Playing";
    [self.bodyButton addTarget:self action:@selector(openPlayer) forControlEvents:(1UL<<6)];
    [self addSubview:self.bodyButton];
    self.cover = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.cover.layer.cornerRadius = 6; self.cover.clipsToBounds = YES;
    self.titleLabel = GMLabel(@"Choose a song",14,.4,GMPrimaryTextColor());
    self.artistLabel = GMLabel(@"Music",11,0,GMSecondaryTextColor());
    self.cover.userInteractionEnabled = NO;
    self.titleLabel.userInteractionEnabled = NO; self.artistLabel.userInteractionEnabled = NO;
    [self addSubview:self.cover]; [self addSubview:self.titleLabel]; [self addSubview:self.artistLabel];
    self.playButton = [[GMCompactTransportButton alloc] initWithFrame:CGRectZero];
    self.nextButton = [[GMCompactTransportButton alloc] initWithFrame:CGRectZero];
    self.playButton.accessibilityLabel = @"Play"; self.nextButton.accessibilityLabel = @"Next song";
    [self.playButton addTarget:self action:@selector(togglePlay) forControlEvents:(1UL<<6)];
    [self.nextButton addTarget:self action:@selector(nextTrack) forControlEvents:(1UL<<6)];
    [self addSubview:self.playButton]; [self addSubview:self.nextButton];
    Class accessoryTrait = NSClassFromString(@"UITraitTabAccessoryEnvironment");
    if (accessoryTrait && [self respondsToSelector:@selector(registerForTraitChanges:withTarget:action:)])
        [self registerForTraitChanges:@[accessoryTrait] withTarget:self action:@selector(updateNativeAccessoryEnvironment)];
    [self updateNativeAccessoryEnvironment];
    [self applyTheme];
    return self;
}
- (CGSize)intrinsicContentSize { return CGSizeMake(-1,52); }
- (void)updateNativeAccessoryEnvironment {
    UITraitCollection *traits = self.traitCollection;
    BOOL inlineAccessory = [traits respondsToSelector:@selector(tabAccessoryEnvironment)] &&
        traits.tabAccessoryEnvironment == UITabAccessoryEnvironmentInline;
    if (self.compactPresentation == inlineAccessory) return;
    self.compactPresentation = inlineAccessory;
    [self setNeedsLayout];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateNativeAccessoryEnvironment];
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateNativeAccessoryEnvironment];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    // UIKit owns the enclosing glass and its regular/inline transition. Only
    // arrange the persistent foreground inside the space it supplies.
    [self updateNativeAccessoryEnvironment];
    BOOL compact = self.compactPresentation || w < 240;
    CGFloat coverSize = GMMin(compact ? 26 : 30,GMMax(0,h-14));
    CGFloat controlsWidth = compact ? 46 : 88;
    self.bodyButton.frame = CGRectMake(0,0,GMMax(0,w-controlsWidth),h);
    self.cover.frame = CGRectMake(10,(h-coverSize)/2,coverSize,coverSize);
    CGFloat textX = coverSize+19, textWidth = GMMax(0,w-textX-controlsWidth-4);
    self.titleLabel.frame = CGRectMake(textX,(h-33)/2,textWidth,19);
    self.artistLabel.frame = CGRectMake(textX,(h-33)/2+20,textWidth,14);
    self.playButton.frame = CGRectMake(w-(compact ? 40 : 84),(h-30)/2,30,30);
    self.nextButton.frame = CGRectMake(w-40,(h-30)/2,30,30);
    self.nextButton.alpha = compact ? 0 : 1;
    self.nextButton.userInteractionEnabled = !compact;
    self.nextButton.accessibilityElementsHidden = compact;
}
- (void)applyTheme {
    self.titleLabel.textColor = GMPrimaryTextColor(); self.artistLabel.textColor = GMSecondaryTextColor();
    // The native accessory supplies one glass surface for the whole pill.
    // Nested glass button backdrops can lag its zoom snapshot on both ends.
    for (UIButton *button in @[self.playButton,self.nextButton]) {
        UIImage *image = button.configuration.image;
        UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
        configuration.image = image;
        configuration.baseForegroundColor = GMCurrentAccent();
        configuration.baseBackgroundColor = [UIColor clearColor];
        configuration.buttonSize = 2;
        configuration.contentInsets = NSDirectionalEdgeInsetsMake(4,4,4,4);
        button.configuration = configuration;
    }
    [self refresh];
}
- (void)refresh {
    PlayerController *engine = self.shell.player;
    NSInteger index = engine.selectedIndex;
    BOOL valid = index >= 0 && index < (NSInteger)engine.tracks.count;
    GMTrack *track = valid ? engine.tracks[index] : nil;
    self.titleLabel.text = track.title ?: @"Choose a song";
    self.artistLabel.text = track.artist ?: @"Music";
    GMConfigureArtwork(self.cover,track);
    self.bodyButton.accessibilityValue = [NSString stringWithFormat:@"%@, %@",self.titleLabel.text,self.artistLabel.text];
    BOOL playing = engine.player.isPlaying;
    GMSetButtonImage(self.playButton,GMPlayerSymbol(playing ? @"pause.fill" : @"play.fill",13));
    GMSetButtonImage(self.nextButton,GMPlayerSymbol(@"forward.end.fill",12));
    self.playButton.accessibilityLabel = playing ? @"Pause" : @"Play";
    self.playButton.enabled = engine.tracks.count > 0;
    self.nextButton.enabled = engine.tracks.count > 0;
}
- (void)openPlayer { [self.shell presentNowPlaying]; }
- (void)togglePlay { [self.shell.player togglePlay]; }
- (void)nextTrack { [self.shell.player nextTrack]; }
@end

@implementation GMMusicShell
- (void)viewDidLoad {
    [super viewDidLoad];
    NSURL *documents = [[[NSFileManager defaultManager] URLsForDirectory:9 inDomains:1] firstObject];
    // Keep the existing preference filename so build 3 appearance survives.
    NSDictionary *saved = documents ? [NSDictionary dictionaryWithContentsOfURL:[documents URLByAppendingPathComponent:@"GlassMusicSettings.plist"]] : nil;
    id storedMode = saved[@"appearance"];
    NSInteger mode = [storedMode isKindOfClass:[NSNumber class]] ? [storedMode integerValue] : 0;
    if (mode < 0 || mode > 3) mode = 0;
    UIColor *accent = GMColor(.98,.18,.32,1);
    id storedAccent = saved[@"accent"];
    if ([storedAccent isKindOfClass:[NSArray class]] && [storedAccent count] == 3) {
        BOOL valid = YES; CGFloat values[3] = {0,0,0};
        for (NSUInteger i=0;i<3;i++) {
            id value = storedAccent[i];
            if (![value isKindOfClass:[NSNumber class]]) { valid = NO; break; }
            values[i] = [value doubleValue];
            if (!(values[i]>=0 && values[i]<=1)) valid = NO;
        }
        if (valid) accent = GMColor(values[0],values[1],values[2],1);
    }
    self.appearanceMode = mode; self.accentColor = accent;
    GMSetThemeValues(mode,accent);
    self.overrideUserInterfaceStyle = mode == 3 ? 0 : mode;
    __weak GMMusicShell *weakShell = self;
    GMSharedPersonalization().fontDidChange = ^{
        GMMusicShell *shell = weakShell;
        [shell applyTheme];
        for (UIViewController *presented=shell.presentedViewController; presented; presented=presented.presentedViewController) {
            if ([presented isKindOfClass:[UINavigationController class]]) {
                UINavigationController *navigation=(UINavigationController *)presented;
                if ([NSStringFromClass(navigation.topViewController.class) hasPrefix:@"GM"]) {
                    GMApplyAppFontToNavigation(navigation.navigationBar);
                    GMApplyAppFontToViewTree(navigation.topViewController.view);
                }
            } else if ([NSStringFromClass(presented.class) hasPrefix:@"GM"] || presented==shell.player) {
                GMApplyAppFontToViewTree(presented.view);
            }
        }
    };
    self.lastSelectedIndex = -2;
    self.playlistStore = [[GMPlaylistStore alloc] initWithFileURL:[documents URLByAppendingPathComponent:@"MusicPlaylists.plist"]];
    self.editsStore = [[GMTrackEditsStore alloc] initWithFileURL:[documents URLByAppendingPathComponent:@"MusicEdits.plist"]];

    self.songsController = [GMSongsController new]; self.songsController.shell = self;
    self.albumsController = [GMAlbumsController new]; self.albumsController.shell = self;
    self.playlistsController = [GMPlaylistsController new]; self.playlistsController.shell = self;
    self.searchController = [GMSearchController new]; self.searchController.shell = self;
    self.settingsController = [GMSettingsController new]; self.settingsController.shell = self;
    NSArray *controllers = @[self.songsController,self.albumsController,self.playlistsController,self.searchController,self.settingsController];
    NSArray *titles = @[@"Songs",@"Albums",@"Playlists",@"Search",@"Settings"];
    NSArray *symbols = @[@"music.note",@"square.stack",@"music.note.list",@"magnifyingglass",@"gearshape"];
    NSMutableArray *navigationControllers = [NSMutableArray array];
    for (NSUInteger i=0;i<controllers.count;i++) {
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controllers[i]];
        navigation.navigationBar.prefersLargeTitles = YES;
        navigation.tabBarItem = [[UITabBarItem alloc] initWithTitle:titles[i] image:[UIImage systemImageNamed:symbols[i]] tag:(NSInteger)i];
        [navigationControllers addObject:navigation];
    }
    self.viewControllers = navigationControllers;
    self.player = [PlayerController new]; self.player.shell = self;
    [self.player loadViewIfNeeded];
    self.albumImporter = [[GMAlbumImporter alloc] initWithPlayer:self.player];
    self.compactPlayer = [[GMCompactPlayerView alloc] initWithFrame:CGRectMake(0,0,340,52)];
    self.compactPlayer.shell = self;
    Class accessoryClass = NSClassFromString(@"UITabAccessory");
    if (accessoryClass && [self respondsToSelector:@selector(setBottomAccessory:animated:)]) {
        self.nativeAccessory = [[accessoryClass alloc] initWithContentView:self.compactPlayer];
        if (self.nativeAccessory) [self setBottomAccessory:self.nativeAccessory animated:NO];
        // Keep the original UIKit bar and selection bubble alive. UIKit morphs
        // its own glass and moves this same accessory inline while scrolling.
        if ([self respondsToSelector:@selector(setTabBarMinimizeBehavior:)])
            [self setTabBarMinimizeBehavior:UITabBarMinimizeBehaviorOnScrollDown];
    }
    if (!self.nativeAccessory) {
        self.fallbackAccessory = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:6]];
        self.fallbackAccessory.layer.cornerRadius = 18; self.fallbackAccessory.clipsToBounds = YES;
        [self.fallbackAccessory.contentView addSubview:self.compactPlayer]; [self.view addSubview:self.fallbackAccessory];
        for (UIViewController *controller in controllers) controller.additionalSafeAreaInsets = UIEdgeInsetsMake(0,0,64,0);
    }
    [self applyTheme]; [self reloadLibrary];
    if (self.playlistStore.lastError) [self.player showMessage:@"Couldn't open playlists" message:self.playlistStore.lastError.localizedDescription];
    else if (self.editsStore.lastError) [self.player showMessage:@"Couldn't open saved song details" message:self.editsStore.lastError.localizedDescription];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.fallbackAccessory) {
        CGFloat width = self.view.bounds.size.width;
        self.fallbackAccessory.frame = CGRectMake(12,GMMax(0,self.tabBar.frame.origin.y-60),GMMax(0,width-24),52);
        self.compactPlayer.frame = self.fallbackAccessory.contentView.bounds;
    }

}
- (void)reloadLibrary {
    self.albums = GMAlbumsForTracks(self.player.tracks);
    for (UINavigationController *navigation in self.viewControllers) {
        for (GMBrowseTableController *controller in navigation.viewControllers) {
            if ([controller respondsToSelector:@selector(reloadLibrary)]) [controller reloadLibrary];
        }
    }
    // Metadata may finish loading while an album/playlist picker is open.
    // Refresh its stable-ID snapshot without replacing a text editor's draft.
    for (UIViewController *presented = self.presentedViewController; presented; presented = presented.presentedViewController) {
        if ([presented isKindOfClass:[UINavigationController class]]) {
            for (GMBrowseTableController *controller in ((UINavigationController *)presented).viewControllers)
                if ([controller respondsToSelector:@selector(reloadLibrary)]) [controller reloadLibrary];
        } else if ([presented respondsToSelector:@selector(reloadLibrary)]) [(GMBrowseTableController *)presented reloadLibrary];
    }
    [self refreshPlaybackState];
}
- (void)refreshPlaybackState {
    [self.compactPlayer refresh];
    NSInteger index = self.player ? self.player.selectedIndex : -1;
    if (index != self.lastSelectedIndex) {
        self.lastSelectedIndex = index;
        for (UINavigationController *navigation in self.viewControllers) {
            GMBrowseTableController *controller = (GMBrowseTableController *)navigation.topViewController;
            if ([controller respondsToSelector:@selector(reloadLibrary)]) [controller reloadLibrary];
        }
    }
    if (self.selectedIndex < self.viewControllers.count) {
        UINavigationController *navigation = (UINavigationController *)self.viewControllers[self.selectedIndex];
        GMBrowseTableController *browser = (GMBrowseTableController *)navigation.topViewController;
        if ([browser respondsToSelector:@selector(refreshPlaybackIndicators)]) [browser refreshPlaybackIndicators];
    }
    UIViewController *presented = [self.player visiblePresenter];
    if ([presented isKindOfClass:[UINavigationController class]]) {
        GMBrowseTableController *browser = (GMBrowseTableController *)((UINavigationController *)presented).topViewController;
        if ([browser respondsToSelector:@selector(refreshPlaybackIndicators)]) [browser refreshPlaybackIndicators];
    }
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.player.caseTransitionInProgress) [self warmPlayerCase];
}
- (void)warmPlayerCase {
    if (!self.view.window || self.player.caseTransitionInProgress || self.player.view.window) return;
    if (!self.caseWarmHost) {
        self.caseWarmHost = [[UIView alloc] initWithFrame:CGRectMake(0,0,300,300)];
        self.caseWarmHost.userInteractionEnabled = NO;
        self.caseWarmHost.accessibilityElementsHidden = YES;
        // Stay above UIKit's quantized visibility cutoff while hidden behind navigation.
        self.caseWarmHost.alpha = .02;
        [self.view insertSubview:self.caseWarmHost atIndex:0];
    }
    [self.player.cdCaseView moveToHost:self.caseWarmHost frame:self.caseWarmHost.bounds prewarming:YES];
}
- (void)presentNowPlaying {
    CGRect source = [self.compactPlayer.cover convertRect:self.compactPlayer.cover.bounds toView:self.view.window];
    [self presentNowPlayingFromCaseRect:source];
}
- (void)presentNowPlayingFromCaseRect:(CGRect)sourceRect {
    if (!self.player || self.player.presentingViewController || self.presentedViewController) return;
    self.caseTransition = [GMPlayerCaseTransition new];
    self.caseTransition.shell = self; self.caseTransition.sourceRect = sourceRect;
    self.player.modalPresentationStyle = 0;
    if ([self.player respondsToSelector:@selector(setPreferredTransition:)]) self.player.preferredTransition = nil;
    self.player.transitioningDelegate = self.caseTransition;
    self.player.caseTransitionInProgress = YES;
    [self.player refreshPlayback];
    [self presentViewController:self.player animated:YES completion:nil];
}
- (BOOL)canImportMusic { return !self.player.importing && !self.albumImporter.busy; }
- (void)importSongs {
    if (self.player.importing || self.albumImporter.busy) return;
    if (self.selectedIndex == 3) {
        __weak GMMusicShell *weakSelf=self;
        [self.searchController performAfterDismissingSearch:^{ [weakSelf.player importMusic]; }];
    } else [self.player importMusic];
}
- (void)importAlbum {
    if (self.player.importing || self.albumImporter.busy) return;
    if (self.selectedIndex == 3) {
        __weak GMMusicShell *weakSelf=self;
        [self.searchController performAfterDismissingSearch:^{
            GMMusicShell *shell=weakSelf;
            [shell.albumImporter presentFromViewController:[shell.player visiblePresenter]];
        }];
    } else [self.albumImporter presentFromViewController:[self.player visiblePresenter]];
}
- (void)applyTheme {
    GMSetThemeValues(self.appearanceMode,self.accentColor);
    self.overrideUserInterfaceStyle = self.appearanceMode == 3 ? 0 : self.appearanceMode;
    self.view.backgroundColor = GMPageColor(); self.view.tintColor = GMCurrentAccent();
    // Preserve UIKit's native glass, including the selection bubble. Remove
    // any solid UIView backing and let the page's accent wash show through.
    self.tabBar.translucent = YES; self.tabBar.opaque = NO;
    self.tabBar.backgroundColor = [UIColor clearColor]; self.tabBar.tintColor = GMCurrentAccent();
    for (UINavigationController *navigation in self.viewControllers) {
        navigation.view.tintColor = GMCurrentAccent(); navigation.navigationBar.tintColor = GMCurrentAccent();
        GMApplyAppFontToNavigation(navigation.navigationBar);
        for (GMBrowseTableController *controller in navigation.viewControllers) {
            if ([controller respondsToSelector:@selector(applyTheme)]) [controller applyTheme];
            GMApplyAppFontToViewTree(controller.view);
        }
    }
    [self.compactPlayer applyTheme]; [self.player applyTheme];
    GMApplyAppFontToViewTree(self.compactPlayer);
}
- (void)setAppearanceMode:(NSInteger)mode persist:(BOOL)persist {
    if (mode < 0 || mode > 3) mode = 0;
    self.appearanceMode = mode; [self applyTheme];
    if (persist) [self savePreferences];
}
- (void)setAccentColor:(UIColor *)color persist:(BOOL)persist {
    self.accentColor = color ?: GMColor(.98,.18,.32,1); [self applyTheme];
    if (persist) [self savePreferences];
}
- (void)savePreferences {
    NSURL *documents = [[[NSFileManager defaultManager] URLsForDirectory:9 inDomains:1] firstObject];
    NSDictionary *preferences = @{@"appearance":@(self.appearanceMode), @"accent":@[@(GMAccentComponents[0]),@(GMAccentComponents[1]),@(GMAccentComponents[2])]};
    NSError *error = nil;
    BOOL saved = documents && [preferences writeToURL:[documents URLByAppendingPathComponent:@"GlassMusicSettings.plist"] error:&error];
    if (!saved) [self.player showMessage:@"Couldn't save appearance" message:error.localizedDescription ?: @"Please try choosing it again."];
}
@end
