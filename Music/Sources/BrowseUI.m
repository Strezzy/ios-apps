// Included after the shared player and MusicLibraryStore implementation.
// Collections retain stable identifiers and refresh their live track indexes
// whenever the shell reloads its library after an import or deletion.
#import "MusicScrollSettings.h"

static GMPlaylist *GMBrowsePlaylist(GMMusicShell *shell, NSString *identifier) {
    for (GMPlaylist *playlist in shell.playlistStore.playlists)
        if ([playlist.identifier isEqualToString:identifier]) return playlist;
    return nil;
}
static GMAlbum *GMBrowseAlbum(GMMusicShell *shell, NSString *identifier) {
    for (GMAlbum *album in shell.albums)
        if ([album.identifier isEqualToString:identifier]) return album;
    return nil;
}
static UIImage *GMBrowseTrackImage(GMTrack *track) {
    return track.artwork;
}
static GMTrack *GMBrowseTrack(GMMusicShell *shell, NSNumber *number) {
    NSInteger index = number ? number.integerValue : -1;
    return index >= 0 && index < (NSInteger)shell.player.tracks.count ? shell.player.tracks[index] : nil;
}
static NSString *GMBrowseSongCount(NSUInteger count) {
    return [NSString stringWithFormat:count == 1 ? @"%lu song" : @"%lu songs",(unsigned long)count];
}
static BOOL GMBrowseMatches(NSString *text, NSString *query) {
    return !query.length || [text localizedCaseInsensitiveContainsString:query];
}
static void GMBrowseSetArtwork(UIImageView *view, UIImage *image, NSString *fallback) {
    view.image = image ?: [UIImage systemImageNamed:fallback ?: @"music.note"];
    view.contentMode = image ? 2 : 1;
    view.backgroundColor = GMCardColor(); view.tintColor = GMCurrentAccent();
    view.layer.cornerRadius = 7; view.clipsToBounds = YES;
}
static UIView *GMBrowseMessage(NSString *message, CGFloat height) {
    UILabel *label = GMLabel(message,15,0,GMSecondaryTextColor());
    label.frame = CGRectMake(20,0,300,height); label.numberOfLines = 0;
    label.textAlignment = 1; label.autoresizingMask = 1UL<<1;
    return label;
}
static void GMBrowseReportError(GMMusicShell *shell, NSError *error) {
    [shell.player showMessage:@"Couldn't save this change" message:error.localizedDescription ?: @"Your playlist was not changed. Please try again."];
}
// Run the change after the name alert finishes dismissing. This permits a
// validation/storage error to present normally instead of competing with it.
static void GMBrowsePromptName(UIViewController *presenter, NSString *title, NSString *initialName, NSString *verb, void (^completion)(NSString *)) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:1];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Playlist name"; field.text = initialName;
        field.autocapitalizationType = 1; field.clearButtonMode = 1;
    }];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:1 handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:verb style:0 handler:^(UIAlertAction *action) {
        UIAlertController *current = weakAlert;
        NSString *name = [current.textFields.firstObject.text copy] ?: @"";
        [current dismissViewControllerAnimated:YES completion:^{ completion(name); }];
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

// The actual plus control owns UIKit's menu. UIKit supplies its glass and
// expansion/dismissal animation; the importer waits for that dismissal.
@interface GMImportMenuButton : UIButton
@property(nonatomic, weak) GMMusicShell *shell;
@property(nonatomic) BOOL menuVisible;
@property(nonatomic) NSUInteger menuGeneration;
@property(nonatomic) NSInteger pendingImport;
- (void)configureMenu;
- (void)requestImport:(NSInteger)choice;
- (void)performPendingImport;
@end
@implementation GMImportMenuButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    [self setImage:[UIImage systemImageNamed:@"plus"] forState:0];
    self.accessibilityLabel = @"Import Music";
    self.accessibilityHint = @"Choose Import Songs or Import Album.";
    self.showsMenuAsPrimaryAction = YES;
    GMStyleGlassButton(self,NO);
    return self;
}
- (CGSize)intrinsicContentSize { return CGSizeMake(44,44); }
- (void)configureMenu {
    __weak GMImportMenuButton *weakSelf = self;
    UIAction *songs = [UIAction actionWithTitle:@"Import Songs" image:[UIImage systemImageNamed:@"music.note"] identifier:nil handler:^(UIAction *action) {
        (void)action; [weakSelf requestImport:1];
    }];
    UIAction *album = [UIAction actionWithTitle:@"Import Album" image:[UIImage systemImageNamed:@"square.stack"] identifier:nil handler:^(UIAction *action) {
        (void)action; [weakSelf requestImport:2];
    }];
    if (![self.shell canImportMusic]) {
        songs.attributes = UIMenuElementAttributesDisabled;
        album.attributes = UIMenuElementAttributesDisabled;
    }
    self.menu = [UIMenu menuWithTitle:@"" children:@[songs,album]];
}
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location {
    // Rebuild only when opening, so busy state cannot become stale between
    // imports. UIButton still creates and presents the native configuration.
    [self configureMenu];
    return [super contextMenuInteraction:interaction configurationForMenuAtLocation:location];
}
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willDisplayMenuForConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionAnimating>)animator {
    self.menuVisible = YES; self.pendingImport = 0; self.menuGeneration++;
    [super contextMenuInteraction:interaction willDisplayMenuForConfiguration:configuration animator:animator];
}
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willEndForConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionAnimating>)animator {
    [super contextMenuInteraction:interaction willEndForConfiguration:configuration animator:animator];
    NSUInteger generation = self.menuGeneration;
    __weak GMImportMenuButton *weakSelf = self;
    void (^finished)(void) = ^{
        GMImportMenuButton *button = weakSelf;
        if (!button || button.menuGeneration != generation) return;
        button.menuVisible = NO;
        [button performPendingImport];
    };
    if (animator) [animator addCompletion:finished];
    else dispatch_async(dispatch_get_main_queue(),finished); // No animation: let UIKit finish its callback.
}
- (void)requestImport:(NSInteger)choice {
    if ((choice != 1 && choice != 2) || !self.window || ![self.shell canImportMusic]) return;
    self.pendingImport = choice;
    // Accessibility may invoke a menu action without a visible menu, or the
    // action may arrive just after UIKit's dismissal completion.
    if (!self.menuVisible) [self performPendingImport];
}
- (void)performPendingImport {
    NSInteger choice = self.pendingImport; self.pendingImport = 0;
    if (!choice || !self.window || ![self.shell canImportMusic]) return;
    if (choice == 1) [self.shell importSongs];
    else if (choice == 2) [self.shell importAlbum];
}
@end

@interface GMBrowseSongCell : UITableViewCell <UIGestureRecognizerDelegate>
@property(nonatomic, weak) GMBrowseTableController *browser;
@property(nonatomic, weak) GMMusicShell *shell;
@property(nonatomic, copy) NSString *songIdentifier;
@property(nonatomic, copy) NSString *playlistIdentifier;
@property(nonatomic, copy) NSString *playlistContextIdentifier;
@property(nonatomic, strong) UIView *foreground;
@property(nonatomic, strong) GMScrollAnimationView *scrollAnimationView;
@property(nonatomic, strong) UIImageView *rowImage;
@property(nonatomic, strong) GMCDCaseView *rowCase;
@property(nonatomic, strong) UILabel *rowTitle;
@property(nonatomic, strong) UILabel *rowSubtitle;
@property(nonatomic, strong) UIImageView *rowAccessory;
@property(nonatomic, strong) GMPlaybackIndicatorView *playbackIndicator;
@property(nonatomic, strong) UIView *actionTray;
@property(nonatomic, strong) UIView *trashSurface;
@property(nonatomic, strong) UIView *moreSurface;
@property(nonatomic, strong) UIButton *trashButton;
@property(nonatomic, strong) UIButton *moreButton;
@property(nonatomic, strong) UIPanGestureRecognizer *revealPan;
@property(nonatomic, strong) UIViewPropertyAnimator *revealAnimator;
@property(nonatomic) CGFloat revealOffset;
@property(nonatomic) CGFloat panStartOffset;
@property(nonatomic) BOOL panStartOpen;
@property(nonatomic) NSInteger normalAccessoryType;
@property(nonatomic) BOOL focusMoreWhenRevealed;
@property(nonatomic) BOOL nativeGlassContainer;
@property(nonatomic) BOOL nativeGlassCorners;
@property(nonatomic) BOOL usesPlaybackIndicator;
- (void)resetActions;
- (void)configureSongIdentifier:(NSString *)identifier playlistContext:(NSString *)playlistIdentifier;
- (void)configurePlaylistIdentifier:(NSString *)identifier;
- (void)setRevealOffset:(CGFloat)offset animated:(BOOL)animated;
- (void)refreshPlaybackIndicator;
- (void)interruptRevealAnimation;
@end

// Display records retain neither cells nor hosts. A row's entry is independent
// of its stable song ID: display/reuse boundaries, not data changes, trigger it.
@interface GMScrollRowDisplay : NSObject
@property(nonatomic, weak) UITableViewCell *cell;
@property(nonatomic, weak) GMScrollAnimationView *host;
@property(nonatomic, copy) NSIndexPath *indexPath;
@property(nonatomic) BOOL enteredViewport;
@end
@implementation GMScrollRowDisplay @end

static GMScrollAnimationView *GMBrowseEntryHost(UITableViewCell *cell) {
    if (![cell respondsToSelector:@selector(scrollAnimationView)]) return nil;
    return [(GMBrowseSongCell *)cell scrollAnimationView];
}
static BOOL GMBrowseEntryIsSafe(UITableViewCell *cell) {
    if (![cell isKindOfClass:[GMBrowseSongCell class]]) return YES;
    GMBrowseSongCell *song = (GMBrowseSongCell *)cell;
    return song.revealOffset <= .01 && !song.revealAnimator &&
        song.revealPan.state != UIGestureRecognizerStateBegan &&
        song.revealPan.state != UIGestureRecognizerStateChanged;
}
static BOOL GMBrowseEntryVisible(UITableView *table, UITableViewCell *cell) {
    if (!cell.window || cell.window != table.window) return NO;
    CGRect frame = [cell convertRect:cell.bounds toView:table];
    CGFloat top = table.contentOffset.y+table.adjustedContentInset.top;
    CGFloat bottom = table.contentOffset.y+table.bounds.size.height-table.adjustedContentInset.bottom;
    return frame.size.height > 0 && bottom > top && frame.origin.y+frame.size.height > top+1 &&
        frame.origin.y < bottom-1;
}
static BOOL GMBrowseEntryEnabled(void) {
    return [GMScrollSettings sharedSettings].enabled && !UIAccessibilityIsReduceMotionEnabled() &&
        !UIAccessibilityPrefersCrossFadeTransitions();
}

