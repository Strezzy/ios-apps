// Music's local settings/UI for its Cask 3 animation adaptation.
// Preset metadata and effects are provided by MusicScrollAnimations.m; this
// module never changes UIKit's scrolling behavior or native glass ancestors.
#import "MusicScrollSettings.h"
#import "MusicScrollAnimations.h"

NSString *const GMScrollSettingsDidChangeNotification = @"com.billy.glassmusic.scrollSettingsDidChange";
static const NSUInteger GMScrollSettingsMaximumBytes = 16 * 1024;

static NSError *GMScrollSettingsError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:@"com.billy.glassmusic.scrollSettings" code:code
                          userInfo:@{NSLocalizedDescriptionKey:description}];
}
static NSData *GMScrollReadBounded(NSURL *url, NSUInteger limit, NSError **error) {
    if (error) *error = nil;
    NSError *issue = nil;
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:&issue];
    if (!handle) { if (error) *error = issue ?: GMScrollSettingsError(1,@"The saved file couldn't be opened."); return nil; }
    NSMutableData *data = [NSMutableData new];
    while (data.length <= limit) {
        NSUInteger remaining = limit + 1 - data.length;
        NSData *chunk = [handle readDataUpToLength:remaining < 4096 ? remaining : 4096 error:&issue];
        if (!chunk) { issue = issue ?: GMScrollSettingsError(2,@"The saved file couldn't be read completely."); break; }
        if (issue || !chunk.length) break;
        [data appendData:chunk];
    }
    NSError *closeError = nil;
    [handle closeAndReturnError:&closeError];
    if (!issue) issue = closeError;
    if (!issue && (!data.length || data.length > limit))
        issue = GMScrollSettingsError(3,@"The saved file is empty or too large. It hasn't been changed.");
    if (issue) { if (error) *error = issue; return nil; }
    return data;
}
static BOOL GMScrollValidPreset(id identifier) {
    return [identifier isKindOfClass:[NSString class]] && [identifier length] <= 32 &&
        [GMScrollPresetIdentifiers() containsObject:identifier];
}

@interface GMScrollSettings ()
@property(nonatomic, readwrite) BOOL enabled;
@property(nonatomic, readwrite, copy) NSString *presetIdentifier;
@property(nonatomic, readwrite, strong) NSError *lastError;
@property(nonatomic, copy) NSURL *fileURL;
@property(nonatomic) BOOL loadedSuccessfully;
- (instancetype)initWithFileURL:(NSURL *)fileURL;
- (BOOL)reloadWithError:(NSError **)error;
- (BOOL)fail:(NSError *)issue error:(NSError **)error;
- (BOOL)commitEnabled:(BOOL)enabled presetIdentifier:(NSString *)identifier error:(NSError **)error;
@end

