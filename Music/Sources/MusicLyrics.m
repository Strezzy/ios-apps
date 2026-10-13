// Included after MusicLibraryStore.m and the shared appearance helpers.
// Lyrics are local text; LRC tags are retained in storage and stripped only
// for display. No network requests, synchronized playback, or extra timers.
#import "MusicLyrics.h"

static const NSUInteger GMLyricsMaximumTextLength = 65536;
static const NSUInteger GMLyricsMaximumImportBytes = 256 * 1024;
static const NSUInteger GMLyricsMaximumManifestBytes = 8 * 1024 * 1024;
static const NSUInteger GMLyricsMaximumSongs = 20000;

static NSError *GMLyricsError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:@"com.billy.glassmusic.lyrics" code:code
                          userInfo:@{NSLocalizedDescriptionKey:description}];
}

// Read at most limit + 1 bytes, including when the input is an unexpectedly
// large file. Each FileHandle API reports NSError instead of raising the old
// readDataOfLength:/closeFile exceptions. No file timestamp/size APIs are used.
static NSData *GMLyricsReadBounded(NSURL *url, NSUInteger limit, NSError **error) {
    if (error) *error = nil;
    if (!url.isFileURL) {
        if (error) *error = GMLyricsError(1,@"Choose a text file from Files.");
        return nil;
    }
    NSError *issue = nil;
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:&issue];
    if (!handle) {
        if (error) *error = issue ?: GMLyricsError(2,@"That lyrics file couldn't be opened.");
        return nil;
    }
    NSMutableData *data = [NSMutableData new];
    while (data.length <= limit) {
        NSUInteger remaining = limit + 1 - data.length;
        NSUInteger count = remaining < 65536 ? remaining : 65536;
        NSData *part = [handle readDataUpToLength:count error:&issue];
        if (!part) { issue = issue ?: GMLyricsError(2,@"That lyrics file couldn't be read completely."); break; }
        if (!part.length) break;
        [data appendData:part];
    }
    NSError *closeError = nil;
    if (![handle closeAndReturnError:&closeError] && !issue)
        issue = closeError ?: GMLyricsError(2,@"That lyrics file couldn't be closed safely.");
    if (issue) { if (error) *error = issue; return nil; }
    if (data.length > limit) {
        if (error) *error = GMLyricsError(3,@"That lyrics file is too large.");
        return nil;
    }
    return data;
}