@interface GMBrowseTableController ()
@property(nonatomic, weak) GMBrowseSongCell *revealedCell;
@property(nonatomic, strong) NSMutableArray<GMScrollRowDisplay *> *scrollRows;
@property(nonatomic) BOOL scrollUserGesture;
@property(nonatomic) CGFloat scrollPreviousOffset;
@property(nonatomic) NSInteger scrollDirection;
@property(nonatomic) CGSize scrollViewportSize;
- (void)revealActionsInCell:(GMBrowseSongCell *)cell;
- (GMScrollRowDisplay *)scrollRecordForCell:(UITableViewCell *)cell create:(BOOL)create;
- (void)updateScrollRecord:(GMScrollRowDisplay *)record animate:(BOOL)animate;
- (void)scrollAnimationEnvironmentChanged:(NSNotification *)notification;
@end

@implementation GMBrowseTableController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:self.tableStyle];
    self.table.autoresizingMask = (1UL<<1)|(1UL<<4);
    self.table.dataSource = self; self.table.delegate = self; self.table.rowHeight = 72;
    self.table.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.table];
    [self setContentScrollView:self.table forEdge:NSDirectionalRectEdgeAll];
    self.scrollRows = [NSMutableArray array];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(scrollAnimationEnvironmentChanged:)
                   name:GMScrollSettingsDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(scrollAnimationEnvironmentChanged:)
                   name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(scrollAnimationEnvironmentChanged:)
                   name:UIApplicationDidEnterBackgroundNotification object:nil];
    GMApplyPageBackground(self.view,self.table,self.tableStyle != 0);
    self.table.separatorColor = GMSeparatorColor();
    GMImportMenuButton *plus = [[GMImportMenuButton alloc] initWithFrame:CGRectMake(0,0,44,44)];
    plus.shell = self.shell; [plus configureMenu];
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithCustomView:plus];
    // The button already owns its native glass. Do not add a second shared
    // glass background around the custom bar item on iOS 26.
    if ([item respondsToSelector:@selector(setHidesSharedBackground:)]) item.hidesSharedBackground = YES;
    self.navigationItem.rightBarButtonItem = item;
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self applyTheme]; }
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self resetScrollEntryAnimations];
    [self closeRevealedActionsIfNeeded];
}
- (void)reloadLibrary {
    // Metadata, search, selection and theme refreshes also reach this method.
    // Disarm entry animation until a new user drag, including deferred display
    // callbacks from reloadData, so stationary rows never replay an entrance.
    [self resetScrollEntryAnimations];
    [self.revealedCell setRevealOffset:0 animated:NO]; self.revealedCell = nil;
    [self.table reloadData];
}
- (void)resetScrollEntryAnimations {
    self.scrollUserGesture = NO; self.scrollDirection = 0;
    self.scrollPreviousOffset = self.table.contentOffset.y;
    self.scrollViewportSize = self.table.bounds.size;
    for (GMScrollRowDisplay *record in self.scrollRows) [record.host resetScrollAnimation];
    [self.scrollRows removeAllObjects];
    for (UITableViewCell *cell in self.table.visibleCells) [GMBrowseEntryHost(cell) resetScrollAnimation];
}
- (void)scrollAnimationEnvironmentChanged:(NSNotification *)notification {
    if (![NSThread isMainThread]) {
        __weak GMBrowseTableController *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(),^{ [weakSelf resetScrollEntryAnimations]; });
        return;
    }
    [self resetScrollEntryAnimations];
}
- (GMScrollRowDisplay *)scrollRecordForCell:(UITableViewCell *)cell create:(BOOL)create {
    for (GMScrollRowDisplay *record in self.scrollRows) if (record.cell == cell) return record;
    GMScrollAnimationView *host = GMBrowseEntryHost(cell);
    if (!create || !host) return nil;
    GMScrollRowDisplay *record = [GMScrollRowDisplay new];
    record.cell = cell; record.host = host;
    [self.scrollRows addObject:record];
    return record;
}
- (void)updateScrollRecord:(GMScrollRowDisplay *)record animate:(BOOL)animate {
    UITableViewCell *cell = record.cell;
    if (!cell || !record.host) { [self.scrollRows removeObject:record]; return; }
    BOOL visible = GMBrowseEntryVisible(self.table,cell);
    if (!visible) {
        if (record.enteredViewport) [record.host resetScrollAnimation];
        record.enteredViewport = NO;
        return;
    }
    if (record.enteredViewport) return;
    record.enteredViewport = YES;
    if (animate && GMBrowseEntryIsSafe(cell)) {
        // willDisplay can precede the cell's first final content layout.
        // Settle only this cell before starting its independent host effect.
        [cell layoutIfNeeded];
        if (!record.host.window || !(record.host.bounds.size.width > 0 && record.host.bounds.size.height > 0)) {
            record.enteredViewport = NO; return;
        }
        [record.host animateWithPreset:[GMScrollSettings sharedSettings].presetIdentifier];
    }
}
- (void)tableView:(UITableView *)table willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)path {
    GMScrollAnimationView *host = GMBrowseEntryHost(cell);
    if (!host) return; // Settings, fields, native controls and headers opt out.
    GMScrollRowDisplay *record = [self scrollRecordForCell:cell create:YES];
    if (record.indexPath && ![record.indexPath isEqual:path]) {
        [host resetScrollAnimation]; record.enteredViewport = NO;
    }
    record.indexPath = path;
    BOOL active = self.scrollUserGesture && GMBrowseEntryEnabled() &&
        (table.isDragging || table.isDecelerating || table.isTracking);
    // The first drag may deliver willDisplay before its first offset callback.
    // Leave that new entry pending; existing rows were baselined at drag start.
    if (!active || self.scrollDirection != 0) [self updateScrollRecord:record animate:active];
}
- (void)tableView:(UITableView *)table didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)path {
    for (GMScrollRowDisplay *record in [self.scrollRows copy]) {
        if (record.cell != cell || (record.indexPath && ![record.indexPath isEqual:path])) continue;
        [record.host resetScrollAnimation]; [self.scrollRows removeObject:record];
    }
}
- (void)tableView:(UITableView *)table didHighlightRowAtIndexPath:(NSIndexPath *)path {
    [GMBrowseEntryHost([table cellForRowAtIndexPath:path]) resetScrollAnimation];
}
- (NSIndexPath *)tableView:(UITableView *)table willSelectRowAtIndexPath:(NSIndexPath *)path {
    [GMBrowseEntryHost([table cellForRowAtIndexPath:path]) resetScrollAnimation];
    return path;
}
- (void)refreshPlaybackIndicators {
    for (UITableViewCell *cell in self.table.visibleCells)
        if ([cell isKindOfClass:[GMBrowseSongCell class]]) [(GMBrowseSongCell *)cell refreshPlaybackIndicator];
}
- (void)revealActionsInCell:(GMBrowseSongCell *)cell {
    [cell.scrollAnimationView resetScrollAnimation];
    if (self.revealedCell != cell) [self.revealedCell setRevealOffset:0 animated:YES];
    self.revealedCell = cell;
}
- (BOOL)closeRevealedActionsIfNeeded {
    GMBrowseSongCell *cell = self.revealedCell;
    self.revealedCell = nil;
    if (!cell || cell.revealOffset <= 0) return NO;
    [cell setRevealOffset:0 animated:YES];
    return YES;
}
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [self closeRevealedActionsIfNeeded];
    if (scrollView != self.table || !GMBrowseEntryEnabled()) return;
    self.scrollUserGesture = YES; self.scrollDirection = 0;
    self.scrollPreviousOffset = scrollView.contentOffset.y;
    self.scrollViewportSize = scrollView.bounds.size;
    // Rows already visible when a finger lands are a baseline, not entries.
    for (UITableViewCell *cell in self.table.visibleCells) {
        GMScrollRowDisplay *record = [self scrollRecordForCell:cell create:YES];
        record.enteredViewport = GMBrowseEntryVisible(self.table,cell);
    }
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView != self.table || !self.table.window || !GMBrowseEntryEnabled()) return;
    CGFloat offset = scrollView.contentOffset.y;
    CGFloat movement = offset-self.scrollPreviousOffset;
    self.scrollPreviousOffset = offset;
    CGSize size = scrollView.bounds.size;
    if (self.scrollUserGesture && size.width != self.scrollViewportSize.width) {
        [self resetScrollEntryAnimations]; return;
    }
    // Native tab/accessory minimization may change only the viewport height.
    // Keep this user scroll armed and preserve existing rows' entered flags;
    // UIKit's own transition must not disable subsequent scrolling effects.
    self.scrollViewportSize = size;
    BOOL active = self.scrollUserGesture && (scrollView.isDragging || scrollView.isTracking || scrollView.isDecelerating);
    if (movement > .1) self.scrollDirection = 1;
    else if (movement < -.1) self.scrollDirection = -1;
    for (UITableViewCell *cell in self.table.visibleCells) [self scrollRecordForCell:cell create:YES];
    // A zero/sub-pixel first offset callback must not consume entries that
    // willDisplay left pending until the first meaningful drag direction.
    if (active && self.scrollDirection == 0) return;
    for (GMScrollRowDisplay *record in [self.scrollRows copy])
        [self updateScrollRecord:record animate:active && self.scrollDirection != 0];
}
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (scrollView == self.table && !decelerate) self.scrollUserGesture = NO;
}
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView == self.table) self.scrollUserGesture = NO;
}
- (void)applyTheme {
    if (!self.table) return;
    GMApplyPageBackground(self.view,self.table,self.tableStyle != 0);
    self.table.separatorColor = GMSeparatorColor();
    self.view.tintColor = GMCurrentAccent();
    UIView *plus = self.navigationItem.rightBarButtonItem.customView;
    if ([plus isKindOfClass:[GMImportMenuButton class]]) GMStyleGlassButton((UIButton *)plus,NO);
    [self reloadLibrary];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return 0; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    // The base class has zero rows; concrete browsers provide their own cells.
    return [[UITableViewCell alloc] initWithStyle:0 reuseIdentifier:nil];
}
// Actions use our glass button tray. No system full-swipe delete path exists.
- (BOOL)tableView:(UITableView *)table canEditRowAtIndexPath:(NSIndexPath *)path { return NO; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end

static const CGFloat GMBrowseActionTrayWidth = 132;
@implementation GMBrowseSongCell
- (id)initWithStyle:(NSInteger)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (!self) return nil;
    self.clipsToBounds = YES;
    // Selection remains enabled for taps and accessibility. Only UIKit's
    // transient selected/highlighted background is suppressed.
    self.selectionStyle = 0;
    self.selectedBackgroundView = [[UIView alloc] initWithFrame:CGRectZero];
    self.selectedBackgroundView.backgroundColor = [UIColor clearColor];
    [super setAccessoryType:0];
    self.foreground = [[UIView alloc] initWithFrame:self.contentView.bounds];
    self.foreground.backgroundColor = [UIColor clearColor];
    self.foreground.clipsToBounds = YES;
    self.foreground.layer.maskedCorners = kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner;
    self.scrollAnimationView = [[GMScrollAnimationView alloc] initWithFrame:self.foreground.bounds];
    [self.foreground addSubview:self.scrollAnimationView];
    self.rowImage = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.rowCase = [[GMCDCaseView alloc] initWithFrame:CGRectZero presentation:GMCDCasePresentationStatic];
    self.rowCase.userInteractionEnabled = NO; self.rowCase.hidden = YES;
    self.rowTitle = GMLabel(@"",17,0,GMPrimaryTextColor());
    self.rowSubtitle = GMLabel(@"",13,0,GMSecondaryTextColor());
    self.rowAccessory = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.rowAccessory.contentMode = 1;
    self.playbackIndicator = [[GMPlaybackIndicatorView alloc] initWithFrame:CGRectMake(0,0,22,22)];
    UIView *entryContent = self.scrollAnimationView.contentView;
    [entryContent addSubview:self.rowCase]; [entryContent addSubview:self.rowImage]; [entryContent addSubview:self.rowTitle];
    [entryContent addSubview:self.rowSubtitle]; [entryContent addSubview:self.rowAccessory];
    [entryContent addSubview:self.playbackIndicator];

    Class containerClass = NSClassFromString(@"UIGlassContainerEffect");
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    UIView *actionHost = nil;
    UIView *trashHost = nil, *moreHost = nil;
    if (containerClass && [glassClass respondsToSelector:@selector(effectWithStyle:)]) {
        UIGlassContainerEffect *containerEffect = [containerClass new];
        containerEffect.spacing = 5;
        UIVisualEffectView *container = [[UIVisualEffectView alloc] initWithEffect:containerEffect];
        self.actionTray = container; actionHost = container.contentView;
        UIGlassEffect *trashEffect = [glassClass effectWithStyle:UIGlassEffectStyleRegular];
        UIGlassEffect *moreEffect = [glassClass effectWithStyle:UIGlassEffectStyleRegular];
        trashEffect.interactive = YES; moreEffect.interactive = YES;
        UIVisualEffectView *trashGlass = [[UIVisualEffectView alloc] initWithEffect:trashEffect];
        UIVisualEffectView *moreGlass = [[UIVisualEffectView alloc] initWithEffect:moreEffect];
        self.trashSurface = trashGlass; self.moreSurface = moreGlass;
        trashHost = trashGlass.contentView; moreHost = moreGlass.contentView;
        self.nativeGlassContainer = YES;
    } else {
        self.actionTray = [[UIView alloc] initWithFrame:CGRectZero]; actionHost = self.actionTray;
        self.trashSurface = [[UIView alloc] initWithFrame:CGRectZero];
        self.moreSurface = [[UIView alloc] initWithFrame:CGRectZero];
        trashHost = self.trashSurface; moreHost = self.moreSurface;
    }
    self.actionTray.backgroundColor = [UIColor clearColor];
    // A fixed container keeps the material alive throughout the gesture.
    // Only the two child surfaces move and change size; no glass is faded or
    // cropped by a changing clip rectangle.
    [actionHost addSubview:self.trashSurface]; [actionHost addSubview:self.moreSurface];
    Class cornerClass = NSClassFromString(@"UICornerConfiguration");
    if ([cornerClass respondsToSelector:@selector(capsuleConfiguration)] &&
        [self.trashSurface respondsToSelector:@selector(setCornerConfiguration:)]) {
        self.trashSurface.cornerConfiguration = [cornerClass capsuleConfiguration];
        self.moreSurface.cornerConfiguration = [cornerClass capsuleConfiguration];
        self.nativeGlassCorners = YES;
    }
    self.trashButton = [UIButton buttonWithType:1];
    self.moreButton = [UIButton buttonWithType:1];
    [self.trashButton setImage:[UIImage systemImageNamed:@"trash"] forState:0];
    [self.moreButton setImage:[UIImage systemImageNamed:@"ellipsis"] forState:0];
    self.trashButton.autoresizingMask = (1UL<<1)|(1UL<<4);
    self.moreButton.autoresizingMask = (1UL<<1)|(1UL<<4);
    self.moreButton.showsMenuAsPrimaryAction = YES;
    self.moreButton.accessibilityLabel = @"More actions";
    [self.trashButton addTarget:self action:@selector(deleteItem) forControlEvents:(1UL<<6)];
    [trashHost addSubview:self.trashButton]; [moreHost addSubview:self.moreButton];
    [self.contentView addSubview:self.actionTray]; [self.contentView addSubview:self.foreground];
    self.revealPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleRevealPan:)];
    self.revealPan.delegate = self;
    self.revealPan.maximumNumberOfTouches = 1;
    [self addGestureRecognizer:self.revealPan];
    [self resetActions];
    return self;
}
// Preserve the existing browser/destination-picker cell contract, while the
// views belong to an independent foreground that UIKit never repositions.
- (UIImageView *)imageView { return self.rowImage; }
- (UILabel *)textLabel { return self.rowTitle; }
- (UILabel *)detailTextLabel { return self.rowSubtitle; }
- (void)prepareForReuse {
    [super prepareForReuse];
    [self resetActions];
}
- (void)resetActions {
    [self.rowCase prepareForReuse]; self.rowCase.hidden = YES; self.rowImage.hidden = NO;
    [self.scrollAnimationView resetScrollAnimation];
    self.revealPan.enabled = NO;
    [self interruptRevealAnimation];
    self.songIdentifier = nil; self.playlistIdentifier = nil; self.playlistContextIdentifier = nil;
    self.moreButton.menu = nil;
    self.focusMoreWhenRevealed = NO;
    self.usesPlaybackIndicator = NO; [self.playbackIndicator reset];
    self.normalAccessoryType = 0; self.rowAccessory.hidden = YES;
    self.accessibilityCustomActions = nil;
    self.accessibilityLabel = nil; self.accessibilityHint = nil; self.accessibilityValue = nil;
    [self setRevealOffset:0 animated:NO];
    self.browser = nil; self.shell = nil;
}
- (void)configureActionAppearance {
    if (self.nativeGlassContainer) {
        // The surrounding UIGlassEffect views provide the material and
        // interaction. A second glass button background would double it.
        UIButtonConfiguration *trash = [UIButtonConfiguration plainButtonConfiguration];
        UIButtonConfiguration *more = [UIButtonConfiguration plainButtonConfiguration];
        trash.image = [UIImage systemImageNamed:@"trash"];
        more.image = [UIImage systemImageNamed:@"ellipsis"];
        trash.baseForegroundColor = [UIColor systemRedColor];
        more.baseForegroundColor = GMCurrentAccent();
        trash.contentInsets = (NSDirectionalEdgeInsets){0,0,0,0};
        more.contentInsets = (NSDirectionalEdgeInsets){0,0,0,0};
        self.trashButton.configuration = trash; self.moreButton.configuration = more;
    } else {
        GMStyleGlassButton(self.trashButton,NO);
        GMStyleGlassButton(self.moreButton,NO);
    }
    UIButtonConfiguration *trashStyle = [self.trashButton.configuration copy];
    trashStyle.baseForegroundColor = [UIColor systemRedColor];
    self.trashButton.configuration = trashStyle;
    self.trashButton.tintColor = [UIColor systemRedColor];
    self.trashButton.accessibilityLabel = self.playlistIdentifier ? @"Delete playlist" : @"Delete song";
    self.moreButton.accessibilityLabel = self.playlistIdentifier ? @"More playlist actions" : @"More song actions";
    self.revealPan.enabled = YES;
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@",self.textLabel.text ?: @"",self.detailTextLabel.text ?: @""];
    self.accessibilityHint = @"More and Delete actions are available";
    self.accessibilityCustomActions = @[
        [[UIAccessibilityCustomAction alloc] initWithName:self.trashButton.accessibilityLabel target:self selector:@selector(accessibilityDelete:)],
        [[UIAccessibilityCustomAction alloc] initWithName:@"Show More actions" target:self selector:@selector(accessibilityShowMore:)]];
}
- (void)configureSongIdentifier:(NSString *)identifier playlistContext:(NSString *)playlistIdentifier {
    if (!identifier.length || !self.shell) return;
    self.songIdentifier = identifier; self.playlistIdentifier = nil;
    self.playlistContextIdentifier = playlistIdentifier;
    UIMenu *menu = [self.shell songMenuForIdentifier:identifier fromView:self.moreButton];
    if (playlistIdentifier.length) {
        NSMutableArray *children = [menu.children mutableCopy] ?: [NSMutableArray array];
        NSString *songID = [identifier copy], *playlistID = [playlistIdentifier copy];
        __weak GMMusicShell *weakShell = self.shell;
        UIAction *remove = [UIAction actionWithTitle:@"Remove from Playlist" image:[UIImage systemImageNamed:@"minus.circle"] identifier:nil handler:^(UIAction *action) {
            [weakShell confirmRemoveSongIdentifier:songID fromPlaylist:playlistID];
        }];
        [children addObject:remove];
        menu = [UIMenu menuWithTitle:@"" children:children];
    }
    self.moreButton.menu = menu;
    [self configureActionAppearance];
}
- (void)configurePlaylistIdentifier:(NSString *)identifier {
    if (!identifier.length || !self.shell) return;
    self.songIdentifier = nil; self.playlistIdentifier = identifier; self.playlistContextIdentifier = nil;
    self.moreButton.menu = [self.shell playlistMenuForIdentifier:identifier fromView:self.moreButton];
    [self configureActionAppearance];
}
- (void)setAccessoryType:(NSInteger)accessoryType {
    _normalAccessoryType = accessoryType;
    self.rowAccessory.image = [UIImage systemImageNamed:accessoryType == 3 ? @"checkmark" : @"chevron.right"];
    self.rowAccessory.tintColor = accessoryType == 3 ? GMCurrentAccent() : GMSecondaryTextColor();
    self.rowAccessory.hidden = accessoryType == 0;
}
- (void)refreshPlaybackIndicator {
    NSInteger selected = self.shell.player ? self.shell.player.selectedIndex : -1;
    GMTrack *track = selected >= 0 && selected < (NSInteger)self.shell.player.tracks.count ? self.shell.player.tracks[selected] : nil;
    BOOL current = self.usesPlaybackIndicator && self.songIdentifier.length &&
        [self.songIdentifier isEqualToString:GMTrackIdentifier(track)];
    self.playbackIndicator.tintColor = GMCurrentAccent();
    if (current) {
        BOOL playing = self.shell.player.player.playing;
        [self.playbackIndicator configurePlaying:playing];
        self.accessibilityValue = playing ? @"Playing" : @"Paused";
    } else {
        [self.playbackIndicator reset];
        self.accessibilityValue = nil;
    }
    self.rowAccessory.hidden = self.normalAccessoryType == 0 || current;
}
- (void)updateRevealGeometry {
    CGFloat progress = self.revealOffset/GMBrowseActionTrayWidth;
    CGFloat appearanceProgress = GMMax(0,GMMin(1,progress));
    CGFloat width = self.contentView.bounds.size.width, height = self.contentView.bounds.size.height;
    self.foreground.transform = CGAffineTransformMakeTranslation(-self.revealOffset,0);
    // Color and trailing corners share the same progress as translation.
    // Their spring interpolation therefore remains continuous when a new
    // drag takes over at the last rendered position. The glass is a sibling
    // of this foreground, so its material and ancestors keep full opacity.
    self.foreground.backgroundColor = [[UIColor systemGray5Color] colorWithAlphaComponent:.94*appearanceProgress];
    self.foreground.layer.cornerRadius = 18*appearanceProgress;
    // Both surfaces originate together just beyond the trailing edge. Their
    // shared native container forms a single glass shape at first, then
    // separates it as the center distance grows past the material spacing.
    CGFloat size = 22+28*progress;
    CGFloat trashCenter = width+40-139*progress;
    CGFloat moreCenter = width+40-81*progress;
    self.trashSurface.frame = CGRectMake(trashCenter-size/2,(height-size)/2,size,size);
    self.moreSurface.frame = CGRectMake(moreCenter-size/2,(height-size)/2,size,size);
    self.trashButton.frame = CGRectMake(0,0,size,size);
    self.moreButton.frame = CGRectMake(0,0,size,size);
    // Only the foreground symbols fade in; every material view and its
    // ancestors stay at full opacity for the native glass renderer.
    if (self.nativeGlassContainer) {
        CGFloat symbolAlpha = GMMax(0,GMMin(1,(progress-.22)/.5));
        self.trashButton.alpha = symbolAlpha; self.moreButton.alpha = symbolAlpha;
    }
    if (!self.nativeGlassCorners) {
        self.trashSurface.layer.cornerRadius = size/2;
        self.moreSurface.layer.cornerRadius = size/2;
    }
}
- (void)updateRevealAccessibility {
    BOOL revealed = self.revealOffset > .01;
    self.isAccessibilityElement = !revealed;
    self.foreground.accessibilityElementsHidden = revealed;
    self.actionTray.accessibilityElementsHidden = !revealed;
    self.actionTray.userInteractionEnabled = self.revealOffset >= GMBrowseActionTrayWidth*.8;
}
- (void)completeReveal {
    // Closed surfaces are fully outside the cell. Keep their fixed material
    // container alive so the next drag never has to restart the glass effect.
    [self updateRevealAccessibility];
    if (self.focusMoreWhenRevealed && self.revealOffset >= GMBrowseActionTrayWidth) {
        self.focusMoreWhenRevealed = NO;
        UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification,self.moreButton);
    }
}
- (void)interruptRevealAnimation {
    UIViewPropertyAnimator *animator = self.revealAnimator;
    if (!animator) return;
    // Clear ownership before callbacks. Stopping promotes the last rendered
    // position into the model, so a new drag starts exactly where it appears.
    self.revealAnimator = nil;
    if (animator.state == UIViewAnimatingStateActive) [animator stopAnimation:NO];
    if (animator.state == UIViewAnimatingStateStopped) [animator finishAnimationAtPosition:UIViewAnimatingPositionCurrent];
    _revealOffset = GMMax(0,GMMin(148,-self.foreground.transform.tx));
}
- (void)setRevealOffset:(CGFloat)offset animated:(BOOL)animated {
    // Horizontal interaction has exclusive ownership of the swipe foreground.
    // Settle the independent entry effect before moving or exposing this row.
    [self.scrollAnimationView resetScrollAnimation];
    [self interruptRevealAnimation];
    CGFloat startingOffset = self.revealOffset;
    _revealOffset = GMMax(0,GMMin(148,offset));
    if (_revealOffset <= .01) self.focusMoreWhenRevealed = NO;
    self.actionTray.hidden = NO;
    [self updateRevealAccessibility];
    CGFloat distance = _revealOffset-startingOffset;
    if (distance < 0) distance = -distance;
    if (!animated || distance < .25 || UIAccessibilityIsReduceMotionEnabled()) {
        [self updateRevealGeometry]; [self completeReveal];
        return;
    }
    __weak GMBrowseSongCell *weakSelf = self;
    BOOL opening = _revealOffset > 0;
    UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc] initWithDuration:opening ? .38 : .32 dampingRatio:opening ? .86 : .94 animations:^{
        [weakSelf updateRevealGeometry];
    }];
    __weak UIViewPropertyAnimator *weakAnimator = animator;
    [animator addCompletion:^(UIViewAnimatingPosition position) {
        GMBrowseSongCell *cell = weakSelf;
        if (!cell || position != UIViewAnimatingPositionEnd || cell.revealAnimator != weakAnimator) return;
        cell.revealAnimator = nil;
        [cell completeReveal];
    }];
    self.revealAnimator = animator;
    [animator startAnimation];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.contentView.bounds.size.height, w = self.contentView.bounds.size.width;
    BOOL sizeChanged = self.foreground.bounds.size.width != w || self.foreground.bounds.size.height != h;
    BOOL settleAfterResize = sizeChanged && self.revealAnimator != nil;
    CGFloat revealTarget = self.revealOffset;
    if (sizeChanged) {
        [self interruptRevealAnimation];
        // Rotation or multitasking should finish the intended snap, rather
        // than leave a stopped spring at an arbitrary partial reveal.
        if (settleAfterResize) _revealOffset = revealTarget;
    }
    // Bounds and center remain independent of the foreground translation.
    // UIKit owns a stationary contentView for the entire gesture and spring.
    self.foreground.bounds = CGRectMake(0,0,w,h); self.foreground.center = CGPointMake(w/2,h/2);
    self.scrollAnimationView.frame = self.foreground.bounds;
    self.actionTray.frame = CGRectMake(0,0,w,h);
    self.rowImage.frame = CGRectMake(20,(h-48)/2,48,48);
    self.rowCase.frame = self.rowImage.frame;
    self.rowTitle.frame = CGRectMake(80,(h-44)/2,GMMax(0,w-124),24);
    self.rowSubtitle.frame = CGRectMake(80,(h-44)/2+26,GMMax(0,w-124),18);
    self.rowAccessory.frame = CGRectMake(GMMax(0,w-40),(h-18)/2,18,18);
    self.playbackIndicator.frame = CGRectMake(GMMax(0,w-42),(h-22)/2,22,22);
    if (!self.revealAnimator) [self updateRevealGeometry];
    if (settleAfterResize) [self completeReveal];
    if (!self.songIdentifier.length && !self.playlistIdentifier.length)
        self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@",self.rowTitle.text ?: @"",self.rowSubtitle.text ?: @""];
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer != self.revealPan) return YES;
    if (!self.songIdentifier.length && !self.playlistIdentifier.length) return NO;
    CGPoint velocity = [self.revealPan velocityInView:self];
    CGFloat horizontal = velocity.x < 0 ? -velocity.x : velocity.x;
    CGFloat vertical = velocity.y < 0 ? -velocity.y : velocity.y;
    if (horizontal <= vertical*1.25) return NO;
    return self.revealAnimator != nil || self.revealOffset > 0 || velocity.x < 0;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (gestureRecognizer != self.revealPan) return YES;
    for (UIView *view = touch.view; view && view != self; view = view.superview)
        if ([view isKindOfClass:[UIControl class]]) return NO;
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other {
    // Give this horizontal gate first refusal; a vertical movement fails it
    // immediately and proceeds through the table's unchanged native pan.
    return gestureRecognizer == self.revealPan && other == self.browser.table.panGestureRecognizer;
}
- (void)handleRevealPan:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.panStartOpen = self.revealOffset >= GMBrowseActionTrayWidth/2;
        [self interruptRevealAnimation];
        self.focusMoreWhenRevealed = NO;
        self.panStartOffset = self.revealOffset;
        [self.browser revealActionsInCell:self];
    }
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        CGFloat offset = self.panStartOffset-[gesture translationInView:self].x;
        // A small bounded stretch replaces the hard stop at full reveal.
        if (offset > GMBrowseActionTrayWidth) {
            CGFloat excess = offset-GMBrowseActionTrayWidth;
            offset = GMBrowseActionTrayWidth+(16*excess)/(excess+80);
        }
        [self setRevealOffset:offset animated:NO];
    } else if (gesture.state == UIGestureRecognizerStateEnded) {
        CGFloat velocity = [gesture velocityInView:self].x;
        CGFloat projectedOffset = self.revealOffset-velocity*.10;
        BOOL open = projectedOffset > GMBrowseActionTrayWidth/2;
        [self setRevealOffset:open ? GMBrowseActionTrayWidth : 0 animated:YES];
    } else if (gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        [self setRevealOffset:self.panStartOpen ? GMBrowseActionTrayWidth : 0 animated:YES];
    }
}
- (void)deleteItem {
    NSString *songID = [self.songIdentifier copy], *playlistID = [self.playlistIdentifier copy];
    GMMusicShell *shell = self.shell;
    [self.browser closeRevealedActionsIfNeeded];
    if (playlistID.length) [shell confirmDeletePlaylistWithIdentifier:playlistID];
    else if (songID.length) [shell confirmDeleteSongWithIdentifier:songID];
}
- (BOOL)accessibilityDelete:(UIAccessibilityCustomAction *)action {
    if (!self.songIdentifier.length && !self.playlistIdentifier.length) return NO;
    [self deleteItem]; return YES;
}
- (BOOL)accessibilityShowMore:(UIAccessibilityCustomAction *)action {
    if (!self.songIdentifier.length && !self.playlistIdentifier.length) return NO;
    [self.browser revealActionsInCell:self];
    self.focusMoreWhenRevealed = YES;
    [self setRevealOffset:GMBrowseActionTrayWidth animated:YES];
    return YES;
}
@end
static GMBrowseSongCell *GMBrowseCell(UITableView *table, NSString *identifier) {
    GMBrowseSongCell *cell = [table dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[GMBrowseSongCell alloc] initWithStyle:3 reuseIdentifier:identifier];
    [cell resetActions];
    cell.browser = (GMBrowseTableController *)table.delegate; cell.shell = cell.browser.shell;
    cell.backgroundColor = [UIColor clearColor]; cell.tintColor = GMCurrentAccent();
    cell.textLabel.textColor = GMPrimaryTextColor();
    cell.textLabel.font = GMAppFont(17,0);
    cell.detailTextLabel.textColor = GMSecondaryTextColor();
    cell.detailTextLabel.font = GMAppFont(13,0);
    cell.selectionStyle = 0; cell.accessoryType = 0;
    return cell;
}
static void GMBrowseConfigureSong(GMBrowseSongCell *cell, GMTrack *track) {
    cell.textLabel.text = track.title ?: @"Untitled Song";
    cell.detailTextLabel.text = track.artist ?: @"Unknown Artist";
    cell.rowImage.hidden = YES; cell.rowCase.hidden = NO;
    [cell.rowCase configureWithIdentifier:GMTrackIdentifier(track) title:track.title artist:track.artist artwork:GMBrowseTrackImage(track)];
    [cell.rowCase applyTheme];
    [cell configureSongIdentifier:GMTrackIdentifier(track) playlistContext:nil];
    cell.usesPlaybackIndicator = YES;
    [cell refreshPlaybackIndicator];
}