@implementation GMScrollSettings
+ (instancetype)sharedSettings {
    static GMScrollSettings *settings;
    if (!settings) {
        NSURL *documents = [[[NSFileManager defaultManager] URLsForDirectory:9 inDomains:1] firstObject];
        settings = [[GMScrollSettings alloc] initWithFileURL:[documents URLByAppendingPathComponent:@"MusicScrollSettings.plist"]];
    }
    return settings;
}
- (instancetype)initWithFileURL:(NSURL *)fileURL {
    self = [super init];
    if (self) {
        self.fileURL = fileURL; self.enabled = NO; self.presetIdentifier = @"fade";
        [self reloadWithError:NULL];
    }
    return self;
}
- (BOOL)fail:(NSError *)issue error:(NSError **)error {
    self.lastError = issue ?: GMScrollSettingsError(4,@"Your scrolling preferences couldn't be saved.");
    if (error) *error = self.lastError;
    return NO;
}
- (BOOL)reloadWithError:(NSError **)error {
    if (error) *error = nil;
    self.loadedSuccessfully = NO;
    if (!self.fileURL.isFileURL || !self.fileURL.path.length)
        return [self fail:GMScrollSettingsError(5,@"Scrolling preference storage is unavailable.") error:error];
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.fileURL.path]) {
        self.enabled = NO; self.presetIdentifier = @"fade";
        self.loadedSuccessfully = YES; self.lastError = nil; return YES;
    }
    NSError *issue = nil;
    NSData *data = GMScrollReadBounded(self.fileURL,GMScrollSettingsMaximumBytes,&issue);
    if (!data) return [self fail:issue error:error];
    id document = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&issue];
    if (![document isKindOfClass:[NSDictionary class]] || [document count] != 3)
        return [self fail:issue ?: GMScrollSettingsError(6,@"Saved scrolling preferences are invalid. The original file hasn't been changed.") error:error];
    id version = document[@"formatVersion"], enabled = document[@"enabled"], identifier = document[@"presetIdentifier"];
    if (![version isKindOfClass:[NSNumber class]] || [version doubleValue] != 1 ||
        ![enabled isKindOfClass:[NSNumber class]] || ([enabled doubleValue] != 0 && [enabled doubleValue] != 1) ||
        !GMScrollValidPreset(identifier))
        return [self fail:GMScrollSettingsError(7,@"Saved scrolling preferences aren't supported. The original file hasn't been changed.") error:error];
    self.enabled = [enabled doubleValue] != 0; self.presetIdentifier = identifier;
    self.loadedSuccessfully = YES; self.lastError = nil;
    return YES;
}
- (BOOL)commitEnabled:(BOOL)enabled presetIdentifier:(NSString *)identifier error:(NSError **)error {
    if (error) *error = nil;
    if (!self.loadedSuccessfully)
        return [self fail:self.lastError ?: GMScrollSettingsError(8,@"Saved scrolling preferences couldn't be read. They haven't been changed.") error:error];
    if (!GMScrollValidPreset(identifier))
        return [self fail:GMScrollSettingsError(9,@"Choose one of Music's available animation styles.") error:error];
    if (self.enabled == enabled && [self.presetIdentifier isEqualToString:identifier]) { self.lastError = nil; return YES; }
    NSError *issue = nil;
    NSDictionary *document = @{@"formatVersion":@1,@"enabled":@(enabled),@"presetIdentifier":identifier};
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:document format:200 options:0 error:&issue];
    if (!data || data.length > GMScrollSettingsMaximumBytes)
        return [self fail:issue ?: GMScrollSettingsError(10,@"The scrolling preference file couldn't be created.") error:error];
    if (![[NSFileManager defaultManager] createDirectoryAtURL:self.fileURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&issue] ||
        ![data writeToURL:self.fileURL options:1 error:&issue]) return [self fail:issue error:error];
    // Publish only after NSDataWritingAtomic succeeds. A failed save preserves
    // both the previous live settings and every existing preference file.
    self.enabled = enabled; self.presetIdentifier = identifier; self.lastError = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:GMScrollSettingsDidChangeNotification object:self userInfo:nil];
    return YES;
}
- (BOOL)setAnimationsEnabled:(BOOL)enabled error:(NSError **)error {
    return [self commitEnabled:enabled presetIdentifier:self.presetIdentifier error:error];
}
- (BOOL)selectPresetIdentifier:(NSString *)identifier error:(NSError **)error {
    return [self commitEnabled:self.enabled presetIdentifier:identifier error:error];
}
@end