static NSString *GMLyricsNormalizedText(id value, NSError **error) {
    if (error) *error = nil;
    if (![value isKindOfClass:[NSString class]] || [value length] > GMLyricsMaximumTextLength) {
        if (error) *error = GMLyricsError(4,@"Use lyrics with no more than 65,536 characters.");
        return nil;
    }
    NSString *text = value;
    for (NSUInteger index = 0; index < text.length; index++) {
        unichar character = [text characterAtIndex:index];
        if ((character < 32 && character != '\n' && character != '\r' && character != '\t') || character == 127) {
            if (error) *error = GMLyricsError(5,@"This file contains non-text data. Choose a plain text or LRC lyrics file.");
            return nil;
        }
    }
    if (text.length && [text characterAtIndex:0] == 0xfeff) text = [text substringFromIndex:1];
    text = [text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    text = [text stringByReplacingOccurrencesOfString:@"\u2028" withString:@"\n"];
    text = [text stringByReplacingOccurrencesOfString:@"\u2029" withString:@"\n"];
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *GMLyricsDecodeText(NSData *data, NSError **error) {
    if (error) *error = nil;
    if (!data.length || data.length > GMLyricsMaximumImportBytes) {
        if (error) *error = GMLyricsError(6,@"Choose a nonempty text or LRC file smaller than 256 KB.");
        return nil;
    }
    const unsigned char *bytes = data.bytes;
    NSStringEncoding encoding = NSUTF8StringEncoding;
    if (data.length >= 2 && ((bytes[0] == 0xff && bytes[1] == 0xfe) || (bytes[0] == 0xfe && bytes[1] == 0xff))) {
        encoding = NSUTF16StringEncoding;
    } else if (data.length % 2 == 0) {
        // Common BOM-less UTF-16 text can be recognized by its ASCII zero-byte
        // pattern. Ambiguous non-UTF-8 data is rejected instead of guessed.
        NSUInteger pairs = data.length / 2;
        if (pairs > 128) pairs = 128;
        NSUInteger evenZero = 0, oddZero = 0;
        for (NSUInteger index = 0; index < pairs; index++) {
            if (!bytes[index*2]) evenZero++;
            if (!bytes[index*2+1]) oddZero++;
        }
        if (oddZero >= 2 && !evenZero) encoding = NSUTF16LittleEndianStringEncoding;
        else if (evenZero >= 2 && !oddZero) encoding = NSUTF16BigEndianStringEncoding;
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:encoding];
    if (!text) {
        if (error) *error = GMLyricsError(7,@"Use a UTF-8 text file, or UTF-16 text saved with a byte-order mark.");
        return nil;
    }
    text = GMLyricsNormalizedText(text,error);
    if (text && !text.length) {
        if (error) *error = GMLyricsError(8,@"That file doesn't contain any lyrics yet.");
        return nil;
    }
    return text;
}

// Begin portable timestamp parser. This exact function is also exercised by
// the focused host-side parser fixture, without reimplementing its behavior.
static BOOL GMLyricsIsTimeTag(const char *tag) {
    if (!tag) return NO;
    NSUInteger index = 0, minutes = 0;
    while (tag[index] >= '0' && tag[index] <= '9' && minutes < 4) { index++; minutes++; }
    if (!minutes || minutes > 3 || tag[index++] != ':') return NO;
    if (tag[index] < '0' || tag[index] > '5') return NO;
    index++;
    if (tag[index] < '0' || tag[index] > '9') return NO;
    index++;
    if (!tag[index]) return YES;
    if (tag[index++] != '.') return NO;
    NSUInteger fraction = 0;
    while (tag[index] >= '0' && tag[index] <= '9' && fraction < 4) { index++; fraction++; }
    return fraction >= 1 && fraction <= 3 && !tag[index];
}
// End portable timestamp parser.

static BOOL GMLyricsIsMetadataTag(NSString *tag) {
    NSString *lower = tag.lowercaseString;
    for (NSString *prefix in @[@"ar:",@"al:",@"ti:",@"au:",@"by:",@"re:",@"ve:",@"offset:",@"length:"])
        if ([lower hasPrefix:prefix]) return YES;
    return NO;
}

static NSString *GMLyricsDisplayText(NSString *source) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *rawLine in [source componentsSeparatedByString:@"\n"]) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        BOOL metadata = NO;
        // Real LRC may repeat a lyric at several timestamps. Only known time
        // or metadata tags are stripped; [Chorus] and other section labels stay.
        for (NSUInteger prefix = 0; prefix < 32 && [line hasPrefix:@"["]; prefix++) {
            NSRange end = [line rangeOfString:@"]"];
            if (end.location == NSNotFound || end.location > 100 || end.location < 2) break;
            NSString *tag = [line substringWithRange:(NSRange){1,end.location-1}];
            BOOL time = GMLyricsIsTimeTag(tag.UTF8String);
            BOOL isMetadata = !time && GMLyricsIsMetadataTag(tag);
            if (!time && !isMetadata) break;
            metadata = metadata || isMetadata;
            line = [[line substringFromIndex:end.location+1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        if (metadata && !line.length) continue;
        [lines addObject:line];
    }
    return [[lines componentsJoinedByString:@"\n"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@interface GMLyricsStore ()
@property(nonatomic, readwrite, copy) NSURL *fileURL;
@property(nonatomic, readwrite, strong) NSError *lastError;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *entries;
@property(nonatomic) BOOL loadedSuccessfully;
- (BOOL)fail:(NSError *)issue error:(NSError **)error;
@end

@implementation GMLyricsStore
- (instancetype)initWithFileURL:(NSURL *)fileURL {
    self = [super init];
    if (self) {
        self.fileURL = fileURL; self.entries = [NSDictionary dictionary];
        [self reloadWithError:NULL];
    }
    return self;
}
- (BOOL)fail:(NSError *)issue error:(NSError **)error {
    self.lastError = issue ?: GMLyricsError(9,@"Your lyrics couldn't be saved. The previous lyrics have not been changed.");
    if (error) *error = self.lastError;
    return NO;
}
- (BOOL)reloadWithError:(NSError **)error {
    if (error) *error = nil;
    self.loadedSuccessfully = NO;
    if (!self.fileURL.isFileURL || !self.fileURL.path.length)
        return [self fail:GMLyricsError(10,@"Lyrics storage is unavailable.") error:error];
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.fileURL.path]) {
        self.entries = [NSDictionary dictionary]; self.loadedSuccessfully = YES; self.lastError = nil;
        return YES;
    }
    NSError *issue = nil;
    NSData *data = GMLyricsReadBounded(self.fileURL,GMLyricsMaximumManifestBytes,&issue);
    if (!data.length) return [self fail:issue ?: GMLyricsError(11,@"The saved lyrics file is empty or unreadable. It hasn't been changed.") error:error];
    id document = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&issue];
    if (![document isKindOfClass:[NSDictionary class]])
        return [self fail:issue ?: GMLyricsError(12,@"Your saved lyrics couldn't be read. They haven't been changed.") error:error];
    id version = document[@"formatVersion"], entries = document[@"lyrics"];
    if (![version isKindOfClass:[NSNumber class]] || [version doubleValue] != 1 ||
        ![entries isKindOfClass:[NSDictionary class]] || [entries count] > GMLyricsMaximumSongs)
        return [self fail:GMLyricsError(13,@"This saved lyrics format isn't supported. It hasn't been changed.") error:error];
    for (id identifier in entries) {
        id text = entries[identifier];
        NSString *normalized = GMLyricsNormalizedText(text,NULL);
        if (!GMStoreValidTrackIdentifier(identifier) || !normalized.length)
            return [self fail:GMLyricsError(14,@"A saved lyrics entry is invalid. The original file hasn't been changed.") error:error];
    }
    self.entries = entries; self.loadedSuccessfully = YES; self.lastError = nil;
    return YES;
}
- (NSString *)lyricsForIdentifier:(NSString *)identifier {
    return GMStoreValidTrackIdentifier(identifier) ? self.entries[identifier] : nil;
}
- (BOOL)saveLyrics:(NSString *)lyrics forIdentifier:(NSString *)identifier error:(NSError **)error {
    if (error) *error = nil;
    if (!self.loadedSuccessfully)
        return [self fail:self.lastError ?: GMLyricsError(15,@"Saved lyrics couldn't be read. They haven't been changed.") error:error];
    if (!GMStoreValidTrackIdentifier(identifier))
        return [self fail:GMLyricsError(16,@"Choose a song before adding lyrics.") error:error];
    NSError *issue = nil;
    NSString *normalized = GMLyricsNormalizedText(lyrics,&issue);
    if (!normalized) return [self fail:issue error:error];
    NSMutableDictionary *candidate = [self.entries mutableCopy];
    candidate[identifier] = normalized.length ? normalized : nil;
    if (candidate.count > GMLyricsMaximumSongs)
        return [self fail:GMLyricsError(17,@"The saved lyrics collection has reached its size limit.") error:error];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:@{@"formatVersion":@1,@"lyrics":candidate}
                                                              format:200 options:0 error:&issue];
    if (!data) return [self fail:issue error:error];
    if (data.length > GMLyricsMaximumManifestBytes)
        return [self fail:GMLyricsError(18,@"The saved lyrics collection has reached its size limit.") error:error];
    if (![[NSFileManager defaultManager] createDirectoryAtURL:self.fileURL.URLByDeletingLastPathComponent
                                 withIntermediateDirectories:YES attributes:nil error:&issue] ||
        ![data writeToURL:self.fileURL options:1 error:&issue])
        return [self fail:issue error:error];
    // NSDataWritingAtomic completed before the live value is replaced.
    self.entries = candidate; self.lastError = nil;
    return YES;
}
@end

@class GMLyricsEditor;
@interface GMLyricsView () <UIDocumentPickerDelegate>
@property(nonatomic, strong) UIVisualEffectView *glassBackdrop;
@property(nonatomic, strong) UITextView *lyricsText;
@property(nonatomic, strong) UILabel *heading;
@property(nonatomic, strong) UIImageView *emptySymbol;
@property(nonatomic, strong) UILabel *emptyTitle;
@property(nonatomic, strong) UILabel *emptyDetail;
@property(nonatomic, strong) UIButton *addButton;
@property(nonatomic, strong) UIButton *pasteButton;
@property(nonatomic, strong) UIButton *editButton;
@property(nonatomic, strong) UIDocumentPickerViewController *activePicker;
@property(nonatomic, copy) NSString *pickerIdentifier;
@property(nonatomic, copy) NSString *pickerTitle;
@property(nonatomic, copy) NSString *renderedIdentifier;
@property(nonatomic, copy) NSString *renderedSource;
@property(nonatomic) BOOL loadingLyrics;
- (void)refreshContent;
- (void)openFileForIdentifier:(NSString *)identifier title:(NSString *)title;
- (void)openEditorForIdentifier:(NSString *)identifier title:(NSString *)title draft:(NSString *)draft;
- (void)didSaveLyricsForIdentifier:(NSString *)identifier;
@end

static void GMLyricsShowError(UIViewController *presenter, NSString *title, NSError *error) {
    if (!presenter.view.window || presenter.isBeingDismissed || presenter.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:error.localizedDescription ?: @"Please try again." preferredStyle:1];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:0 handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

// A fresh controller captures a single destination for its entire lifetime.
// Playback changes update the panel, never this editor's identifier or store.
@interface GMLyricsEditor : UIViewController
@property(nonatomic, weak) GMLyricsView *owner;
@property(nonatomic, strong) GMLyricsStore *store;
@property(nonatomic, copy) NSString *destinationIdentifier;
@property(nonatomic, copy) NSString *destinationTitle;
@property(nonatomic, copy) NSString *draft;
@property(nonatomic, strong) UILabel *songLabel;
@property(nonatomic, strong) UILabel *hint;
@property(nonatomic, strong) UITextView *editor;
@property(nonatomic, strong) UIBarButtonItem *saveButton;
@property(nonatomic) BOOL saving;
@property(nonatomic) BOOL canceled;
- (void)applyTheme;
@end

@implementation GMLyricsEditor
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Lyrics";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:0 target:self action:@selector(cancel)];
    self.saveButton = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:2 target:self action:@selector(save)];
    self.navigationItem.rightBarButtonItem = self.saveButton;
    self.songLabel = GMLabel(self.destinationTitle ?: @"Selected Song",17,.55,GMPrimaryTextColor());
    self.songLabel.numberOfLines = 1; [self.view addSubview:self.songLabel];
    self.hint = GMLabel(@"Paste or write lyrics, then tap Save.",12,0,GMSecondaryTextColor());
    [self.view addSubview:self.hint];
    self.editor = [[UITextView alloc] initWithFrame:CGRectZero];
    self.editor.text = self.draft ?: @"";
    self.editor.font = GMAppFont(19,0);
    self.editor.editable = YES; self.editor.selectable = YES;
    self.editor.textContainerInset = UIEdgeInsetsMake(16,12,20,12);
    self.editor.layer.cornerRadius = 18; self.editor.clipsToBounds = YES;
    self.editor.alwaysBounceVertical = YES;
    self.editor.accessibilityLabel = [NSString stringWithFormat:@"Lyrics for %@",self.destinationTitle ?: @"selected song"];
    [self.view addSubview:self.editor];
    // Initialize the system keyboard guide before the sheet's first layout.
    (void)self.view.keyboardLayoutGuide;
    [self applyTheme];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width, height = self.view.bounds.size.height;
    CGFloat top = self.view.safeAreaInsets.top+12;
    CGFloat bottom = height-self.view.safeAreaInsets.bottom;
    CGRect keyboard = self.view.keyboardLayoutGuide.layoutFrame;
    if (keyboard.size.height > 0 && keyboard.origin.y >= 0 && keyboard.origin.y < bottom)
        bottom = keyboard.origin.y;
    self.songLabel.frame = CGRectMake(18,top,GMMax(0,width-36),24);
    self.hint.frame = CGRectMake(18,top+26,GMMax(0,width-36),18);
    self.editor.frame = CGRectMake(12,top+54,GMMax(0,width-24),GMMax(44,bottom-top-66));
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.draft.length) [self.editor becomeFirstResponder];
}
- (void)applyTheme {
    self.view.backgroundColor = GMPageColor(); self.view.tintColor = GMCurrentAccent();
    self.editor.backgroundColor = GMCardColor(); self.editor.textColor = GMPrimaryTextColor();
    self.editor.tintColor = GMCurrentAccent(); self.songLabel.textColor = GMPrimaryTextColor();
    self.hint.textColor = GMSecondaryTextColor();
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (self.editor) [self applyTheme];
}
- (void)cancel { self.canceled = YES; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)save {
    if (self.canceled || self.saving || !self.view.window || self.navigationController.isBeingDismissed) return;
    [self.view endEditing:YES]; self.saving = YES; self.saveButton.enabled = NO;
    NSError *issue = nil;
    BOOL saved = [self.store saveLyrics:self.editor.text ?: @"" forIdentifier:self.destinationIdentifier error:&issue];
    self.saving = NO; self.saveButton.enabled = YES;
    if (!saved) { GMLyricsShowError(self,@"Couldn't Save Lyrics",issue); return; }
    [self.owner didSaveLyricsForIdentifier:self.destinationIdentifier];
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end

@implementation GMLyricsView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.layer.cornerRadius = 24; self.clipsToBounds = YES;
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    UIVisualEffect *effect = nil;
    if (glassClass && [glassClass respondsToSelector:@selector(effectWithStyle:)])
        effect = [glassClass effectWithStyle:0];
    if (!effect) effect = [UIBlurEffect effectWithStyle:6];
    self.glassBackdrop = [[UIVisualEffectView alloc] initWithEffect:effect];
    self.glassBackdrop.userInteractionEnabled = NO;
    self.glassBackdrop.accessibilityElementsHidden = YES;
    [self addSubview:self.glassBackdrop];
    self.heading = GMLabel(@"LYRICS",12,.6,GMSecondaryTextColor());
    [self addSubview:self.heading];
    self.lyricsText = [[UITextView alloc] initWithFrame:CGRectZero];
    self.lyricsText.editable = NO; self.lyricsText.selectable = YES;
    self.lyricsText.font = GMAppFont(23,.45);
    self.lyricsText.textContainerInset = UIEdgeInsetsMake(8,12,24,12);
    self.lyricsText.contentInsetAdjustmentBehavior = 2;
    self.lyricsText.alwaysBounceVertical = YES;
    self.lyricsText.accessibilityLabel = @"Lyrics";
    [self addSubview:self.lyricsText];
    self.emptySymbol = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"text.quote"]];
    self.emptySymbol.contentMode = 1; [self addSubview:self.emptySymbol];
    self.emptyTitle = GMLabel(@"No Lyrics Yet",21,.65,GMPrimaryTextColor());
    self.emptyTitle.adjustsFontSizeToFitWidth = YES; self.emptyTitle.minimumScaleFactor = .75;
    self.emptyTitle.textAlignment = 1; [self addSubview:self.emptyTitle];
    self.emptyDetail = GMLabel(@"Add a text file or paste your lyrics.",14,0,GMSecondaryTextColor());
    self.emptyDetail.numberOfLines = 2; self.emptyDetail.textAlignment = 1; [self addSubview:self.emptyDetail];
    self.addButton = [UIButton buttonWithType:1];
    [self.addButton setTitle:@"Add Lyrics" forState:0];
    [self.addButton setImage:[UIImage systemImageNamed:@"plus"] forState:0];
    [self.addButton addTarget:self action:@selector(addLyrics) forControlEvents:(1UL<<6)];
    self.addButton.accessibilityHint = @"Choose a downloaded text or LRC file.";
    [self addSubview:self.addButton];
    self.pasteButton = [UIButton buttonWithType:1];
    [self.pasteButton setTitle:@"Paste or Write" forState:0];
    [self.pasteButton addTarget:self action:@selector(pasteLyrics) forControlEvents:(1UL<<6)];
    [self addSubview:self.pasteButton];
    self.editButton = [UIButton buttonWithType:1];
    [self.editButton setImage:[UIImage systemImageNamed:@"ellipsis"] forState:0];
    self.editButton.accessibilityLabel = @"Lyrics options";
    self.editButton.showsMenuAsPrimaryAction = YES;
    [self addSubview:self.editButton];
    [self refreshContent]; [self applyTheme];
    return self;
}
- (void)configureForSongIdentifier:(NSString *)identifier title:(NSString *)title {
    self.songIdentifier = GMStoreValidTrackIdentifier(identifier) ? identifier : nil;
    self.songTitle = title.length ? title : @"Selected Song";
    [self refreshContent];
}
- (void)refreshContent {
    BOOL valid = GMStoreValidTrackIdentifier(self.songIdentifier);
    BOOL ready = self.store.loadedSuccessfully;
    NSString *source = valid ? [self.store lyricsForIdentifier:self.songIdentifier] : nil;
    source = source ?: @"";
    BOOL changed = ![self.renderedIdentifier isEqualToString:self.songIdentifier] || ![self.renderedSource isEqualToString:source];
    if (changed) {
        self.renderedIdentifier = self.songIdentifier; self.renderedSource = source;
        self.lyricsText.text = GMLyricsDisplayText(source);
        self.lyricsText.contentOffset = CGPointMake(0,0);
    }
    BOOL visibleLyrics = self.lyricsText.text.length > 0;
    self.lyricsText.hidden = !visibleLyrics;
    self.emptySymbol.hidden = visibleLyrics; self.emptyTitle.hidden = visibleLyrics;
    self.emptyDetail.hidden = visibleLyrics; self.addButton.hidden = visibleLyrics;
    self.pasteButton.hidden = visibleLyrics; self.editButton.hidden = !visibleLyrics;
    self.addButton.enabled = valid && ready && !self.loadingLyrics;
    self.pasteButton.enabled = self.addButton.enabled; self.editButton.enabled = self.addButton.enabled;
    self.emptyTitle.text = !valid ? @"Choose a Song" : !ready ? @"Lyrics Unavailable" : self.loadingLyrics ? @"Opening Lyrics…" : @"No Lyrics Yet";
    self.emptyDetail.text = !valid ? @"Play a song to add its lyrics." : !ready ? @"Saved lyrics couldn't be read. The original file is unchanged." : self.loadingLyrics ? @"Your text file is being opened." : source.length ? @"This file has no lyric lines. You can edit it or choose another." : @"Add a text file or paste your lyrics.";
    NSString *identifier = [self.songIdentifier copy], *title = [self.songTitle copy];
    __weak GMLyricsView *weakSelf = self;
    UIAction *edit = [UIAction actionWithTitle:@"Edit Lyrics" image:[UIImage systemImageNamed:@"pencil"] identifier:nil handler:^(UIAction *action) {
        (void)action;
        GMLyricsView *view = weakSelf;
        [view openEditorForIdentifier:identifier title:title draft:[view.store lyricsForIdentifier:identifier] ?: @""];
    }];
    UIAction *file = [UIAction actionWithTitle:@"Import from Files" image:[UIImage systemImageNamed:@"folder"] identifier:nil handler:^(UIAction *action) {
        (void)action; [weakSelf openFileForIdentifier:identifier title:title];
    }];
    self.editButton.menu = [UIMenu menuWithTitle:@"Lyrics" children:@[edit,file]];
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    self.glassBackdrop.frame = self.bounds;
    self.heading.frame = CGRectMake(18,16,GMMax(0,width-80),20);
    self.editButton.frame = CGRectMake(GMMax(0,width-56),8,42,36);
    self.lyricsText.frame = CGRectMake(0,42,width,GMMax(0,height-42));
    BOOL compact = height < 260;
    self.emptySymbol.hidden = !self.lyricsText.hidden || compact;
    self.emptyTitle.font = GMAppFont(compact ? 18 : 21,.65);
    self.emptyDetail.font = GMAppFont(compact ? 12 : 14,0);
    if (compact) {
        // The smallest supported art pane is 170 points high. Keep both
        // actions reachable, with a full 44-point Add button and no icon.
        self.heading.frame = CGRectMake(16,7,GMMax(0,width-74),17);
        CGFloat pasteY = GMMax(138,height-32);
        CGFloat addY = pasteY-48;
        CGFloat titleY = 28+GMMax(0,height-170)*.25;
        self.emptyTitle.frame = CGRectMake(14,titleY,GMMax(0,width-28),24);
        self.emptyDetail.frame = CGRectMake(14,titleY+27,GMMax(0,width-28),GMMax(0,addY-titleY-33));
        self.addButton.frame = CGRectMake(18,addY,GMMax(0,width-36),44);
        self.pasteButton.frame = CGRectMake(18,pasteY,GMMax(0,width-36),28);
    } else {
        CGFloat center = height*.48;
        self.emptySymbol.frame = CGRectMake((width-38)/2,GMMax(48,center-86),38,34);
        self.emptyTitle.frame = CGRectMake(14,center-40,GMMax(0,width-28),28);
        self.emptyDetail.frame = CGRectMake(22,center-7,GMMax(0,width-44),42);
        self.addButton.frame = CGRectMake((width-154)/2,center+47,154,46);
        self.pasteButton.frame = CGRectMake((width-154)/2,center+97,154,32);
    }
}
- (void)applyTheme {
    // The native effect and all its ancestors stay at alpha 1. Text/buttons
    // remain foreground siblings over the system glass or older blur fallback.
    self.backgroundColor = [UIColor clearColor];
    self.glassBackdrop.backgroundColor = [UIColor clearColor];
    self.tintColor = GMCurrentAccent(); self.heading.textColor = GMSecondaryTextColor();
    self.lyricsText.backgroundColor = [UIColor clearColor]; self.lyricsText.textColor = GMPrimaryTextColor();
    self.lyricsText.tintColor = GMCurrentAccent(); self.emptySymbol.tintColor = GMCurrentAccent();
    self.emptyTitle.textColor = GMPrimaryTextColor(); self.emptyDetail.textColor = GMSecondaryTextColor();
    GMStyleGlassButton(self.addButton,NO); GMStyleGlassButton(self.editButton,NO);
    self.pasteButton.tintColor = GMCurrentAccent();
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [self applyTheme];
}
- (void)updatePlaybackTime:(NSTimeInterval)time { (void)time; }
- (void)addLyrics { [self openFileForIdentifier:self.songIdentifier title:self.songTitle]; }
- (void)pasteLyrics {
    NSString *identifier = [self.songIdentifier copy];
    [self openEditorForIdentifier:identifier title:self.songTitle draft:[self.store lyricsForIdentifier:identifier] ?: @""];
}
- (void)openEditorForIdentifier:(NSString *)identifier title:(NSString *)title draft:(NSString *)draft {
    UIViewController *presenter = self.presenter;
    if (!GMStoreValidTrackIdentifier(identifier) || !self.store || !presenter.view.window ||
        presenter.isBeingDismissed || presenter.presentedViewController || self.loadingLyrics) return;
    GMLyricsEditor *editor = [GMLyricsEditor new];
    editor.owner = self; editor.store = self.store;
    editor.destinationIdentifier = identifier; editor.destinationTitle = title;
    editor.draft = draft;
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:editor];
    navigation.navigationBar.tintColor = GMCurrentAccent();
    navigation.overrideUserInterfaceStyle = presenter.overrideUserInterfaceStyle;
    navigation.modalPresentationStyle = 1;
    UISheetPresentationController *sheet = navigation.sheetPresentationController;
    sheet.detents = @[[UISheetPresentationControllerDetent largeDetent]];
    sheet.prefersGrabberVisible = YES; sheet.preferredCornerRadius = 28;
    [presenter presentViewController:navigation animated:YES completion:nil];
}
- (void)openFileForIdentifier:(NSString *)identifier title:(NSString *)title {
    UIViewController *presenter = self.presenter;
    if (!GMStoreValidTrackIdentifier(identifier) || !self.store || self.loadingLyrics || self.activePicker ||
        !presenter.view.window || presenter.isBeingDismissed || presenter.presentedViewController) return;
    // Use the ordinary extension lookup so Files' default LRC classification
    // also matches when the extension has no registered plain-text subtype.
    UTType *lrc = [UTType typeWithFilenameExtension:@"lrc"];
    NSArray<UTType *> *types = lrc ? @[UTTypePlainText,lrc] : @[UTTypePlainText];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    picker.delegate = self; picker.allowsMultipleSelection = NO;
    self.activePicker = picker; self.pickerIdentifier = identifier; self.pickerTitle = title;
    [presenter presentViewController:picker animated:YES completion:nil];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)picker {
    if (picker != self.activePicker) return;
    self.activePicker = nil; self.pickerIdentifier = nil; self.pickerTitle = nil;
    self.loadingLyrics = NO; [self refreshContent];
}
- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (picker != self.activePicker || self.loadingLyrics) return;
    NSURL *url = urls.firstObject;
    if (!url) { [self documentPickerWasCancelled:picker]; return; }
    NSString *identifier = [self.pickerIdentifier copy], *title = [self.pickerTitle copy];
    self.loadingLyrics = YES; [self refreshContent];
    BOOL scoped = [url startAccessingSecurityScopedResource];
    __weak GMLyricsView *weakSelf = self;
    [picker dismissViewControllerAnimated:YES completion:^{
        dispatch_async(dispatch_get_global_queue(0,0),^{
            @autoreleasepool {
                NSError *issue = nil;
                NSData *data = GMLyricsReadBounded(url,GMLyricsMaximumImportBytes,&issue);
                NSString *text = data ? GMLyricsDecodeText(data,&issue) : nil;
                if (scoped) [url stopAccessingSecurityScopedResource];
                dispatch_async(dispatch_get_main_queue(),^{
                    GMLyricsView *view = weakSelf;
                    if (!view || view.activePicker != picker) return;
                    view.activePicker = nil; view.pickerIdentifier = nil; view.pickerTitle = nil;
                    view.loadingLyrics = NO; [view refreshContent];
                    // A dismissed Now Playing view must never summon a late
                    // editor/error above a different screen. The file is still
                    // only a draft, so dropping it cannot change saved lyrics.
                    if (!view.window || !view.presenter.view.window || view.presenter.isBeingDismissed) return;
                    if (!text) { GMLyricsShowError(view.presenter,@"Couldn't Open Lyrics",issue); return; }
                    [view openEditorForIdentifier:identifier title:title draft:text];
                });
            }
        });
    }];
}
- (void)didSaveLyricsForIdentifier:(NSString *)identifier {
    if ([self.songIdentifier isEqualToString:identifier]) [self refreshContent];
}
@end