@interface GMSongsControlsHeader : UIView
@property(nonatomic, strong) UIButton *playButton;
@property(nonatomic, strong) UIButton *shuffleButton;
- (void)applyTheme;
@end
@implementation GMSongsControlsHeader
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.playButton = [UIButton buttonWithType:1];
    self.shuffleButton = [UIButton buttonWithType:1];
    [self.playButton setTitle:@"  Play" forState:0];
    [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:0];
    [self.shuffleButton setTitle:@"  Shuffle" forState:0];
    [self.shuffleButton setImage:[UIImage systemImageNamed:@"shuffle"] forState:0];
    self.playButton.accessibilityLabel = @"Play all songs";
    self.playButton.accessibilityHint = @"Play your songs in title order";
    self.shuffleButton.accessibilityLabel = @"Shuffle all songs";
    self.shuffleButton.accessibilityHint = @"Play every song in a random order";
    [self addSubview:self.playButton]; [self addSubview:self.shuffleButton];
    [self applyTheme];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat buttonWidth = GMMax(0,(self.bounds.size.width-56)/2);
    self.playButton.frame = CGRectMake(20,8,buttonWidth,48);
    self.shuffleButton.frame = CGRectMake(36+buttonWidth,8,buttonWidth,48);
}
- (void)applyTheme {
    // Equal native glass treatments leave the existing page wash visible.
    GMStyleGlassButton(self.playButton,NO);
    GMStyleGlassButton(self.shuffleButton,NO);
}
@end

