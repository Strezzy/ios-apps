// Included after PlayerController's implementation. Album audio is copied to
// private staging before review. Save publishes one shared metadata transaction;
// any observed copy/metadata failure rolls back only this import's new files.
#import "MusicAlbumImport.h"

static const NSUInteger GMAlbumMaximumSongs = 500;
static const NSUInteger GMAlbumMaximumEntries = 4096;
static const NSUInteger GMAlbumMaximumAudioBytes = (NSUInteger)8*1024*1024*1024;
static const NSUInteger GMAlbumMaximumTrackBytes = (NSUInteger)2*1024*1024*1024;
static const NSUInteger GMAlbumMaximumCoverBytes = 32*1024*1024;

static NSError *GMAlbumImportError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"com.billy.glassmusic.albumimport" code:code
                          userInfo:@{NSLocalizedDescriptionKey:message}];
}
static void GMAlbumImportShowError(UIViewController *presenter, NSString *title, NSError *error) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:error.localizedDescription ?: @"Please try again." preferredStyle:1];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:0 handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}
static NSArray<NSString *> *GMAlbumResourceKeys(void) {
    return @[NSURLIsDirectoryKey,NSURLIsRegularFileKey,NSURLIsSymbolicLinkKey,NSURLFileSizeKey];
}
static NSArray<NSString *> *GMAlbumKindKeys(void) {
    return @[NSURLIsDirectoryKey,NSURLIsRegularFileKey,NSURLIsSymbolicLinkKey];
}
static BOOL GMAlbumReadCoordinated(NSURL *url, BOOL (^reader)(NSURL *,NSError **), NSError **error) {
    if (error) *error = nil;
    if (!url.isFileURL || !reader) {
        if (error) *error = GMAlbumImportError(1,@"Choose an album folder or audio files from Files.");
        return NO;
    }
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    __block BOOL success = NO;
    __block NSError *readError = nil;
    NSError *coordinationError = nil;
    [coordinator coordinateReadingItemAtURL:url options:0 error:&coordinationError byAccessor:^(NSURL *readURL) {
        success = reader(readURL,&readError);
    }];
    if (scoped) [url stopAccessingSecurityScopedResource];
    if (!success && error) *error = readError ?: coordinationError ?:
        GMAlbumImportError(2,@"Those files couldn't be read. Make sure they are downloaded in Files, then try again.");
    return success;
}
static NSString *GMAlbumUsableTitle(NSString *title, NSString *filename) {
    NSString *clean = GMStoreTrimmedString(title);
    if (GMEditsValidText(clean,NO)) return clean;
    clean = [[filename.stringByDeletingPathExtension componentsSeparatedByCharactersInSet:
        [NSCharacterSet controlCharacterSet]] componentsJoinedByString:@" "];
    clean = GMStoreTrimmedString(clean);
    return GMEditsValidText(clean,NO) ? clean : @"Untitled Song";
}
static BOOL GMAlbumIsCoverURL(NSURL *url) {
    return [@[@"jpg",@"jpeg",@"png",@"heic",@"heif",@"tif",@"tiff",@"webp"]
        containsObject:url.pathExtension.lowercaseString];
}
static NSInteger GMAlbumCoverPriority(NSURL *url) {
    NSString *name = url.lastPathComponent.stringByDeletingPathExtension.lowercaseString;
    if ([@[@"cover",@"folder",@"front",@"album",@"artwork"] containsObject:name]) return 0;
    return [name hasPrefix:@"cover"] || [name hasPrefix:@"front"] ? 1 : 2;
}
static UIImage *GMAlbumReadCover(NSURL *url, NSError **error) {
    NSDictionary *values = [url resourceValuesForKeys:GMAlbumResourceKeys() error:error];
    NSNumber *size = values[NSURLFileSizeKey];
    if (![values[NSURLIsRegularFileKey] boolValue] || [values[NSURLIsSymbolicLinkKey] boolValue] ||
        ![size isKindOfClass:[NSNumber class]] || !size.unsignedIntegerValue || size.unsignedIntegerValue > GMAlbumMaximumCoverBytes) {
        if (error && !*error) *error = GMAlbumImportError(3,@"Choose a regular image file no larger than 32 MiB.");
        return nil;
    }
    UIImage *image = GMArtworkFromURL(url);
    if (!GMStoreValidArtworkImage(image) && error)
        *error = GMAlbumImportError(4,@"That image couldn't be opened. Try a JPEG, PNG, or HEIC image.");
    return GMStoreValidArtworkImage(image) ? image : nil;
}

@interface GMAlbumImportEntry : NSObject
@property(nonatomic, copy) NSString *originalFilename;
@property(nonatomic, strong) NSURL *stagedURL;
@property(nonatomic, strong) GMTrack *track;
@end
@implementation GMAlbumImportEntry @end