static void GMScrollShowError(UIViewController *presenter, NSError *issue) {
    if (!presenter.view.window || presenter.isBeingDismissed || presenter.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn't Save Scrolling" message:issue.localizedDescription ?: @"Please try again." preferredStyle:1];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:0 handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

@class GMScrollPresetMenuButton;
@interface GMScrollStyleCell ()
@property(nonatomic, strong) UILabel *heading;
@property(nonatomic, strong) GMScrollPresetMenuButton *styleButton;
@property(nonatomic, strong) UIButton *replayButton;
@property(nonatomic, strong) UIView *previewClip;
@property(nonatomic, strong) GMScrollAnimationView *previewHost;
@property(nonatomic, strong) UIImageView *sampleArtwork;
@property(nonatomic, strong) UILabel *sampleTitle;
@property(nonatomic, strong) UILabel *sampleDetail;
- (void)replay;
- (void)showCredits;
- (void)settingsChanged:(NSNotification *)notification;
@end

// Use the same public native-menu lifecycle as the approved import button.
// Every menu generation owns its deferred result, including save errors, so
// table reuse or a later menu cannot execute an old action on a new screen.
@interface GMScrollPresetMenuButton : UIButton
@property(nonatomic, weak) GMScrollStyleCell *ownerCell;
@property(nonatomic) BOOL menuVisible;
@property(nonatomic) NSUInteger menuGeneration;
@property(nonatomic) BOOL pendingPreview;
@property(nonatomic) BOOL pendingCredits;
@property(nonatomic, strong) NSError *pendingError;
- (void)configureMenu;
- (void)resetPendingActions;
- (void)finishPendingActions;
@end
@implementation GMScrollPresetMenuButton
- (void)configureMenu {
    NSUInteger generation = self.menuGeneration;
    __weak GMScrollPresetMenuButton *weakSelf = self;
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
    GMScrollSettings *settings = [GMScrollSettings sharedSettings];
    for (NSString *identifier in GMScrollPresetIdentifiers()) {
        UIAction *action = [UIAction actionWithTitle:GMScrollPresetName(identifier) image:nil identifier:identifier handler:^(UIAction *selectedAction) {
            (void)selectedAction;
            GMScrollPresetMenuButton *button = weakSelf;
            if (!button || generation != button.menuGeneration || !button.window) return;
            NSError *issue = nil;
            button.pendingPreview = [[GMScrollSettings sharedSettings] selectPresetIdentifier:identifier error:&issue];
            button.pendingError = issue; button.pendingCredits = NO;
            [button.ownerCell refreshStyle];
            if (!button.menuVisible) [button finishPendingActions];
        }];
        action.state = [settings.presetIdentifier isEqualToString:identifier] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [items addObject:action];
    }
    UIAction *credits = [UIAction actionWithTitle:@"Credits" image:[UIImage systemImageNamed:@"info.circle"] identifier:nil handler:^(UIAction *action) {
        (void)action;
        GMScrollPresetMenuButton *button = weakSelf;
        if (!button || generation != button.menuGeneration || !button.window) return;
        button.pendingCredits = YES; button.pendingPreview = NO; button.pendingError = nil;
        if (!button.menuVisible) [button finishPendingActions];
    }];
    [items addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[credits]]];
    self.menu = [UIMenu menuWithTitle:@"Animation Style" children:items];
}
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location {
    self.menuGeneration++; self.pendingPreview = NO; self.pendingCredits = NO; self.pendingError = nil;
    [self configureMenu];
    return [super contextMenuInteraction:interaction configurationForMenuAtLocation:location];
}
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willDisplayMenuForConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionAnimating>)animator {
    self.menuVisible = YES;
    [super contextMenuInteraction:interaction willDisplayMenuForConfiguration:configuration animator:animator];
}
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willEndForConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionAnimating>)animator {
    [super contextMenuInteraction:interaction willEndForConfiguration:configuration animator:animator];
    NSUInteger generation = self.menuGeneration;
    __weak GMScrollPresetMenuButton *weakSelf = self;
    void (^completion)(void) = ^{
        GMScrollPresetMenuButton *button = weakSelf;
        if (!button || button.menuGeneration != generation) return;
        button.menuVisible = NO; [button finishPendingActions];
    };
    if (animator) [animator addCompletion:completion];
    else dispatch_async(dispatch_get_main_queue(),completion);
}
- (void)resetPendingActions {
    self.menuGeneration++; self.menuVisible = NO;
    self.pendingPreview = NO; self.pendingCredits = NO; self.pendingError = nil;
}
- (void)finishPendingActions {
    GMScrollStyleCell *cell = self.ownerCell;
    NSError *issue = self.pendingError;
    BOOL preview = self.pendingPreview, credits = self.pendingCredits;
    self.pendingPreview = NO; self.pendingCredits = NO; self.pendingError = nil;
    if (!cell.window || !cell.presenter.view.window) return;
    if (issue) GMScrollShowError(cell.presenter,issue);
    else if (credits) [cell showCredits];
    else if (preview) [cell replay];
}
@end