@interface GMSongsController ()
@property(nonatomic, copy) NSArray<NSNumber *> *trackIndexes;
@property(nonatomic, strong) GMSongsControlsHeader *controlsHeader;
@end
@implementation GMSongsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Songs";
    self.controlsHeader = [[GMSongsControlsHeader alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,76)];
    [self.controlsHeader.playButton addTarget:self action:@selector(playAllSongs) forControlEvents:(1UL<<6)];
    [self.controlsHeader.shuffleButton addTarget:self action:@selector(shuffleAllSongs) forControlEvents:(1UL<<6)];
    self.table.tableHeaderView = self.controlsHeader;
    [self reloadLibrary];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.controlsHeader.frame.size.width != self.table.bounds.size.width) {
        self.controlsHeader.frame = CGRectMake(0,0,self.table.bounds.size.width,76);
        self.table.tableHeaderView = self.controlsHeader;
    }
}
- (void)reloadLibrary {
    NSArray<GMTrack *> *tracks = self.shell.player.tracks;
    NSMutableArray<NSNumber *> *indexes = [NSMutableArray array];
    for (NSUInteger i=0; i<tracks.count; i++) [indexes addObject:@(i)];
    self.trackIndexes = [indexes sortedArrayUsingComparator:^NSInteger(NSNumber *a, NSNumber *b) {
        GMTrack *left = tracks[a.unsignedIntegerValue], *right = tracks[b.unsignedIntegerValue];
        NSString *leftTitle = left.title.length ? left.title : @"Untitled Song";
        NSString *rightTitle = right.title.length ? right.title : @"Untitled Song";
        NSInteger comparison = [leftTitle localizedCaseInsensitiveCompare:rightTitle];
        if (!comparison) comparison = [(left.artist ?: @"") localizedCaseInsensitiveCompare:(right.artist ?: @"")];
        if (comparison) return comparison;
        return a.unsignedIntegerValue < b.unsignedIntegerValue ? -1 : (a.unsignedIntegerValue > b.unsignedIntegerValue ? 1 : 0);
    }];
    BOOL hasSongs = self.trackIndexes.count > 0;
    self.controlsHeader.playButton.enabled = hasSongs;
    self.controlsHeader.shuffleButton.enabled = hasSongs;
    [self.controlsHeader applyTheme];
    self.table.tableFooterView = GMBrowseMessage(hasSongs ? GMBrowseSongCount(self.trackIndexes.count) : @"Import audio with the + button to add your songs.",76);
    [super reloadLibrary];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.trackIndexes.count;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    GMBrowseSongCell *cell = GMBrowseCell(table,@"LibrarySong");
    if (path.row < 0 || path.row >= (NSInteger)self.trackIndexes.count) return cell;
    NSNumber *index = self.trackIndexes[path.row];
    GMBrowseConfigureSong(cell,GMBrowseTrack(self.shell,index));
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if ([self closeRevealedActionsIfNeeded]) return;
    GMBrowseSongCell *cell = (GMBrowseSongCell *)[table cellForRowAtIndexPath:path];
    CGRect source = [cell.rowCase convertRect:cell.rowCase.bounds toView:self.shell.view.window];
    if ([self.shell.player playTrackIndexes:self.trackIndexes startingAtPosition:path.row]) {
        [table layoutIfNeeded];
        GMBrowseSongCell *sourceCell=(GMBrowseSongCell *)[table cellForRowAtIndexPath:path];
        [self.shell presentNowPlayingFromCaseRect:source artworkView:sourceCell.rowCase];
    }
}
- (void)playAllSongs {
    [self closeRevealedActionsIfNeeded];
    if ([self.shell.player playAllTrackIndexes:self.trackIndexes]) [self.shell presentNowPlaying];
}
- (void)shuffleAllSongs {
    [self closeRevealedActionsIfNeeded];
    if ([self.shell.player shuffleTrackIndexes:self.trackIndexes]) [self.shell presentNowPlaying];
}
@end