@interface GMAlbumImportSession : NSObject
@property(atomic) BOOL cancelled;
@property(nonatomic) BOOL prepared;
@property(nonatomic) BOOL saving;
@property(nonatomic) NSUInteger totalBytes;
@property(nonatomic, copy) NSString *token;
@property(nonatomic, copy) NSString *folderTitle;
@property(nonatomic, strong) NSURL *stagingDirectory;
@property(nonatomic, copy) NSArray<GMAlbumImportEntry *> *entries;
@property(nonatomic, copy) NSString *album;
@property(nonatomic, copy) NSString *artist;
@property(nonatomic, strong) UIImage *artwork;
@end
@implementation GMAlbumImportSession @end

static void GMAlbumDiscardStaging(GMAlbumImportSession *session) {
    if (session.stagingDirectory)
        [[NSFileManager defaultManager] removeItemAtURL:session.stagingDirectory error:NULL];
}
static BOOL GMAlbumCopyAudio(NSURL *source, NSString *sourceName, GMAlbumImportSession *session,
                             NSMutableArray<GMAlbumImportEntry *> *entries, NSError **error) {
    if (session.cancelled) return NO;
    NSDictionary *values = [source resourceValuesForKeys:GMAlbumResourceKeys() error:error];
    NSNumber *size = values[NSURLFileSizeKey];
    NSString *extension = sourceName.pathExtension.lowercaseString;
    if (![values[NSURLIsRegularFileKey] boolValue] || [values[NSURLIsSymbolicLinkKey] boolValue] ||
        ![GMAudioExtensions() containsObject:extension] || ![size isKindOfClass:[NSNumber class]] ||
        !size.unsignedIntegerValue || size.unsignedIntegerValue > GMAlbumMaximumTrackBytes) {
        if (error && !*error) *error = GMAlbumImportError(5,
            [NSString stringWithFormat:@"%@: choose a regular supported audio file between 1 byte and 2 GiB.",sourceName]);
        return NO;
    }
    if (entries.count >= GMAlbumMaximumSongs || size.unsignedIntegerValue > GMAlbumMaximumAudioBytes-session.totalBytes) {
        if (error) *error = GMAlbumImportError(6,@"Choose one album with no more than 500 songs and 8 GiB of audio.");
        return NO;
    }
    NSString *name = [NSString stringWithFormat:@"%04lu.%@",(unsigned long)entries.count+1,extension];
    NSURL *destination = [session.stagingDirectory URLByAppendingPathComponent:name];
    if (![[NSFileManager defaultManager] copyItemAtURL:source toURL:destination error:error]) return NO;
    session.totalBytes += size.unsignedIntegerValue;
    GMAlbumImportEntry *entry = [GMAlbumImportEntry new];
    entry.originalFilename = sourceName; entry.stagedURL = destination;
    GMTrack *track = [GMTrack new]; track.url = destination;
    track.title = GMAlbumUsableTitle(nil,sourceName); track.artist = @"Unknown Artist"; track.album = @"Unknown Album";
    entry.track = track; [entries addObject:entry];
    return YES;
}
static NSString *GMAlbumCommonText(NSArray<GMAlbumImportEntry *> *entries, BOOL artist) {
    NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *spellings = [NSMutableDictionary dictionary];
    NSString *best = nil; NSUInteger bestCount = 0;
    for (GMAlbumImportEntry *entry in entries) {
        NSString *text = artist ? (entry.track.albumArtist.length ? entry.track.albumArtist : entry.track.artist) : entry.track.album;
        text = GMStoreTrimmedString(text);
        if (!GMEditsValidText(text,NO) || [text.lowercaseString isEqualToString:artist ? @"unknown artist" : @"unknown album"]) continue;
        NSString *key = text.lowercaseString;
        NSUInteger count = counts[key].unsignedIntegerValue+1;
        counts[key] = @(count); if (!spellings[key]) spellings[key] = text;
        if (count > bestCount) { best = key; bestCount = count; }
    }
    return best ? spellings[best] : nil;
}
static BOOL GMAlbumPrepareMetadata(GMAlbumImportSession *session, NSArray<GMAlbumImportEntry *> *entries,
                                   PlayerController *player, NSError **error) {
    if (!entries.count) {
        if (error) *error = GMAlbumImportError(7,@"No supported audio files were found. Choose an album folder containing MP3, M4A, AAC, WAV, AIFF, CAF, or FLAC files.");
        return NO;
    }
    for (GMAlbumImportEntry *entry in entries) {
        if (session.cancelled) return NO;
        @autoreleasepool {
            [player readMetadataForTrack:entry.track];
            entry.track.title = GMAlbumUsableTitle(entry.track.title,entry.originalFilename);
            if (!session.artwork && entry.track.artwork) session.artwork = entry.track.artwork;
            // The batch needs one shared cover, not one decoded cover per song.
            entry.track.artwork = nil;
        }
    }
    NSArray<GMAlbumImportEntry *> *ordered = [entries sortedArrayUsingComparator:^NSInteger(GMAlbumImportEntry *a, GMAlbumImportEntry *b) {
        NSInteger leftDisc = a.track.discNumber > 0 ? a.track.discNumber : 1;
        NSInteger rightDisc = b.track.discNumber > 0 ? b.track.discNumber : 1;
        if (leftDisc != rightDisc) return leftDisc < rightDisc ? -1 : 1;
        NSInteger leftTrack = a.track.trackNumber > 0 ? a.track.trackNumber : NSNotFound;
        NSInteger rightTrack = b.track.trackNumber > 0 ? b.track.trackNumber : NSNotFound;
        if (leftTrack != rightTrack) return leftTrack < rightTrack ? -1 : 1;
        NSInteger comparison = [a.originalFilename localizedStandardCompare:b.originalFilename];
        return comparison ?: [a.stagedURL.lastPathComponent compare:b.stagedURL.lastPathComponent];
    }];
    // Save exact review order, including files with missing/duplicate tags,
    // while retaining the source's disc grouping. Embedded tags stay untouched.
    NSInteger currentDisc = 0, trackNumber = 0;
    for (GMAlbumImportEntry *entry in ordered) {
        NSInteger disc = entry.track.discNumber > 0 ? entry.track.discNumber : 1;
        if (disc != currentDisc) { currentDisc = disc; trackNumber = 0; }
        entry.track.discNumber = disc; entry.track.trackNumber = ++trackNumber;
    }
    session.entries = ordered;
    session.album = GMAlbumCommonText(ordered,NO);
    if (!session.album.length && GMEditsValidText(session.folderTitle,NO)) session.album = session.folderTitle;
    if (!session.album.length) session.album = @"New Album";
    session.artist = GMAlbumCommonText(ordered,YES) ?: @"Unknown Artist";
    return YES;
}