@implementation GMScrollStyleCell
- (instancetype)initWithStyle:(NSInteger)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (!self) return nil;
    self.selectionStyle = 0;
    self.heading = GMLabel(@"Animation Style",17,.5,GMPrimaryTextColor());
    self.styleButton = [[GMScrollPresetMenuButton alloc] initWithFrame:CGRectZero];
    self.styleButton.ownerCell = self; self.styleButton.showsMenuAsPrimaryAction = YES;
    [self.styleButton setImage:[UIImage systemImageNamed:@"chevron.up.chevron.down"] forState:0];
    self.styleButton.accessibilityLabel = @"Animation Style";
    self.styleButton.accessibilityHint = @"Choose a scrolling style or read its credits.";
    self.replayButton = [UIButton buttonWithType:1];
    [self.replayButton setImage:[UIImage systemImageNamed:@"arrow.clockwise"] forState:0];
    self.replayButton.accessibilityLabel = @"Replay animation preview";
    [self.replayButton addTarget:self action:@selector(replay) forControlEvents:(1UL<<6)];
    self.previewClip = [[UIView alloc] initWithFrame:CGRectZero]; self.previewClip.clipsToBounds = YES;
    self.previewHost = [[GMScrollAnimationView alloc] initWithFrame:CGRectZero];
    [self.previewClip addSubview:self.previewHost];
    self.sampleArtwork = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"music.note"]];
    self.sampleArtwork.contentMode = 1;
    self.sampleTitle = GMLabel(@"Your Music",16,.5,GMPrimaryTextColor());
    self.sampleDetail = GMLabel(@"",12,0,GMSecondaryTextColor());
    for (UIView *view in @[self.sampleArtwork,self.sampleTitle,self.sampleDetail]) [self.previewHost.contentView addSubview:view];
    self.previewHost.accessibilityLabel = @"Scrolling animation preview";
    for (UIView *view in @[self.heading,self.styleButton,self.replayButton,self.previewClip]) [self.contentView addSubview:view];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingsChanged:) name:GMScrollSettingsDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingsChanged:) name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
    [self.styleButton configureMenu]; [self refreshStyle]; [self applyTheme];
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)prepareForReuse {
    [super prepareForReuse]; [self.previewHost resetScrollAnimation];
    [self.styleButton resetPendingActions]; self.presenter = nil;
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) { [self.previewHost resetScrollAnimation]; [self.styleButton resetPendingActions]; }
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    self.heading.frame = CGRectMake(16,10,GMMax(0,width-32),24);
    self.styleButton.frame = CGRectMake(16,43,GMMax(0,width-94),44);
    self.replayButton.frame = CGRectMake(GMMax(16,width-62),43,46,44);
    self.previewClip.frame = CGRectMake(16,98,GMMax(0,width-32),56);
    self.previewHost.frame = self.previewClip.bounds;
    self.sampleArtwork.frame = CGRectMake(2,10,32,32);
    self.sampleTitle.frame = CGRectMake(46,7,GMMax(0,width-82),22);
    self.sampleDetail.frame = CGRectMake(46,31,GMMax(0,width-82),18);
}
- (void)settingsChanged:(NSNotification *)notification {
    if (![NSThread isMainThread]) {
        __weak GMScrollStyleCell *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(),^{ [weakSelf settingsChanged:notification]; });
        return;
    }
    [self.previewHost resetScrollAnimation]; [self refreshStyle];
}
- (void)refreshStyle {
    GMScrollSettings *settings = [GMScrollSettings sharedSettings];
    NSString *name = GMScrollPresetName(settings.presetIdentifier);
    UIButtonConfiguration *configuration = self.styleButton.configuration;
    if (configuration) { configuration.title = name; self.styleButton.configuration = configuration; }
    else [self.styleButton setTitle:name forState:0];
    self.styleButton.accessibilityValue = name;
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    BOOL preferCrossFade = UIAccessibilityPrefersCrossFadeTransitions();
    self.sampleDetail.text = reduceMotion ? @"Reduce Motion is on" : preferCrossFade ? @"Prefer Cross-Fade is on" :
        settings.enabled ? @"Preview your scrolling style" : @"Preview · animations are off";
    self.replayButton.enabled = !(reduceMotion || preferCrossFade);
    self.replayButton.accessibilityHint = reduceMotion ? @"Reduce Motion keeps this preview still." :
        preferCrossFade ? @"Prefer Cross-Fade Transitions keeps this preview still." : @"Try the current style without changing the on/off setting.";
}
- (void)applyTheme {
    // Only the system's glass buttons draw material here. The sample is an
    // independent foreground sibling, with no glass ancestor to fade or move.
    self.backgroundColor = [UIColor clearColor]; self.contentView.backgroundColor = [UIColor clearColor];
    self.previewClip.backgroundColor = [UIColor clearColor];
    self.tintColor = GMCurrentAccent(); self.heading.textColor = GMPrimaryTextColor();
    self.sampleTitle.textColor = GMPrimaryTextColor(); self.sampleDetail.textColor = GMSecondaryTextColor();
    self.sampleArtwork.tintColor = GMCurrentAccent();
    GMStyleGlassButton(self.styleButton,NO); GMStyleGlassButton(self.replayButton,NO);
    GMApplyAppFontToViewTree(self.contentView);
}
- (void)replay {
    if (!self.window) return;
    [self layoutIfNeeded]; [self.previewHost resetScrollAnimation];
    // The real preset renderer intentionally allows a preview while the
    // global switch is off. It independently honors Reduce Motion.
    [self.previewHost animateWithPreset:[GMScrollSettings sharedSettings].presetIdentifier];
}
- (void)showCredits {
    UIViewController *presenter = self.presenter;
    if (!presenter.view.window || presenter.isBeingDismissed || presenter.presentedViewController || !presenter.navigationController) return;
    [presenter.navigationController pushViewController:[GMScrollCreditsController new] animated:YES];
}
@end