@interface GMBrowseCollectionHeader : UIView
@property(nonatomic, strong) UIImageView *cover;
@property(nonatomic, strong) GMCDCaseView *caseView;
@property(nonatomic) BOOL caseOpen;
@property(nonatomic, strong) UILabel *nameLabel;
@property(nonatomic, strong) UILabel *detailLabel;
@property(nonatomic, strong) UIButton *playButton;
- (void)applyTheme;
@end
@implementation GMBrowseCollectionHeader
- (void)toggleCase {
    self.caseOpen = !self.caseOpen;
    [self.caseView setCaseOpen:self.caseOpen animated:YES];
}
- (BOOL)accessibilityToggleCase:(UIAccessibilityCustomAction *)action { [self toggleCase]; return YES; }
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.cover = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.cover.layer.cornerRadius = 12; self.cover.clipsToBounds = YES;
    self.caseView = [[GMCDCaseView alloc] initWithFrame:CGRectZero presentation:GMCDCasePresentationInspector];
    self.caseView.hidden = YES; self.caseView.isAccessibilityElement = YES;
    self.caseView.accessibilityTraits = UIAccessibilityTraitButton;
    self.caseView.accessibilityHint = @"Use the Open or Close Case action";
    self.caseView.accessibilityCustomActions = @[[[UIAccessibilityCustomAction alloc] initWithName:@"Open or Close Case" target:self selector:@selector(accessibilityToggleCase:)]];
    [self.caseView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleCase)]];
    [self addSubview:self.caseView];
    self.nameLabel = GMLabel(@"",24,.6,GMPrimaryTextColor());
    self.nameLabel.adjustsFontSizeToFitWidth = YES; self.nameLabel.minimumScaleFactor = .6;
    self.detailLabel = GMLabel(@"",15,0,GMSecondaryTextColor());
    self.playButton = [UIButton buttonWithType:1];
    [self.playButton setTitle:@"  Play" forState:0];
    [self.playButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:0];
    self.playButton.accessibilityLabel = @"Play all songs in this collection";
    [self addSubview:self.cover]; [self addSubview:self.nameLabel];
    [self addSubview:self.detailLabel]; [self addSubview:self.playButton];
    [self applyTheme];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, cover = GMMin(218,GMMax(130,w-100));
    self.cover.frame = CGRectMake((w-cover)/2,12,cover,cover);
    self.caseView.frame = self.cover.frame;
    self.nameLabel.frame = CGRectMake(20,246,GMMax(0,w-40),31);
    self.detailLabel.frame = CGRectMake(20,281,GMMax(0,w-40),22);
    self.playButton.frame = CGRectMake(20,320,GMMax(0,w-40),48);
}
- (void)applyTheme {
    self.backgroundColor = [UIColor clearColor];
    self.nameLabel.textColor = GMPrimaryTextColor(); self.detailLabel.textColor = GMSecondaryTextColor();
    self.cover.backgroundColor = GMCardColor(); self.cover.tintColor = GMCurrentAccent();
    [self.caseView applyTheme];
    GMStyleGlassButton(self.playButton,YES);
}
@end

@interface GMBrowseSongsController : GMBrowseTableController
@property(nonatomic, copy) NSString *albumIdentifier;
@property(nonatomic, copy) NSString *albumAnchorIdentifier;
@property(nonatomic, copy) NSString *playlistIdentifier;
@property(nonatomic, copy) NSString *artistName;
@property(nonatomic, copy) NSArray<NSNumber *> *trackIndexes;
@property(nonatomic, strong) GMBrowseCollectionHeader *collectionHeader;
@property(nonatomic) BOOL caseOwnerVisible;
- (void)playCollection;
- (void)addSongs;
@end
@interface GMPlaylistSongPicker : GMBrowseTableController
@property(nonatomic, copy) NSString *playlistIdentifier;
@end