@class GMAlbumReviewController;
@interface GMAlbumImporter () <UIDocumentPickerDelegate>
@property(nonatomic, readwrite) BOOL busy;
@property(nonatomic, weak) PlayerController *player;
@property(nonatomic, weak) UIViewController *presenter;
@property(nonatomic, strong) UIDocumentPickerViewController *activePicker;
@property(nonatomic, strong) GMAlbumReviewController *review;
@property(nonatomic, strong) GMAlbumImportSession *session;
@property(nonatomic) BOOL folderSelection;
- (void)chooseFolder:(BOOL)folder;
- (void)prepareURLs:(NSArray<NSURL *> *)urls;
- (void)cancelReview;
- (void)saveAlbum:(NSString *)album artist:(NSString *)artist artwork:(UIImage *)artwork;
- (void)finishSession:(GMAlbumImportSession *)session error:(NSError *)error importedTracks:(NSArray<GMTrack *> *)tracks;
- (void)reportPreparing:(NSString *)message session:(GMAlbumImportSession *)session;
@end

@interface GMAlbumImportFieldCell : UITableViewCell
@property(nonatomic, strong) UILabel *nameLabel;
@property(nonatomic, strong) UITextField *field;
@end
@implementation GMAlbumImportFieldCell
- (instancetype)initWithStyle:(NSInteger)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (self) { self.selectionStyle = 0; self.nameLabel = GMLabel(@"",12,.4,GMSecondaryTextColor()); [self.contentView addSubview:self.nameLabel]; }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    self.nameLabel.frame = CGRectMake(16,8,GMMax(0,width-32),18);
    self.field.frame = CGRectMake(16,27,GMMax(0,width-32),33);
}
@end

@interface GMAlbumReviewController : UITableViewController <UIDocumentPickerDelegate,UITextFieldDelegate>
@property(nonatomic, weak) GMAlbumImporter *importer;
@property(nonatomic, strong) GMAlbumImportSession *session;
@property(nonatomic, strong) UITextField *albumField;
@property(nonatomic, strong) UITextField *artistField;
@property(nonatomic, strong) UIView *artHeader;
@property(nonatomic, strong) UIImageView *cover;
@property(nonatomic, strong) UIButton *coverButton;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIBarButtonItem *saveButton;
@property(nonatomic, strong) UIImage *draftArtwork;
@property(nonatomic, strong) UIDocumentPickerViewController *coverPicker;
@property(nonatomic) BOOL loadingArtwork;
@property(nonatomic) NSUInteger artworkGeneration;
- (void)showPreparedAlbum;
- (void)setSaving:(BOOL)saving;
- (void)applyTheme;
@end