@interface GMScrollCreditsController ()
@property(nonatomic, strong) UIView *backdrop;
@property(nonatomic, strong) UIVisualEffectView *glass;
@property(nonatomic, strong) UITextView *textView;
@end
@implementation GMScrollCreditsController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Scrolling Credits";
    self.backdrop = GMNewPageBackdrop(self.view.bounds,NO); [self.view addSubview:self.backdrop];
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    UIVisualEffect *effect = [glassClass respondsToSelector:@selector(effectWithStyle:)] ? [glassClass effectWithStyle:0] : nil;
    self.glass = [[UIVisualEffectView alloc] initWithEffect:effect ?: [UIBlurEffect effectWithStyle:6]];
    self.glass.layer.cornerRadius = 24; self.glass.clipsToBounds = YES;
    self.glass.userInteractionEnabled = NO; self.glass.accessibilityElementsHidden = YES;
    [self.view addSubview:self.glass];
    self.textView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.textView.editable = NO; self.textView.selectable = YES;
    self.textView.font = GMAppFont(15,0);
    self.textView.textContainerInset = UIEdgeInsetsMake(18,18,28,18);
    self.textView.alwaysBounceVertical = YES; self.textView.contentInsetAdjustmentBehavior = 2;
    self.textView.accessibilityLabel = @"Cask 3 credits and Apache License";
    NSURL *noticeURL = [[NSBundle mainBundle] URLForResource:@"Cask3-ACKNOWLEDGMENTS" withExtension:@"txt"];
    NSURL *licenseURL = [[NSBundle mainBundle] URLForResource:@"Cask3-LICENSE" withExtension:@"txt"];
    NSData *noticeData = noticeURL ? GMScrollReadBounded(noticeURL,128*1024,NULL) : nil;
    NSData *licenseData = licenseURL ? GMScrollReadBounded(licenseURL,128*1024,NULL) : nil;
    NSString *notice = noticeData ? [[NSString alloc] initWithData:noticeData encoding:NSUTF8StringEncoding] : nil;
    NSString *license = licenseData ? [[NSString alloc] initWithData:licenseData encoding:NSUTF8StringEncoding] : nil;
    if (!notice.length) notice = @"Scrolling animations adapted from Cask 3 by Ryan Nair (@ryannair05), inspired by the original Cask by Ryan Petrich. Thank you both for bringing personality to scrolling.\n\nhttps://github.com/ryannair05/Cask-3\nSource revision: f82e252334d69a151afa8f20db3d59e7a84ee592\nLicense: Apache License, Version 2.0";
    self.textView.text = [NSString stringWithFormat:@"%@\n\n%@",notice,license.length ? license : @"The full license file is unavailable in this build.\nhttps://www.apache.org/licenses/LICENSE-2.0"];
    [self.view addSubview:self.textView]; [self applyTheme];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.backdrop.frame = self.view.bounds;
    CGFloat top = self.view.safeAreaInsets.top+12, bottom = self.view.safeAreaInsets.bottom+12;
    CGRect pane = CGRectMake(12,top,GMMax(0,self.view.bounds.size.width-24),GMMax(0,self.view.bounds.size.height-top-bottom));
    self.glass.frame = pane; self.textView.frame = pane;
}
- (void)applyTheme {
    self.view.backgroundColor = GMPageColor(); self.view.tintColor = GMCurrentAccent();
    self.glass.backgroundColor = [UIColor clearColor]; self.textView.backgroundColor = [UIColor clearColor];
    self.textView.textColor = GMPrimaryTextColor(); self.textView.tintColor = GMCurrentAccent();
    GMApplyAppFontToViewTree(self.textView); GMApplyAppFontToNavigation(self.navigationController.navigationBar);
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous { [super traitCollectionDidChange:previous]; if (self.textView) [self applyTheme]; }
@end