@implementation GMBrowseSongsController
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; self.caseOwnerVisible = YES;
    [self.collectionHeader.caseView setActive:YES];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated]; self.caseOwnerVisible = NO;
    [self.collectionHeader.caseView setActive:NO];
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [super scrollViewDidScroll:scrollView];
    [self.collectionHeader.caseView setActive:self.caseOwnerVisible];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = 2;
    self.collectionHeader = [[GMBrowseCollectionHeader alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,392)];
    [self.collectionHeader.playButton addTarget:self action:@selector(playCollection) forControlEvents:(1UL<<6)];
    self.table.tableHeaderView = self.collectionHeader;
    if (self.playlistIdentifier) {
        UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithTitle:@"Add Songs" style:0 target:self action:@selector(addSongs)];
        UIBarButtonItem *edit = [[UIBarButtonItem alloc] initWithTitle:@"Edit" style:0 target:self action:@selector(editPlaylist)];
        self.navigationItem.rightBarButtonItems = @[add,edit];
    }
    [self reloadLibrary];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.collectionHeader.frame.size.width != self.table.bounds.size.width) {
        self.collectionHeader.frame = CGRectMake(0,0,self.table.bounds.size.width,392);
        self.table.tableHeaderView = self.collectionHeader;
    }
}
- (void)reloadLibrary {
    UIImage *artwork = nil;
    NSString *detail = nil;
    if (self.playlistIdentifier) {
        GMPlaylist *playlist = GMBrowsePlaylist(self.shell,self.playlistIdentifier);
        self.title = playlist.name ?: @"Playlist";
        self.trackIndexes = [self.shell.playlistStore trackIndexesForPlaylist:self.playlistIdentifier tracks:self.shell.player.tracks] ?: [NSArray array];
        artwork = playlist.artwork;
        detail = GMBrowseSongCount(self.trackIndexes.count);
    } else if (self.albumIdentifier) {
        GMAlbum *album = GMBrowseAlbum(self.shell,self.albumIdentifier);
        // A late metadata batch can replace an Unknown Album group. Follow
        // its first song into the now-identified album instead of going blank.
        if (!album && self.albumAnchorIdentifier) {
            NSInteger anchor = GMTrackIndexForIdentifier(self.shell.player.tracks,self.albumAnchorIdentifier);
            if (anchor != NSNotFound) for (GMAlbum *candidate in self.shell.albums) {
                if ([candidate.trackIndexes containsObject:@(anchor)]) {
                    album = candidate; self.albumIdentifier = candidate.identifier; break;
                }
            }
        }
        self.title = album.title ?: @"Album"; self.trackIndexes = album.trackIndexes ?: [NSArray array];
        artwork = album.artwork;
        detail = [NSString stringWithFormat:@"%@ · %@",album.artist ?: @"Unknown Artist",GMBrowseSongCount(self.trackIndexes.count)];
    } else {
        NSMutableArray *indexes = [NSMutableArray array];
        for (NSUInteger i=0; i<self.shell.player.tracks.count; i++) {
            GMTrack *track = self.shell.player.tracks[i];
            if (!self.artistName || [(track.artist ?: @"Unknown Artist") localizedCaseInsensitiveCompare:self.artistName] == 0) [indexes addObject:@(i)];
        }
        self.trackIndexes = indexes; self.title = self.artistName ?: @"Songs";
        detail = GMBrowseSongCount(indexes.count);
    }
    if (!artwork) artwork = GMBrowseTrackImage(GMBrowseTrack(self.shell,self.trackIndexes.firstObject));
    self.collectionHeader.cover.hidden = YES;
    self.collectionHeader.caseView.hidden = NO;
    [self.collectionHeader.caseView configureWithIdentifier:self.albumIdentifier ?: self.playlistIdentifier ?: self.artistName ?: @"collection" title:self.title artist:detail artwork:artwork];
    self.collectionHeader.nameLabel.text = self.title;
    self.collectionHeader.detailLabel.text = detail;
    self.collectionHeader.playButton.enabled = self.trackIndexes.count > 0;
    [self.collectionHeader applyTheme];
    self.table.tableFooterView = !self.trackIndexes.count ? GMBrowseMessage(self.playlistIdentifier ? @"Tap Add Songs to choose music from your library." : @"Import music with the + button to add songs.",88) : [[UIView alloc] initWithFrame:CGRectZero];
    [super reloadLibrary];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.trackIndexes.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    GMBrowseSongCell *cell = GMBrowseCell(table,@"CollectionSong");
    if (path.row < 0 || path.row >= (NSInteger)self.trackIndexes.count) return cell;
    NSNumber *index = self.trackIndexes[path.row]; GMTrack *track = GMBrowseTrack(self.shell,index);
    GMBrowseConfigureSong(cell,track);
    if (self.artistName) cell.detailTextLabel.text = track.album ?: @"Unknown Album";
    if (self.playlistIdentifier) [cell configureSongIdentifier:GMTrackIdentifier(track) playlistContext:self.playlistIdentifier];
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if ([self closeRevealedActionsIfNeeded]) return;
    GMBrowseSongCell *cell = (GMBrowseSongCell *)[table cellForRowAtIndexPath:path];
    CGRect source = [cell.rowCase convertRect:cell.rowCase.bounds toView:self.shell.view.window];
    if ([self.shell.player playTrackIndexes:self.trackIndexes startingAtPosition:path.row]) {
        [table layoutIfNeeded];
        GMBrowseSongCell *sourceCell=(GMBrowseSongCell *)[table cellForRowAtIndexPath:path];
        [self.shell presentNowPlayingFromCaseRect:source artworkView:sourceCell.rowCase];
    }
}
- (void)playCollection {
    [self closeRevealedActionsIfNeeded];
    if ([self.shell.player playAllTrackIndexes:self.trackIndexes]) [self.shell presentNowPlaying];
}
- (void)addSongs {
    [self closeRevealedActionsIfNeeded];
    GMPlaylistSongPicker *picker = [GMPlaylistSongPicker new]; picker.shell = self.shell;
    picker.playlistIdentifier = self.playlistIdentifier; picker.additionalSafeAreaInsets = self.additionalSafeAreaInsets;
    [self.navigationController pushViewController:picker animated:YES];
}
- (void)editPlaylist {
    [self closeRevealedActionsIfNeeded];
    [self.shell editPlaylistWithIdentifier:self.playlistIdentifier fromView:self.collectionHeader];
}
@end

@implementation GMPlaylistSongPicker
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Add Songs";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:0 target:self action:@selector(finish)];
    self.table.tableHeaderView = GMBrowseMessage(@"Tap to add songs. Tap a checked song to confirm its removal.",64);
    [self reloadLibrary];
}
- (void)finish { [self.navigationController popViewControllerAnimated:YES]; }
- (void)reloadLibrary {
    self.table.tableHeaderView = GMBrowseMessage(@"Tap to add songs. Tap a checked song to confirm its removal.",64);
    self.table.tableFooterView = !self.shell.player.tracks.count ? GMBrowseMessage(@"Import songs from the Albums or Search tab first.",88) : [[UIView alloc] initWithFrame:CGRectZero];
    [super reloadLibrary];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.shell.player.tracks.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    GMBrowseSongCell *cell = GMBrowseCell(table,@"AddSong");
    if (path.row < 0 || path.row >= (NSInteger)self.shell.player.tracks.count) return cell;
    GMTrack *track = self.shell.player.tracks[path.row]; GMBrowseConfigureSong(cell,track);
    // Checkmarks in this picker denote playlist membership, not playback.
    cell.usesPlaybackIndicator = NO; [cell refreshPlaybackIndicator];
    GMPlaylist *playlist = GMBrowsePlaylist(self.shell,self.playlistIdentifier);
    BOOL contained = [playlist.trackIdentifiers containsObject:GMTrackIdentifier(track)];
    if (contained) [cell configureSongIdentifier:GMTrackIdentifier(track) playlistContext:self.playlistIdentifier];
    cell.accessoryType = contained ? 3 : 0;
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if ([self closeRevealedActionsIfNeeded]) return;
    if (path.row < 0 || path.row >= (NSInteger)self.shell.player.tracks.count) return;
    GMTrack *track = self.shell.player.tracks[path.row];
    GMPlaylist *playlist = GMBrowsePlaylist(self.shell,self.playlistIdentifier);
    if (!playlist) return;
    NSError *error = nil; NSString *identifier = GMTrackIdentifier(track);
    BOOL contained = [playlist.trackIdentifiers containsObject:identifier];
    if (contained) {
        [self.shell confirmRemoveSongIdentifier:identifier fromPlaylist:self.playlistIdentifier];
        return;
    }
    if (![self.shell.playlistStore addTracks:@[track] toPlaylist:self.playlistIdentifier error:&error]) { GMBrowseReportError(self.shell,error); return; }
    [self.shell reloadLibrary]; [self reloadLibrary];
}
@end

static void GMBrowsePushSongs(GMBrowseTableController *source, NSString *albumIdentifier, NSString *playlistIdentifier, NSString *artistName) {
    GMBrowseSongsController *controller = [GMBrowseSongsController new]; controller.shell = source.shell;
    controller.albumIdentifier = albumIdentifier; controller.playlistIdentifier = playlistIdentifier; controller.artistName = artistName;
    if (albumIdentifier) {
        GMAlbum *album = GMBrowseAlbum(source.shell,albumIdentifier);
        controller.albumAnchorIdentifier = GMTrackIdentifier(GMBrowseTrack(source.shell,album.trackIndexes.firstObject));
    }
    controller.additionalSafeAreaInsets = source.additionalSafeAreaInsets;
    [source.navigationController pushViewController:controller animated:YES];
}