@implementation GMAlbumReviewController
- (UITextField *)newField:(NSString *)placeholder {
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];
    field.placeholder = placeholder; field.font = GMAppFont(17,0);
    field.textColor = GMPrimaryTextColor(); field.autocapitalizationType = 1;
    field.clearButtonMode = 1; field.returnKeyType = 9; field.delegate = self; field.enabled = NO;
    return field;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Import Album";
    self.navigationController.modalInPresentation = YES;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:0 target:self action:@selector(cancel)];
    self.saveButton = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:2 target:self action:@selector(save)];
    self.saveButton.enabled = NO; self.navigationItem.rightBarButtonItem = self.saveButton;
    self.albumField = [self newField:@"Album name"]; self.artistField = [self newField:@"Album artist"];
    self.tableView.rowHeight = 72;
    self.artHeader = [[UIView alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,246)];
    self.cover = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.cover.layer.cornerRadius = 16; self.cover.clipsToBounds = YES;
    [self.artHeader addSubview:self.cover];
    self.coverButton = [UIButton buttonWithType:1];
    [self.coverButton setTitle:@"  Change Cover" forState:0];
    [self.coverButton setImage:[UIImage systemImageNamed:@"photo"] forState:0];
    self.coverButton.accessibilityLabel = @"Change album cover";
    self.coverButton.enabled = NO; self.coverButton.showsMenuAsPrimaryAction = YES;
    __weak GMAlbumReviewController *weakSelf = self;
    UIAction *choose = [UIAction actionWithTitle:@"Choose Image from Files" image:[UIImage systemImageNamed:@"folder"] identifier:nil handler:^(UIAction *action) { [weakSelf chooseCover]; }];
    UIAction *remove = [UIAction actionWithTitle:@"Remove Cover" image:[UIImage systemImageNamed:@"minus.circle"] identifier:nil handler:^(UIAction *action) {
        GMAlbumReviewController *controller = weakSelf;
        if (!controller || controller.session.saving || controller.loadingArtwork) return;
        controller.draftArtwork = nil; [controller applyTheme];
    }];
    self.coverButton.menu = [UIMenu menuWithTitle:@"Album Cover" children:@[choose,remove]];
    [self.artHeader addSubview:self.coverButton];
    self.statusLabel = GMLabel(@"Preparing your album…",13,0,GMSecondaryTextColor());
    self.statusLabel.textAlignment = 1; self.statusLabel.numberOfLines = 2;
    [self.artHeader addSubview:self.statusLabel]; self.tableView.tableHeaderView = self.artHeader;
    [self applyTheme];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews]; CGFloat width = self.tableView.bounds.size.width;
    if (self.artHeader.frame.size.width != width) {
        self.artHeader.frame = CGRectMake(0,0,width,246); self.tableView.tableHeaderView = self.artHeader;
    }
    self.cover.frame = CGRectMake((width-142)/2,10,142,142);
    self.coverButton.frame = CGRectMake((width-174)/2,164,174,42);
    self.statusLabel.frame = CGRectMake(18,211,GMMax(0,width-36),34);
}
- (void)applyTheme {
    GMApplyPageBackground(self.view,self.tableView,YES);
    self.view.tintColor = GMCurrentAccent(); self.navigationController.navigationBar.tintColor = GMCurrentAccent();
    self.cover.image = self.draftArtwork ?: [UIImage systemImageNamed:@"square.stack"];
    self.cover.contentMode = self.draftArtwork ? 2 : 1;
    self.cover.backgroundColor = GMCardColor(); self.cover.tintColor = GMCurrentAccent();
    self.albumField.textColor = GMPrimaryTextColor(); self.artistField.textColor = GMPrimaryTextColor();
    self.statusLabel.textColor = GMSecondaryTextColor(); GMStyleGlassButton(self.coverButton,NO);
    GMApplyAppFontToNavigation(self.navigationController.navigationBar);
    GMApplyAppFontToViewTree(self.view);
    [self.tableView reloadData];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous]; if (self.artHeader) [self applyTheme];
}
- (void)showPreparedAlbum {
    self.albumField.text = self.session.album; self.artistField.text = self.session.artist;
    self.draftArtwork = self.session.artwork;
    self.statusLabel.text = [NSString stringWithFormat:@"%lu songs · review before saving",(unsigned long)self.session.entries.count];
    self.albumField.enabled = YES; self.artistField.enabled = YES;
    self.coverButton.enabled = YES; self.saveButton.enabled = YES;
    [self applyTheme];
}
- (void)setSaving:(BOOL)saving {
    self.session.saving = saving;
    self.saveButton.enabled = !saving && !self.loadingArtwork && self.session.prepared;
    self.navigationItem.leftBarButtonItem.enabled = !saving;
    self.albumField.enabled = !saving && self.session.prepared;
    self.artistField.enabled = !saving && self.session.prepared;
    self.coverButton.enabled = !saving && !self.loadingArtwork && self.session.prepared;
    if (saving) self.statusLabel.text = @"Saving your album…";
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return self.session.prepared ? 2 : 0; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 2 : (NSInteger)self.session.entries.count;
}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Album Details" : @"Songs";
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    return section == 0 ? @"All songs will share this album name, artist, and cover. Song titles and this order are preserved." :
        @"Save adds local copies to your music library. The original files stay where they are.";
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 0) {
        NSString *identifier = path.row == 0 ? @"AlbumName" : @"AlbumArtist";
        GMAlbumImportFieldCell *cell = [table dequeueReusableCellWithIdentifier:identifier];
        if (!cell) cell = [[GMAlbumImportFieldCell alloc] initWithStyle:0 reuseIdentifier:identifier];
        cell.nameLabel.text = path.row == 0 ? @"Album" : @"Artist"; cell.nameLabel.textColor = GMSecondaryTextColor();
        cell.field = path.row == 0 ? self.albumField : self.artistField;
        [cell.contentView addSubview:cell.field]; cell.backgroundColor = GMCardColor();
        return cell;
    }
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"AlbumImportSong"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:3 reuseIdentifier:@"AlbumImportSong"];
    GMAlbumImportEntry *entry = self.session.entries[(NSUInteger)path.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%lu. %@",(unsigned long)path.row+1,entry.track.title];
    cell.detailTextLabel.text = entry.originalFilename; cell.textLabel.textColor = GMPrimaryTextColor();
    cell.detailTextLabel.textColor = GMSecondaryTextColor(); cell.backgroundColor = GMCardColor(); cell.selectionStyle = 0;
    GMApplyAppFontToViewTree(cell.contentView);
    return cell;
}
- (BOOL)textFieldShouldReturn:(UITextField *)field { [field resignFirstResponder]; return YES; }
- (void)cancel { if (!self.session.saving) [self.importer cancelReview]; }
- (void)save {
    if (self.loadingArtwork || !self.session.prepared || self.session.saving) return;
    [self.view endEditing:YES];
    [self.importer saveAlbum:self.albumField.text artist:self.artistField.text artwork:self.draftArtwork];
}
- (void)chooseCover {
    if (self.session.saving || self.loadingArtwork || self.presentedViewController) return;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:NO];
    picker.delegate = self; picker.allowsMultipleSelection = NO; self.coverPicker = picker;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    if (controller == self.coverPicker) self.coverPicker = nil;
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (controller != self.coverPicker || !urls.count || self.session.cancelled) return;
    self.coverPicker = nil; self.loadingArtwork = YES;
    self.saveButton.enabled = NO; self.coverButton.enabled = NO;
    self.statusLabel.text = @"Reading the album cover…";
    NSUInteger generation = ++self.artworkGeneration;
    NSURL *url = urls.firstObject; __weak GMAlbumReviewController *weakSelf = self;
    [controller dismissViewControllerAnimated:YES completion:^{
        dispatch_async(dispatch_get_global_queue(0,0),^{
            @autoreleasepool {
                __block UIImage *image = nil; NSError *error = nil;
                GMAlbumReadCoordinated(url,^BOOL(NSURL *readURL,NSError **issue) {
                    image = GMAlbumReadCover(readURL,issue); return image != nil;
                },&error);
                dispatch_async(dispatch_get_main_queue(),^{
                    GMAlbumReviewController *review = weakSelf;
                    if (!review || review.session.cancelled || generation != review.artworkGeneration) return;
                    review.loadingArtwork = NO; review.saveButton.enabled = YES; review.coverButton.enabled = YES;
                    if (image) review.draftArtwork = image;
                    review.statusLabel.text = [NSString stringWithFormat:@"%lu songs · review before saving",(unsigned long)review.session.entries.count];
                    [review applyTheme];
                    if (!image) GMAlbumImportShowError(review,@"Couldn't Open Cover",error);
                });
            }
        });
    }];
}
@end