@interface GMAlbumTile : UIControl
@property(nonatomic, weak) GMAlbumsController *owner;
@property(nonatomic, copy) NSString *albumIdentifier;
@property(nonatomic, strong) GMCDCaseView *caseView;
@property(nonatomic, strong) UILabel *nameLabel;
@property(nonatomic, strong) UILabel *artistLabel;
- (void)configure:(GMAlbum *)album;
- (void)prepareCaseForReuse;
@end
@implementation GMAlbumTile
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame]; if (!self) return nil;
    self.caseView = [[GMCDCaseView alloc] initWithFrame:CGRectZero presentation:GMCDCasePresentationStatic];
    self.nameLabel = GMLabel(@"",15,0,GMPrimaryTextColor()); self.artistLabel = GMLabel(@"",13,0,GMSecondaryTextColor());
    self.caseView.userInteractionEnabled = NO; self.nameLabel.userInteractionEnabled = NO; self.artistLabel.userInteractionEnabled = NO;
    [self addSubview:self.caseView]; [self addSubview:self.nameLabel]; [self addSubview:self.artistLabel];
    self.isAccessibilityElement = YES; self.accessibilityHint = @"Open album. Use Inspect Album in actions to turn its media case.";
    self.accessibilityCustomActions = @[[[UIAccessibilityCustomAction alloc] initWithName:@"Inspect Album" target:self selector:@selector(accessibilityInspectAlbum:)]];
    [self addTarget:self action:@selector(openAlbum) forControlEvents:(1UL<<6)];
    return self;
}
- (void)configure:(GMAlbum *)album {
    self.albumIdentifier = album.identifier; self.nameLabel.text = album.title; self.artistLabel.text = album.artist;
    self.nameLabel.textColor = GMPrimaryTextColor(); self.artistLabel.textColor = GMSecondaryTextColor();
    [self.caseView configureWithIdentifier:album.identifier title:album.title artist:album.artist artwork:album.artwork];
    [self.caseView setPlaying:YES]; [self.caseView setCaseOpen:NO animated:NO]; [self.caseView applyTheme];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@, %@",album.title,album.artist,GMBrowseSongCount(album.trackIndexes.count)];
}
- (void)prepareCaseForReuse {
    [self.caseView prepareForReuse]; self.albumIdentifier = nil; self.owner = nil;
}
- (void)layoutSubviews {
    [super layoutSubviews]; CGFloat w = self.bounds.size.width;
    self.caseView.frame = CGRectMake(0,0,w,w); self.nameLabel.frame = CGRectMake(2,w+3,w-4,20); self.artistLabel.frame = CGRectMake(2,w+24,w-4,18);
}
- (void)openAlbum {
    if (!self.albumIdentifier.length || !self.owner.view.window || self.owner.presentedViewController) return;
    [self.owner resetScrollEntryAnimations]; GMBrowsePushSongs(self.owner,self.albumIdentifier,nil,nil);
}
- (BOOL)accessibilityInspectAlbum:(UIAccessibilityCustomAction *)action {
    (void)action; if (!self.albumIdentifier.length) return NO;
    [self.owner inspectAlbumWithIdentifier:self.albumIdentifier]; return YES;
}
@end
@interface GMAlbumGridCell : UITableViewCell
@property(nonatomic, strong) GMScrollAnimationView *scrollAnimationView;
@property(nonatomic, strong) GMAlbumTile *leftTile;
@property(nonatomic, strong) GMAlbumTile *rightTile;
@property(nonatomic, copy) NSIndexPath *displayedIndexPath;
- (void)setCDCasesActive:(BOOL)active;
@end
@implementation GMAlbumGridCell
- (id)initWithStyle:(NSInteger)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier]; if (!self) return nil;
    self.selectionStyle = 0; self.clipsToBounds = YES;
    self.scrollAnimationView = [[GMScrollAnimationView alloc] initWithFrame:self.contentView.bounds];
    [self.contentView addSubview:self.scrollAnimationView];
    self.leftTile = [[GMAlbumTile alloc] initWithFrame:CGRectZero]; self.rightTile = [[GMAlbumTile alloc] initWithFrame:CGRectZero];
    [self.scrollAnimationView.contentView addSubview:self.leftTile];
    [self.scrollAnimationView.contentView addSubview:self.rightTile];
    return self;
}
- (void)prepareForReuse {
    [super prepareForReuse]; [self.scrollAnimationView resetScrollAnimation];
    [self.leftTile prepareCaseForReuse]; [self.rightTile prepareCaseForReuse]; self.displayedIndexPath = nil;
}
- (void)setCDCasesActive:(BOOL)active {
    [self.leftTile.caseView setActive:active && !self.leftTile.hidden && self.leftTile.albumIdentifier.length > 0];
    [self.rightTile.caseView setActive:active && !self.rightTile.hidden && self.rightTile.albumIdentifier.length > 0];
}
- (void)didMoveToWindow { [super didMoveToWindow]; if (!self.window) [self setCDCasesActive:NO]; }
- (void)layoutSubviews {
    [super layoutSubviews]; CGFloat w = GMMax(0,(self.contentView.bounds.size.width-32)/2);
    self.scrollAnimationView.frame = self.contentView.bounds;
    self.leftTile.frame = CGRectMake(12,0,w,w+45); self.rightTile.frame = CGRectMake(20+w,0,w,w+45);
}
@end

@interface GMAlbumsController () <UIGestureRecognizerDelegate>
@property(nonatomic) BOOL casesOwnerVisible;
@property(nonatomic, strong) UILongPressGestureRecognizer *inspectionPress;
@property(nonatomic, weak) UIWindow *inspectionWindow;
@property(nonatomic, copy) NSString *heldAlbumIdentifier;
@property(nonatomic) CGPoint heldStartPoint;
@property(nonatomic) CGSize heldWindowSize;
@property(nonatomic) BOOL forwardingHeldInspection;
@property(nonatomic, weak) GMCDAlbumInspector *heldInspector;
- (void)updateCDCaseVisibility;
- (void)installInspectionGesture;
- (void)removeInspectionGesture;
- (GMCDAlbumInspector *)presentInspectorForAlbumIdentifier:(NSString *)identifier held:(BOOL)held;
@end
@implementation GMAlbumsController
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"Albums"; self.table.separatorStyle = 0; [self reloadLibrary]; }
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; self.casesOwnerVisible = YES;
    [self updateCDCaseVisibility]; [self installInspectionGesture];
}
- (void)viewWillDisappear:(BOOL)animated {
    self.casesOwnerVisible = NO; [self updateCDCaseVisibility];
    // A window-level recognizer can finish the original hold even after a
    // full-screen presentation removes the grid's view from the hierarchy.
    if (!self.forwardingHeldInspection) [self removeInspectionGesture];
    [super viewWillDisappear:animated];
}
- (void)dealloc {
    if (self.inspectionPress) [self.inspectionWindow removeGestureRecognizer:self.inspectionPress];
}
- (void)reloadLibrary {
    for (UITableViewCell *cell in self.table.visibleCells)
        if ([cell isKindOfClass:[GMAlbumGridCell class]]) [(GMAlbumGridCell *)cell setCDCasesActive:NO];
    self.table.tableFooterView = GMBrowseMessage(self.shell.albums.count ? [NSString stringWithFormat:@"%lu albums · %@",(unsigned long)self.shell.albums.count,GMBrowseSongCount(self.shell.player.tracks.count)] : @"Import audio with the + button. Embedded album information organizes your library.",76);
    [super reloadLibrary]; [self updateCDCaseVisibility];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 1; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return ((NSInteger)self.shell.albums.count+1)/2; }
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path { return GMMax(0,(table.bounds.size.width-32)/2)+54; }
- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section { return .01; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    GMAlbumGridCell *cell = [table dequeueReusableCellWithIdentifier:@"AlbumPair"];
    if (!cell) cell = [[GMAlbumGridCell alloc] initWithStyle:0 reuseIdentifier:@"AlbumPair"];
    [cell.scrollAnimationView resetScrollAnimation];
    cell.displayedIndexPath = path;
    cell.backgroundColor = [UIColor clearColor]; cell.leftTile.owner = self; cell.rightTile.owner = self;
    NSInteger left = path.row*2, right = left+1;
    cell.leftTile.hidden = left >= (NSInteger)self.shell.albums.count; cell.rightTile.hidden = right >= (NSInteger)self.shell.albums.count;
    if (!cell.leftTile.hidden) [cell.leftTile configure:self.shell.albums[left]];
    if (!cell.rightTile.hidden) [cell.rightTile configure:self.shell.albums[right]];
    if (cell.leftTile.hidden) [cell.leftTile.caseView setActive:NO];
    if (cell.rightTile.hidden) [cell.rightTile.caseView setActive:NO];
    return cell;
}
- (void)tableView:(UITableView *)table willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)path {
    [super tableView:table willDisplayCell:cell forRowAtIndexPath:path];
    if ([cell isKindOfClass:[GMAlbumGridCell class]])
        [(GMAlbumGridCell *)cell setCDCasesActive:self.casesOwnerVisible && GMBrowseEntryVisible(table,cell)];
}
- (void)tableView:(UITableView *)table didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)path {
    [super tableView:table didEndDisplayingCell:cell forRowAtIndexPath:path];
    if ([cell isKindOfClass:[GMAlbumGridCell class]] && [((GMAlbumGridCell *)cell).displayedIndexPath isEqual:path])
        [(GMAlbumGridCell *)cell setCDCasesActive:NO];
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [super scrollViewDidScroll:scrollView];
    if (scrollView == self.table) [self updateCDCaseVisibility];
}
- (void)updateCDCaseVisibility {
    for (UITableViewCell *cell in self.table.visibleCells)
        if ([cell isKindOfClass:[GMAlbumGridCell class]])
            [(GMAlbumGridCell *)cell setCDCasesActive:self.casesOwnerVisible && GMBrowseEntryVisible(self.table,cell)];
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
}
- (void)installInspectionGesture {
    UIWindow *window = self.view.window;
    if (!self.casesOwnerVisible || !window || self.inspectionWindow == window) return;
    [self removeInspectionGesture];
    if (!self.inspectionPress) {
        self.inspectionPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleInspectionPress:)];
        self.inspectionPress.minimumPressDuration = .38; self.inspectionPress.allowableMovement = 12;
        self.inspectionPress.numberOfTouchesRequired = 1; self.inspectionPress.cancelsTouchesInView = YES;
        self.inspectionPress.delegate = self;
    }
    self.inspectionWindow = window; [window addGestureRecognizer:self.inspectionPress];
}
- (void)removeInspectionGesture {
    UIWindow *window = self.inspectionWindow; self.inspectionWindow = nil;
    if (self.inspectionPress) [window removeGestureRecognizer:self.inspectionPress];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (gesture != self.inspectionPress || !self.casesOwnerVisible || self.presentedViewController) return NO;
    self.heldAlbumIdentifier = nil;
    for (UIView *view = touch.view; view && view != self.table; view = view.superview) {
        if ([view isKindOfClass:[GMAlbumTile class]]) {
            GMAlbumTile *tile = (GMAlbumTile *)view;
            if (tile.owner != self || tile.hidden || !tile.albumIdentifier.length) return NO;
            self.heldAlbumIdentifier = [tile.albumIdentifier copy]; return YES;
        }
    }
    return NO;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    return gesture != self.inspectionPress || (self.casesOwnerVisible && !self.table.isDragging &&
        !self.presentedViewController && GMBrowseAlbum(self.shell,self.heldAlbumIdentifier) != nil);
}
- (void)handleInspectionPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.heldStartPoint = [gesture locationInView:self.inspectionWindow];
        self.heldWindowSize = self.inspectionWindow.bounds.size;
        self.forwardingHeldInspection = YES;
        self.heldInspector = [self presentInspectorForAlbumIdentifier:self.heldAlbumIdentifier held:YES];
        if (!self.heldInspector) self.forwardingHeldInspection = NO;
    } else if (gesture.state == UIGestureRecognizerStateChanged && self.forwardingHeldInspection) {
        CGPoint point = [gesture locationInView:self.inspectionWindow];
        CGSize size = self.inspectionWindow.bounds.size;
        if (size.width != self.heldWindowSize.width || size.height != self.heldWindowSize.height) {
            self.heldStartPoint = point; self.heldWindowSize = size;
        }
        [self.heldInspector updateHeldInspectionTranslation:CGPointMake(point.x-self.heldStartPoint.x,point.y-self.heldStartPoint.y)];
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        [self.heldInspector finishHeldInspection]; self.heldInspector = nil;
        self.forwardingHeldInspection = NO; self.heldAlbumIdentifier = nil;
        if (!self.casesOwnerVisible) [self removeInspectionGesture];
    }
}
- (GMCDAlbumInspector *)presentInspectorForAlbumIdentifier:(NSString *)identifier held:(BOOL)held {
    if (!self.casesOwnerVisible || !self.view.window || self.presentedViewController || self.shell.presentedViewController ||
        !GMBrowseAlbum(self.shell,identifier)) return nil;
    [self resetScrollEntryAnimations]; [self closeRevealedActionsIfNeeded];
    GMCDAlbumInspector *inspector = [[GMCDAlbumInspector alloc] initWithShell:self.shell albumIdentifier:identifier];
    if (held) [inspector beginHeldInspection];
    // The shell is the actual full-screen presenter, so library refreshes
    // reach the inspector through its existing presented-controller walk.
    [self.shell presentViewController:inspector animated:YES completion:nil];
    return inspector;
}
- (void)inspectAlbumWithIdentifier:(NSString *)identifier {
    [self presentInspectorForAlbumIdentifier:identifier held:NO];
}
@end