@implementation GMAlbumImporter
- (instancetype)initWithPlayer:(PlayerController *)player {
    self = [super init]; if (self) self.player = player; return self;
}
- (void)presentFromViewController:(UIViewController *)presenter {
    if (self.busy || self.player.importing || !presenter || presenter.presentedViewController) return;
    self.presenter = presenter;
    UIAlertController *choice = [UIAlertController alertControllerWithTitle:@"Import Album"
        message:@"Choose an album folder, including its cover and disc subfolders, or select the album's songs together." preferredStyle:1];
    __weak GMAlbumImporter *weakSelf = self; __weak UIAlertController *weakChoice = choice;
    [choice addAction:[UIAlertAction actionWithTitle:@"Album Folder" style:0 handler:^(UIAlertAction *action) {
        [weakChoice dismissViewControllerAnimated:YES completion:^{ [weakSelf chooseFolder:YES]; }];
    }]];
    [choice addAction:[UIAlertAction actionWithTitle:@"Select Album Songs" style:0 handler:^(UIAlertAction *action) {
        [weakChoice dismissViewControllerAnimated:YES completion:^{ [weakSelf chooseFolder:NO]; }];
    }]];
    [choice addAction:[UIAlertAction actionWithTitle:@"Cancel" style:1 handler:nil]];
    [presenter presentViewController:choice animated:YES completion:nil];
}
- (void)chooseFolder:(BOOL)folder {
    if (self.busy || self.player.importing || !self.presenter || self.presenter.presentedViewController) return;
    self.busy = YES; self.player.importing = YES; self.folderSelection = folder;
    [self.player.shell refreshPlaybackState];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:folder ? @[UTTypeFolder] : @[UTTypeAudio] asCopy:NO];
    picker.delegate = self; picker.allowsMultipleSelection = !folder; self.activePicker = picker;
    [self.presenter presentViewController:picker animated:YES completion:nil];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    if (controller != self.activePicker) return;
    self.activePicker = nil; self.busy = NO; self.player.importing = NO;
    [self.player.shell refreshPlaybackState];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (controller != self.activePicker) return;
    self.activePicker = nil; NSArray *selection = [urls copy];
    __weak GMAlbumImporter *weakSelf = self;
    [controller dismissViewControllerAnimated:YES completion:^{ [weakSelf prepareURLs:selection]; }];
}
- (void)reportPreparing:(NSString *)message session:(GMAlbumImportSession *)session {
    dispatch_async(dispatch_get_main_queue(),^{
        if (self.session == session && !session.cancelled) self.review.statusLabel.text = message;
    });
}
- (void)prepareURLs:(NSArray<NSURL *> *)urls {
    GMAlbumImportSession *session = [GMAlbumImportSession new];
    session.token = [NSUUID UUID].UUIDString;
    NSURL *cache = [[[NSFileManager defaultManager] URLsForDirectory:13 inDomains:1] firstObject];
    session.stagingDirectory = [[cache URLByAppendingPathComponent:@"AlbumImports"] URLByAppendingPathComponent:session.token];
    session.folderTitle = self.folderSelection ? GMStoreTrimmedString(urls.firstObject.lastPathComponent) : nil;
    self.session = session;
    GMAlbumReviewController *review = [[GMAlbumReviewController alloc] initWithStyle:2];
    review.importer = self; review.session = session; self.review = review;
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:review];
    navigation.modalPresentationStyle = 1; navigation.modalInPresentation = YES;
    navigation.sheetPresentationController.detents = @[[UISheetPresentationControllerDetent largeDetent]];
    navigation.sheetPresentationController.prefersGrabberVisible = YES;
    [review loadViewIfNeeded];
    BOOL folder = self.folderSelection; PlayerController *player = self.player;
    __weak GMAlbumImporter *weakSelf = self;
    // Start after presentation finishes so a fast provider failure can dismiss
    // the review cleanly instead of racing its opening transition.
    [self.presenter presentViewController:navigation animated:YES completion:^{
      dispatch_async(dispatch_get_global_queue(0,0),^{
        @autoreleasepool {
            if (session.cancelled) { GMAlbumDiscardStaging(session); return; }
            NSFileManager *fm = [NSFileManager defaultManager]; NSError *error = nil;
            NSMutableArray<GMAlbumImportEntry *> *entries = [NSMutableArray array];
            BOOL ready = urls.count && (!folder || urls.count == 1) && urls.count <= GMAlbumMaximumSongs &&
                session.stagingDirectory && [fm createDirectoryAtURL:session.stagingDirectory withIntermediateDirectories:YES attributes:nil error:&error];
            if (!ready && !error) error = GMAlbumImportError(8,@"Choose one album folder or up to 500 songs.");
            if (ready && folder) {
                ready = GMAlbumReadCoordinated(urls.firstObject,^BOOL(NSURL *folderURL,NSError **issue) {
                    NSDictionary *rootValues = [folderURL resourceValuesForKeys:GMAlbumKindKeys() error:issue];
                    if (![rootValues[NSURLIsDirectoryKey] boolValue] || [rootValues[NSURLIsSymbolicLinkKey] boolValue]) {
                        if (issue && !*issue) *issue = GMAlbumImportError(9,@"Choose a regular album folder from Files.");
                        return NO;
                    }
                    __block NSError *enumerationError = nil;
                    NSDirectoryEnumerator<NSURL *> *enumerator = [fm enumeratorAtURL:folderURL
                        includingPropertiesForKeys:GMAlbumKindKeys() options:2|4
                        errorHandler:^BOOL(NSURL *url,NSError *failure) { enumerationError = failure; return NO; }];
                    if (!enumerator) { if (issue) *issue = GMAlbumImportError(10,@"That folder couldn't be opened. Try Select Album Songs instead."); return NO; }
                    NSMutableArray<NSURL *> *audio = [NSMutableArray array], *covers = [NSMutableArray array];
                    NSUInteger visited = 0;
                    for (NSURL *url in enumerator) {
                        if (session.cancelled) return NO;
                        if (++visited > GMAlbumMaximumEntries || enumerator.level > 8) {
                            if (issue) *issue = GMAlbumImportError(11,@"Choose a single album folder with no more than 4,096 entries and 8 folder levels.");
                            return NO;
                        }
                        NSDictionary *values = [url resourceValuesForKeys:GMAlbumKindKeys() error:issue];
                        if (!values) return NO;
                        if ([values[NSURLIsSymbolicLinkKey] boolValue]) { [enumerator skipDescendants]; continue; }
                        if ([values[NSURLIsDirectoryKey] boolValue]) continue;
                        if (![values[NSURLIsRegularFileKey] boolValue]) continue;
                        if ([GMAudioExtensions() containsObject:url.pathExtension.lowercaseString]) {
                            [audio addObject:url];
                            if (audio.count > GMAlbumMaximumSongs) { if (issue) *issue = GMAlbumImportError(6,@"Choose an album with no more than 500 songs."); return NO; }
                        } else if (covers.count < 32 && GMAlbumIsCoverURL(url)) [covers addObject:url];
                    }
                    if (enumerationError) { if (issue) *issue = enumerationError; return NO; }
                    NSArray *orderedAudio = [audio sortedArrayUsingComparator:^NSInteger(NSURL *a,NSURL *b) { return [a.path localizedStandardCompare:b.path]; }];
                    for (NSURL *url in orderedAudio) {
                        if (!GMAlbumCopyAudio(url,url.lastPathComponent,session,entries,issue)) return NO;
                        [weakSelf reportPreparing:[NSString stringWithFormat:@"Copying song %lu of %lu…",(unsigned long)entries.count,(unsigned long)audio.count] session:session];
                    }
                    NSArray *orderedCovers = [covers sortedArrayUsingComparator:^NSInteger(NSURL *a,NSURL *b) {
                        NSInteger left = GMAlbumCoverPriority(a), right = GMAlbumCoverPriority(b);
                        return left != right ? (left < right ? -1 : 1) : [a.path localizedStandardCompare:b.path];
                    }];
                    for (NSURL *url in orderedCovers) {
                        if (session.cancelled) return NO;
                        UIImage *cover = GMAlbumReadCover(url,NULL);
                        if (cover) { session.artwork = cover; break; }
                    }
                    return YES;
                },&error);
            } else if (ready) {
                for (NSURL *url in urls) {
                    if (session.cancelled) { ready = NO; break; }
                    ready = GMAlbumReadCoordinated(url,^BOOL(NSURL *readURL,NSError **issue) {
                        return GMAlbumCopyAudio(readURL,url.lastPathComponent,session,entries,issue);
                    },&error);
                    if (!ready) break;
                    [weakSelf reportPreparing:[NSString stringWithFormat:@"Copying song %lu of %lu…",(unsigned long)entries.count,(unsigned long)urls.count] session:session];
                }
            }
            if (ready && !session.cancelled) {
                [weakSelf reportPreparing:@"Reading album details…" session:session];
                ready = GMAlbumPrepareMetadata(session,entries,player,&error);
            }
            if (session.cancelled) { GMAlbumDiscardStaging(session); return; }
            if (!ready) GMAlbumDiscardStaging(session);
            dispatch_async(dispatch_get_main_queue(),^{
                GMAlbumImporter *importer = weakSelf;
                if (!importer || importer.session != session || session.cancelled) { dispatch_async(dispatch_get_global_queue(0,0),^{ GMAlbumDiscardStaging(session); }); return; }
                if (!ready) { [importer finishSession:session error:error ?: GMAlbumImportError(12,@"The album couldn't be prepared.") importedTracks:nil]; return; }
                session.prepared = YES; [importer.review showPreparedAlbum];
            });
        }
      });
    }];
}
- (void)cancelReview {
    GMAlbumImportSession *session = self.session;
    if (!session || session.saving) return;
    session.cancelled = YES;
    if (session.prepared) dispatch_async(dispatch_get_global_queue(0,0),^{ GMAlbumDiscardStaging(session); });
    [self finishSession:session error:nil importedTracks:nil];
}
- (void)saveAlbum:(NSString *)album artist:(NSString *)artist artwork:(UIImage *)artwork {
    GMAlbumImportSession *session = self.session;
    if (!session || !session.prepared || session.saving || session.cancelled) return;
    NSString *name = GMStoreTrimmedString(album), *sharedArtist = GMStoreTrimmedString(artist);
    if (!GMEditsValidText(name,NO) || !GMEditsValidText(sharedArtist,NO)) {
        GMAlbumImportShowError(self.review,@"Check Album Details",GMAlbumImportError(13,@"Enter an album name and artist using up to 512 characters each, on one line."));
        return;
    }
    [self.review setSaving:YES];
    NSURL *directory = self.player.musicDirectory;
    NSMutableArray<GMTrack *> *tracks = [NSMutableArray array];
    for (NSUInteger index=0;index<session.entries.count;index++) {
        GMAlbumImportEntry *entry = session.entries[index];
        NSString *filename = [NSString stringWithFormat:@"Album-%@-%04lu.%@",session.token,(unsigned long)index+1,entry.stagedURL.pathExtension];
        GMTrack *track = [GMTrack new]; track.url = [directory URLByAppendingPathComponent:filename];
        track.title = entry.track.title; track.artist = entry.track.artist; track.album = entry.track.album;
        track.albumArtist = entry.track.albumArtist; track.trackNumber = entry.track.trackNumber;
        track.discNumber = entry.track.discNumber; track.metadataLoaded = YES;
        [tracks addObject:track];
    }
    __weak GMAlbumImporter *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(0,0),^{
        @autoreleasepool {
            NSFileManager *fm = [NSFileManager defaultManager]; NSError *error = nil;
            NSMutableArray<NSURL *> *published = [NSMutableArray array];
            BOOL success = directory && [fm createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error];
            if (success) for (GMTrack *track in tracks) {
                if ([fm fileExistsAtPath:track.url.path]) { success = NO; error = GMAlbumImportError(14,@"A new album filename is already in use. Please import the album again."); break; }
            }
            if (success) for (NSUInteger index=0;index<tracks.count;index++) {
                if (![fm moveItemAtURL:session.entries[index].stagedURL toURL:tracks[index].url error:&error]) { success = NO; break; }
                [published addObject:tracks[index].url];
            }
            if (!success) {
                NSUInteger remaining = 0;
                for (NSURL *url in published) if (![fm removeItemAtURL:url error:NULL]) remaining++;
                GMAlbumDiscardStaging(session);
                NSString *message = error.localizedDescription ?: @"The album couldn't be copied into your library.";
                if (remaining) message = [NSString stringWithFormat:@"%@ %lu new copies could not be removed from the library. Your original files are unchanged.",message,(unsigned long)remaining];
                NSError *result = GMAlbumImportError(15,message);
                dispatch_async(dispatch_get_main_queue(),^{ [weakSelf finishSession:session error:result importedTracks:nil]; });
                return;
            }
            dispatch_async(dispatch_get_main_queue(),^{
                GMAlbumImporter *importer = weakSelf;
                NSError *saveError = nil;
                BOOL saved = importer && importer.session == session &&
                    [importer.player.shell.editsStore saveImportedAlbumTracks:tracks album:name artist:sharedArtist artwork:artwork error:&saveError];
                if (saved) {
                    dispatch_async(dispatch_get_global_queue(0,0),^{ GMAlbumDiscardStaging(session); });
                    [importer finishSession:session error:nil importedTracks:tracks];
                } else {
                    dispatch_async(dispatch_get_global_queue(0,0),^{
                        NSUInteger remaining = 0;
                        for (NSURL *url in published) if (![fm removeItemAtURL:url error:NULL]) remaining++;
                        GMAlbumDiscardStaging(session);
                        NSString *message = saveError.localizedDescription ?: @"The album details couldn't be saved.";
                        if (remaining) message = [NSString stringWithFormat:@"%@ %lu new copies could not be removed from the library. Your original files are unchanged.",message,(unsigned long)remaining];
                        NSError *result = GMAlbumImportError(16,message);
                        dispatch_async(dispatch_get_main_queue(),^{ [weakSelf finishSession:session error:result importedTracks:nil]; });
                    });
                }
            });
        }
    });
}
- (void)finishSession:(GMAlbumImportSession *)session error:(NSError *)error importedTracks:(NSArray<GMTrack *> *)tracks {
    if (self.session != session) return;
    PlayerController *player = self.player;
    NSInteger selected = player.selectedIndex;
    GMTrack *current = selected >= 0 && selected < (NSInteger)player.tracks.count ? player.tracks[(NSUInteger)selected] : nil;
    BOOL selectImported = tracks.count && !player.player.isPlaying && (!current || current.demo);
    // Seed the metadata cache with the prepared tracks before loadLibrary, so
    // the new album does not re-decode every embedded cover on a second pass.
    for (GMTrack *track in tracks) [player.tracks addObject:track];
    self.busy = NO; player.importing = NO;
    self.session = nil; self.activePicker = nil;
    UINavigationController *navigation = self.review.navigationController; self.review = nil;
    if (tracks.count || error) [player loadLibrary];
    if (selectImported) {
        NSInteger index = GMTrackIndexForIdentifier(player.tracks,GMTrackIdentifier(tracks.firstObject));
        if (index != NSNotFound) [player selectTrackAtIndex:index autoplay:NO];
    }
    [player refreshEditedLibrary];
    [navigation dismissViewControllerAnimated:YES completion:^{
        if (error) [player showMessage:@"Album Not Imported" message:error.localizedDescription];
        else if (tracks.count) [player showMessage:@"Album Imported" message:[NSString stringWithFormat:@"%lu songs were added to %@.",(unsigned long)tracks.count,tracks.firstObject.album]];
    }];
}
@end