@implementation GMPlaylistsController
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"Playlists"; [self reloadLibrary]; }
- (void)reloadLibrary {
    NSString *message = self.shell.playlistStore.playlists.count ? @"Playlists are saved on this device." : @"Create a playlist, then add songs from your imported music.";
    if (self.shell.playlistStore.lastError) message = self.shell.playlistStore.lastError.localizedDescription;
    self.table.tableFooterView = GMBrowseMessage(message,88);
    [super reloadLibrary];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 2; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return section == 0 ? 1 : (NSInteger)self.shell.playlistStore.playlists.count; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section { return section == 1 && self.shell.playlistStore.playlists.count ? @"Your Playlists" : nil; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    GMBrowseSongCell *cell = GMBrowseCell(table,path.section == 0 ? @"CreatePlaylist" : @"Playlist");
    if (path.section == 0) {
        cell.textLabel.text = @"New Playlist"; cell.textLabel.textColor = GMCurrentAccent();
        cell.detailTextLabel.text = @"Choose a name and add songs";
        GMBrowseSetArtwork(cell.imageView,nil,@"plus"); cell.imageView.tintColor = GMCurrentAccent();
        return cell;
    }
    if (path.row < 0 || path.row >= (NSInteger)self.shell.playlistStore.playlists.count) return cell;
    GMPlaylist *playlist = self.shell.playlistStore.playlists[path.row];
    NSArray<NSNumber *> *indexes = [self.shell.playlistStore trackIndexesForPlaylist:playlist.identifier tracks:self.shell.player.tracks];
    cell.textLabel.text = playlist.name; cell.detailTextLabel.text = GMBrowseSongCount(indexes.count);
    cell.rowImage.hidden=YES;cell.rowCase.hidden=NO;
    [cell.rowCase configureWithIdentifier:playlist.identifier title:playlist.name artist:nil artwork:playlist.artwork ?: GMBrowseTrackImage(GMBrowseTrack(self.shell,indexes.firstObject))];
    [cell configurePlaylistIdentifier:playlist.identifier];
    cell.accessoryType = 1; return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if ([self closeRevealedActionsIfNeeded]) return;
    if (path.section == 0) { [self createPlaylist]; return; }
    if (path.row >= 0 && path.row < (NSInteger)self.shell.playlistStore.playlists.count)
        GMBrowsePushSongs(self,nil,self.shell.playlistStore.playlists[path.row].identifier,nil);
}
- (void)createPlaylist {
    __weak GMPlaylistsController *weakSelf = self;
    GMBrowsePromptName(self,@"New Playlist",nil,@"Create",^(NSString *name) {
        GMPlaylistsController *controller = weakSelf; if (!controller) return;
        NSError *error = nil; GMPlaylist *playlist = [controller.shell.playlistStore createPlaylistWithName:name error:&error];
        if (!playlist) { GMBrowseReportError(controller.shell,error); return; }
        [controller.shell reloadLibrary]; [controller reloadLibrary];
        GMBrowsePushSongs(controller,nil,playlist.identifier,nil);
    });
}
@end

@interface GMSearchController ()
@property(nonatomic, strong) UISearchController *searchController;
@property(nonatomic, copy) NSArray<NSNumber *> *songMatches;
@property(nonatomic, copy) NSArray<GMAlbum *> *albumMatches;
@property(nonatomic, copy) NSArray<NSString *> *artistMatches;
@property(nonatomic, copy) void (^afterSearchDismissal)(void);
@property(nonatomic) BOOL dismissingSearch;
@end
@implementation GMSearchController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Search";
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.delegate = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Songs, artists, and albums";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    [self reloadLibrary];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)controller { [self reloadLibrary]; }
- (void)performAfterDismissingSearch:(void (^)(void))action {
    // Preserve a choice already in flight instead of replacing its pending
    // navigation or stacking a new sheet during the dismissal animation.
    if (!action || self.afterSearchDismissal) return;
    if (self.searchController.active || self.dismissingSearch) {
        self.afterSearchDismissal = action;
        if (self.searchController.active) {
            self.dismissingSearch = YES;
            self.searchController.active = NO;
        }
    } else action();
}
- (void)finishSearchThen:(void (^)(void))action { [self performAfterDismissingSearch:action]; }
- (void)willDismissSearchController:(UISearchController *)controller { self.dismissingSearch = YES; }
- (void)didDismissSearchController:(UISearchController *)controller {
    void (^action)(void) = self.afterSearchDismissal;
    self.afterSearchDismissal = nil;
    self.dismissingSearch = NO;
    if (action) action();
}
- (void)reloadLibrary {
    NSString *query = [self.searchController.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    NSMutableArray *songs = [NSMutableArray array], *albums = [NSMutableArray array], *artists = [NSMutableArray array], *seenArtists = [NSMutableArray array];
    for (NSUInteger i=0; i<self.shell.player.tracks.count; i++) {
        GMTrack *track = self.shell.player.tracks[i];
        NSString *artist = track.artist.length ? track.artist : @"Unknown Artist";
        if (GMBrowseMatches(track.title,query) || GMBrowseMatches(artist,query) || GMBrowseMatches(track.album,query)) [songs addObject:@(i)];
        if (GMBrowseMatches(artist,query) && ![seenArtists containsObject:artist.lowercaseString]) {
            [artists addObject:artist]; [seenArtists addObject:artist.lowercaseString];
        }
    }
    for (GMAlbum *album in self.shell.albums)
        if (GMBrowseMatches(album.title,query) || GMBrowseMatches(album.artist,query)) [albums addObject:album];
    self.songMatches = songs; self.albumMatches = albums;
    self.artistMatches = [artists sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    self.table.tableFooterView = !songs.count && !albums.count && !artists.count ? GMBrowseMessage(query.length ? @"No results in your library. Try a different song, album, or artist." : @"Import audio with the + button to start your library.",100) : [[UIView alloc] initWithFrame:CGRectZero];
    [super reloadLibrary];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 3; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)(section == 0 ? self.songMatches.count : section == 1 ? self.albumMatches.count : self.artistMatches.count);
}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    if (![self tableView:table numberOfRowsInSection:section]) return nil;
    return section == 0 ? @"Songs" : section == 1 ? @"Albums" : @"Artists";
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    GMBrowseSongCell *cell = GMBrowseCell(table,@"SearchResult");
    if (path.section == 0 && path.row >= 0 && path.row < (NSInteger)self.songMatches.count) {
        NSNumber *index = self.songMatches[path.row];
        GMBrowseConfigureSong(cell,GMBrowseTrack(self.shell,index));
    } else if (path.section == 1 && path.row >= 0 && path.row < (NSInteger)self.albumMatches.count) {
        GMAlbum *album = self.albumMatches[path.row];
        cell.textLabel.text = album.title; cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@",album.artist,GMBrowseSongCount(album.trackIndexes.count)];
        cell.rowImage.hidden=YES;cell.rowCase.hidden=NO;
        [cell.rowCase configureWithIdentifier:album.identifier title:album.title artist:album.artist artwork:album.artwork];cell.accessoryType=1;
    } else if (path.section == 2 && path.row >= 0 && path.row < (NSInteger)self.artistMatches.count) {
        NSString *artist = self.artistMatches[path.row]; NSUInteger count = 0;
        UIImage *artwork=nil;
        for (GMTrack *track in self.shell.player.tracks) if ([(track.artist ?: @"Unknown Artist") localizedCaseInsensitiveCompare:artist] == 0) {count++;if(!artwork)artwork=track.artwork;}
        cell.textLabel.text = artist; cell.detailTextLabel.text = GMBrowseSongCount(count);
        cell.rowImage.hidden=YES;cell.rowCase.hidden=NO;
        [cell.rowCase configureWithIdentifier:artist title:artist artist:nil artwork:artwork];cell.accessoryType=1;
    }
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if ([self closeRevealedActionsIfNeeded]) return;
    if (self.afterSearchDismissal || self.dismissingSearch) return;
    __weak GMSearchController *weakSelf = self;
    if (path.section == 0 && path.row >= 0 && path.row < (NSInteger)self.songMatches.count) {
        // Keep the filtered results available while music starts. Only the
        // keyboard closes; album/artist navigation still uses the handoff.
        if ([self.shell.player playTrackIndexes:self.songMatches startingAtPosition:path.row])
            [self.searchController.searchBar resignFirstResponder];
    } else if (path.section == 1 && path.row >= 0 && path.row < (NSInteger)self.albumMatches.count) {
        NSString *identifier = self.albumMatches[path.row].identifier;
        [self finishSearchThen:^{ if (weakSelf) GMBrowsePushSongs(weakSelf,identifier,nil,nil); }];
    } else if (path.section == 2 && path.row >= 0 && path.row < (NSInteger)self.artistMatches.count) {
        NSString *artist = self.artistMatches[path.row];
        [self finishSearchThen:^{ if (weakSelf) GMBrowsePushSongs(weakSelf,nil,nil,artist); }];
    }
}
@end
