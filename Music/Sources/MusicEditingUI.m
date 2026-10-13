// Native anchored menus, on-device details/artwork editors, and collection pickers.
// Included after the shared player, stores, browsers, and shell implementations.

static GMTrack *GMEditingTrack(GMMusicShell *shell, NSString *identifier) {
    NSInteger index = GMTrackIndexForIdentifier(shell.player.tracks,identifier);
    return index == NSNotFound ? nil : shell.player.tracks[(NSUInteger)index];
}
static GMPlaylist *GMEditingPlaylist(GMMusicShell *shell, NSString *identifier) {
    for (GMPlaylist *playlist in shell.playlistStore.playlists)
        if ([playlist.identifier isEqualToString:identifier]) return playlist;
    return nil;
}
static UIImage *GMEditingPlaylistArtwork(GMMusicShell *shell, GMPlaylist *playlist) {
    UIImage *customArtwork = playlist.artwork;
    if (customArtwork) return customArtwork;
    for (NSString *identifier in playlist.trackIdentifiers) {
        UIImage *image = GMEditingTrack(shell,identifier).artwork;
        if (image) return image;
    }
    return nil;
}
static void GMEditingError(GMMusicShell *shell, NSString *title, NSError *error) {
    [shell.player showMessage:title message:error.localizedDescription ?: @"Please try again."];
}
static void GMEditingShowController(GMMusicShell *shell, UIViewController *controller) {
    __weak GMMusicShell *weakShell = shell;
    [shell.searchController performAfterDismissingSearch:^{
        GMMusicShell *current = weakShell;
        if (current) [[current.player visiblePresenter] presentViewController:controller animated:YES completion:nil];
    }];
}
static void GMEditingPresent(GMMusicShell *shell, UIViewController *controller, BOOL startLarge) {
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    navigation.navigationBar.tintColor = GMCurrentAccent();
    navigation.modalPresentationStyle = 1;
    UISheetPresentationController *sheet = navigation.sheetPresentationController;
    sheet.detents = @[[UISheetPresentationControllerDetent mediumDetent],[UISheetPresentationControllerDetent largeDetent]];
    sheet.prefersGrabberVisible = YES; sheet.preferredCornerRadius = 28;
    if (startLarge) sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge;
    GMEditingShowController(shell,navigation);
}
@interface GMTextEntryCell : UITableViewCell
@property(strong) UILabel *fieldLabel;
@property(strong) UITextField *field;
@end
@implementation GMTextEntryCell
- (id)initWithStyle:(NSInteger)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (!self) return nil;
    self.selectionStyle = 0;
    self.fieldLabel = GMLabel(@"",12,.4,GMSecondaryTextColor());
    [self.contentView addSubview:self.fieldLabel];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    self.fieldLabel.frame = CGRectMake(16,9,GMMax(0,width-32),17);
    self.field.frame = CGRectMake(16,28,GMMax(0,width-32),32);
}
@end

@interface GMMetadataEditor : UITableViewController <UIDocumentPickerDelegate,PHPickerViewControllerDelegate,UITextFieldDelegate>
@property(weak) GMMusicShell *shell;
@property(copy) NSString *songIdentifier;
@property(copy) NSString *playlistIdentifier;
@property(strong) UITextField *titleField;
@property(strong) UITextField *artistField;
@property(strong) UITextField *albumField;
@property(strong) UIView *artHeader;
@property(strong) UIImageView *cover;
@property(strong) UIButton *artButton;
@property(strong) UIButton *artBadge;
@property(strong) UILabel *artStatus;
@property(strong) UIImage *draftArtwork;
@property(strong) UIBarButtonItem *saveButton;
@property BOOL artworkChanged;
@property BOOL loadingArtwork;
@property BOOL saving;
@property BOOL canceled;
- (void)applyTheme;
- (void)choosePhoto;
- (void)chooseImageFile;
@end
@implementation GMMetadataEditor
- (UITextField *)fieldWithText:(NSString *)text placeholder:(NSString *)placeholder {
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];
    field.text = text ?: @""; field.placeholder = placeholder;
    field.font = GMAppFont(17,0); field.textColor = GMPrimaryTextColor();
    field.autocapitalizationType = 1; field.autocorrectionType = 1;
    field.clearButtonMode = 1; field.returnKeyType = 9; field.delegate = self;
    return field;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.playlistIdentifier ? @"Edit Playlist" : @"Edit Song";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:0 target:self action:@selector(cancel)];
    self.saveButton = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:2 target:self action:@selector(save)];
    self.navigationItem.rightBarButtonItem = self.saveButton;
    if (self.playlistIdentifier) {
        GMPlaylist *playlist = GMEditingPlaylist(self.shell,self.playlistIdentifier);
        self.titleField = [self fieldWithText:playlist.name placeholder:@"Playlist name"];
        self.draftArtwork = GMEditingPlaylistArtwork(self.shell,playlist);
    } else {
        GMTrack *track = GMEditingTrack(self.shell,self.songIdentifier);
        self.titleField = [self fieldWithText:track.title placeholder:@"Song title"];
        self.artistField = [self fieldWithText:track.artist placeholder:@"Artist"];
        self.albumField = [self fieldWithText:track.album placeholder:@"Album"];
        self.draftArtwork = track.artwork;
    }
    self.tableView.rowHeight = 72;
    self.artHeader = [[UIView alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,218)];
    self.cover = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.cover.layer.cornerRadius = 18; self.cover.clipsToBounds = YES;
    [self.artHeader addSubview:self.cover];
    self.artButton = [UIButton buttonWithType:0];
    self.artButton.accessibilityLabel = @"Change artwork";
    self.artBadge = [UIButton buttonWithType:1];
    [self.artBadge setTitle:@"Edit" forState:0];
    [self.artBadge setImage:[UIImage systemImageNamed:@"pencil"] forState:0];
    self.artBadge.accessibilityLabel = @"Change artwork";
    GMStyleGlassButton(self.artBadge,NO);
    __weak GMMetadataEditor *weakSelf = self;
    UIAction *photos = [UIAction actionWithTitle:@"Choose Photo" image:[UIImage systemImageNamed:@"photo"] identifier:nil handler:^(UIAction *action) { [weakSelf choosePhoto]; }];
    UIAction *files = [UIAction actionWithTitle:@"Choose File" image:[UIImage systemImageNamed:@"folder"] identifier:nil handler:^(UIAction *action) { [weakSelf chooseImageFile]; }];
    UIMenu *artMenu = [UIMenu menuWithTitle:@"Artwork" children:@[photos,files]];
    self.artButton.menu = artMenu; self.artButton.showsMenuAsPrimaryAction = YES;
    self.artBadge.menu = artMenu; self.artBadge.showsMenuAsPrimaryAction = YES;
    [self.artHeader addSubview:self.artButton]; [self.artHeader addSubview:self.artBadge];
    self.artStatus = GMLabel(@"Choose a photo or image from Files",12,0,GMSecondaryTextColor());
    self.artStatus.textAlignment = 1; [self.artHeader addSubview:self.artStatus];
    self.tableView.tableHeaderView = self.artHeader;
    [self applyTheme];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.tableView.bounds.size.width;
    if (self.artHeader.frame.size.width != width) {
        self.artHeader.frame = CGRectMake(0,0,width,218); self.tableView.tableHeaderView = self.artHeader;
    }
    self.cover.frame = CGRectMake((width-144)/2,14,144,144);
    self.artButton.frame = self.cover.frame;
    self.artBadge.frame = CGRectMake((width-76)/2,135,76,34);
    self.artStatus.frame = CGRectMake(12,184,GMMax(0,width-24),19);
}
- (void)applyTheme {
    GMApplyPageBackground(self.view,self.tableView,YES);
    self.view.tintColor = GMCurrentAccent();
    self.cover.backgroundColor = GMCardColor(); self.cover.tintColor = GMCurrentAccent();
    self.cover.image = self.draftArtwork ?: [UIImage systemImageNamed:self.playlistIdentifier ? @"music.note.list" : @"music.note"];
    self.cover.contentMode = self.draftArtwork ? 2 : 1;
    self.artStatus.textColor = GMSecondaryTextColor();
    self.titleField.textColor = GMPrimaryTextColor(); self.artistField.textColor = GMPrimaryTextColor(); self.albumField.textColor = GMPrimaryTextColor();
    GMStyleGlassButton(self.artBadge,NO);
    [self.tableView reloadData];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (self.artHeader) [self applyTheme];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return self.playlistIdentifier ? 1 : 3; }
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section { return @"Saved on this iPhone."; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    GMTextEntryCell *cell = [[GMTextEntryCell alloc] initWithStyle:0 reuseIdentifier:nil];
    cell.backgroundColor = GMCardColor(); cell.fieldLabel.textColor = GMSecondaryTextColor();
    cell.fieldLabel.text = path.row == 0 ? (self.playlistIdentifier ? @"Playlist Name" : @"Title") : path.row == 1 ? @"Artist" : @"Album";
    cell.field = path.row == 0 ? self.titleField : path.row == 1 ? self.artistField : self.albumField;
    [cell.contentView addSubview:cell.field];
    return cell;
}
- (BOOL)textFieldShouldReturn:(UITextField *)field { [field resignFirstResponder]; return YES; }
- (void)cancel { self.canceled = YES; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)save {
    if (self.canceled || self.saving || self.loadingArtwork) return;
    [self.view endEditing:YES]; self.saving = YES; self.saveButton.enabled = NO;
    NSError *error = nil; BOOL saved = NO;
    if (self.playlistIdentifier) {
        saved = [self.shell.playlistStore updatePlaylist:self.playlistIdentifier name:self.titleField.text artwork:self.draftArtwork replaceArtwork:self.artworkChanged error:&error];
    } else {
        GMTrack *track = GMEditingTrack(self.shell,self.songIdentifier);
        if (track) saved = [self.shell.editsStore saveTrack:track title:self.titleField.text artist:self.artistField.text album:self.albumField.text artwork:self.draftArtwork replaceArtwork:self.artworkChanged error:&error];
    }
    self.saving = NO; self.saveButton.enabled = YES;
    if (!saved) { GMEditingError(self.shell,@"Couldn't Save Changes",error); return; }
    [self.shell.player refreshEditedLibrary];
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)beginArtworkLoad {
    self.loadingArtwork = YES; self.saveButton.enabled = NO;
    self.artButton.enabled = NO; self.artBadge.enabled = NO;
    self.artStatus.text = @"Loading artwork…";
}
- (void)finishArtworkLoad:(UIImage *)image error:(NSError *)error {
    if (self.canceled) return;
    self.loadingArtwork = NO; self.saveButton.enabled = YES;
    self.artButton.enabled = YES; self.artBadge.enabled = YES;
    self.artStatus.text = @"Choose a photo or image from Files";
    if (!image) {
        // A provider may finish after Cancel or during an interactive sheet
        // dismissal. Do not put its error over the newly exposed library.
        if (self.navigationController.isBeingDismissed || !self.navigationController.presentingViewController) return;
        [self.shell.player showMessage:@"Couldn't Open Artwork" message:error.localizedDescription ?: @"Choose a downloaded photo, JPEG, PNG, or HEIC image."];
        return;
    }
    self.draftArtwork = image; self.artworkChanged = YES;
    self.cover.image = image; self.cover.contentMode = 2;
}
- (void)choosePhoto {
    if (self.loadingArtwork || self.presentedViewController) return;
    [self.view endEditing:YES];
    PHPickerConfiguration *configuration = [PHPickerConfiguration new];
    configuration.filter = [PHPickerFilter imagesFilter]; configuration.selectionLimit = 1;
    configuration.preferredAssetRepresentationMode = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    NSItemProvider *provider = results.firstObject.itemProvider;
    if (!provider) { [picker dismissViewControllerAnimated:YES completion:nil]; return; }
    [self beginArtworkLoad];
    __weak GMMetadataEditor *weakSelf = self;
    [picker dismissViewControllerAnimated:YES completion:^{
        [provider loadFileRepresentationForTypeIdentifier:UTTypeImage.identifier completionHandler:^(NSURL *url,NSError *error) {
            @autoreleasepool {
                // This provider URL expires when this callback returns.
                UIImage *image = GMArtworkFromURL(url);
                dispatch_async(dispatch_get_main_queue(),^{ [weakSelf finishArtworkLoad:image error:error]; });
            }
        }];
    }];
}
- (void)chooseImageFile {
    if (self.loadingArtwork || self.presentedViewController) return;
    [self.view endEditing:YES];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];
    picker.delegate = self; picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject; if (!url) return;
    [self beginArtworkLoad];
    BOOL access = [url startAccessingSecurityScopedResource];
    __weak GMMetadataEditor *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(0,0),^{
        @autoreleasepool {
            UIImage *image = GMArtworkFromURL(url);
            if (access) [url stopAccessingSecurityScopedResource];
            dispatch_async(dispatch_get_main_queue(),^{ [weakSelf finishArtworkLoad:image error:nil]; });
        }
    });
}
@end

@interface GMCollectionDestinationPicker : GMBrowseTableController
@property(copy) NSString *songIdentifier;
@property BOOL choosesAlbum;
@property(copy) NSArray<NSString *> *itemIdentifiers;
@end
@implementation GMCollectionDestinationPicker
- (void)viewDidLoad {
    self.tableStyle = 2; [super viewDidLoad];
    self.title = self.choosesAlbum ? @"Add to Album" : @"Add to Playlist";
    self.navigationItem.rightBarButtonItem = nil;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:0 target:self action:@selector(cancel)];
    self.table.tableHeaderView = GMBrowseMessage(self.choosesAlbum ? @"Choose an album to use its artist, album name, and artwork for this song." : @"Choose a playlist for this song.",78);
    [self reloadLibrary];
}
- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)reloadLibrary {
    NSMutableArray *identifiers = [NSMutableArray array];
    if (self.choosesAlbum) for (GMAlbum *album in self.shell.albums) [identifiers addObject:album.identifier];
    else for (GMPlaylist *playlist in self.shell.playlistStore.playlists) [identifiers addObject:playlist.identifier];
    self.itemIdentifiers = identifiers;
    self.table.tableFooterView = identifiers.count ? [[UIView alloc] initWithFrame:CGRectZero] : GMBrowseMessage(self.choosesAlbum ? @"Add music to your library to see albums here." : @"Create a playlist in the Playlists tab first.",88);
    [super reloadLibrary];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.itemIdentifiers.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    // Reuse the browser's fixed 48-point cover layout, with swipe actions
    // disabled, so portrait and panoramic artwork cannot stretch these rows.
    GMBrowseSongCell *cell = GMBrowseCell(table,@"Destination");
    cell.backgroundColor = GMCardColor(); cell.tintColor = GMCurrentAccent();
    cell.textLabel.textColor = GMPrimaryTextColor(); cell.detailTextLabel.textColor = GMSecondaryTextColor();
    NSString *identifier = self.itemIdentifiers[path.row]; UIImage *artwork = nil;
    if (self.choosesAlbum) {
        GMAlbum *album = GMBrowseAlbum(self.shell,identifier);
        cell.textLabel.text = album.title; cell.detailTextLabel.text = album.artist; artwork = album.artwork;
    } else {
        GMPlaylist *playlist = GMEditingPlaylist(self.shell,identifier);
        NSArray *availableSongs = [self.shell.playlistStore trackIndexesForPlaylist:identifier tracks:self.shell.player.tracks];
        cell.textLabel.text = playlist.name; cell.detailTextLabel.text = GMBrowseSongCount(availableSongs.count);
        artwork = GMEditingPlaylistArtwork(self.shell,playlist);
    }
    GMBrowseSetArtwork(cell.imageView,artwork,self.choosesAlbum ? @"square.stack" : @"music.note.list");
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.row < 0 || path.row >= (NSInteger)self.itemIdentifiers.count) return;
    GMTrack *track = GMEditingTrack(self.shell,self.songIdentifier);
    NSString *identifier = self.itemIdentifiers[path.row]; NSError *error = nil; BOOL saved = NO;
    if (track) {
        if (self.choosesAlbum) {
            GMAlbum *album = GMBrowseAlbum(self.shell,identifier);
            if (album) saved = [self.shell.editsStore assignTrack:track toAlbum:album tracks:self.shell.player.tracks error:&error];
        } else saved = [self.shell.playlistStore addTracks:@[track] toPlaylist:identifier error:&error];
    }
    if (!saved) { GMEditingError(self.shell,self.choosesAlbum ? @"Couldn't Add to Album" : @"Couldn't Add to Playlist",error); [self reloadLibrary]; return; }
    [self.shell.player refreshEditedLibrary];
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end

@implementation GMMusicShell (GMEditing)
- (UIMenu *)songMenuForIdentifier:(NSString *)identifier fromView:(UIView *)view {
    NSString *songIdentifier = [identifier copy]; __weak GMMusicShell *weakSelf = self;
    __weak UIView *weakView = view;
    UIAction *edit = [UIAction actionWithTitle:@"Edit Song" image:[UIImage systemImageNamed:@"pencil"] identifier:nil handler:^(UIAction *action) { [weakSelf editSongWithIdentifier:songIdentifier fromView:weakView]; }];
    UIAction *album = [UIAction actionWithTitle:@"Add to Album" image:[UIImage systemImageNamed:@"square.stack"] identifier:nil handler:^(UIAction *action) { [weakSelf chooseAlbumForSongWithIdentifier:songIdentifier]; }];
    UIAction *playlist = [UIAction actionWithTitle:@"Add to Playlist" image:[UIImage systemImageNamed:@"text.badge.plus"] identifier:nil handler:^(UIAction *action) { [weakSelf choosePlaylistForSongWithIdentifier:songIdentifier]; }];
    return [UIMenu menuWithTitle:@"" children:@[edit,album,playlist]];
}
- (UIMenu *)playlistMenuForIdentifier:(NSString *)identifier fromView:(UIView *)view {
    NSString *playlistIdentifier = [identifier copy]; __weak GMMusicShell *weakSelf = self;
    __weak UIView *weakView = view;
    UIAction *edit = [UIAction actionWithTitle:@"Edit Playlist" image:[UIImage systemImageNamed:@"pencil"] identifier:nil handler:^(UIAction *action) { [weakSelf editPlaylistWithIdentifier:playlistIdentifier fromView:weakView]; }];
    UIAction *remove = [UIAction actionWithTitle:@"Delete Playlist" image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction *action) { [weakSelf confirmDeletePlaylistWithIdentifier:playlistIdentifier]; }];
    remove.attributes = UIMenuElementAttributesDestructive;
    return [UIMenu menuWithTitle:@"" children:@[edit,remove]];
}
- (void)editSongWithIdentifier:(NSString *)identifier fromView:(UIView *)view {
    GMTrack *track = GMEditingTrack(self,identifier); if (!track) return;
    [self.player readMetadataForTrack:track]; [self.editsStore applyToTrack:track];
    GMMetadataEditor *editor = [[GMMetadataEditor alloc] initWithStyle:2];
    editor.shell = self; editor.songIdentifier = identifier;
    GMEditingPresent(self,editor,YES);
}
- (void)editPlaylistWithIdentifier:(NSString *)identifier fromView:(UIView *)view {
    if (!GMEditingPlaylist(self,identifier)) return;
    GMMetadataEditor *editor = [[GMMetadataEditor alloc] initWithStyle:2];
    editor.shell = self; editor.playlistIdentifier = identifier;
    GMEditingPresent(self,editor,NO);
}
- (void)chooseAlbumForSongWithIdentifier:(NSString *)identifier {
    if (!GMEditingTrack(self,identifier)) return;
    GMCollectionDestinationPicker *picker = [GMCollectionDestinationPicker new];
    picker.shell = self; picker.songIdentifier = identifier; picker.choosesAlbum = YES;
    GMEditingPresent(self,picker,NO);
}
- (void)choosePlaylistForSongWithIdentifier:(NSString *)identifier {
    if (!GMEditingTrack(self,identifier)) return;
    GMCollectionDestinationPicker *picker = [GMCollectionDestinationPicker new];
    picker.shell = self; picker.songIdentifier = identifier;
    GMEditingPresent(self,picker,NO);
}
- (void)confirmDeleteSongWithIdentifier:(NSString *)identifier {
    GMTrack *track = GMEditingTrack(self,identifier); if (!track) return;
    NSString *stableIdentifier = [identifier copy];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete Song?" message:[NSString stringWithFormat:@"Remove “%@” from Music?",track.title ?: @"this song"] preferredStyle:1];
    __weak GMMusicShell *weakSelf = self; __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:1 handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete Song" style:2 handler:^(UIAlertAction *action) {
        [weakAlert dismissViewControllerAnimated:YES completion:^{
            GMMusicShell *shell = weakSelf;
            NSInteger index = GMTrackIndexForIdentifier(shell.player.tracks,stableIdentifier);
            if (index != NSNotFound) [shell.player removeTrackAtIndex:index];
        }];
    }]];
    GMEditingShowController(self,alert);
}
- (void)confirmDeletePlaylistWithIdentifier:(NSString *)identifier {
    GMPlaylist *playlist = GMEditingPlaylist(self,identifier); if (!playlist) return;
    NSString *stableIdentifier = [identifier copy];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete Playlist?" message:[NSString stringWithFormat:@"Delete “%@”? Its songs will stay in Music.",playlist.name] preferredStyle:1];
    __weak GMMusicShell *weakSelf = self; __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:1 handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete Playlist" style:2 handler:^(UIAlertAction *action) {
        [weakAlert dismissViewControllerAnimated:YES completion:^{
            GMMusicShell *shell = weakSelf; NSError *error = nil;
            if (![shell.playlistStore deletePlaylist:stableIdentifier error:&error]) { GMEditingError(shell,@"Couldn't Delete Playlist",error); return; }
            for (UINavigationController *navigation in shell.viewControllers) {
                BOOL containsDeletedPlaylist = NO;
                for (UIViewController *controller in navigation.viewControllers) {
                    NSString *openPlaylist = nil;
                    if ([controller isKindOfClass:[GMBrowseSongsController class]]) openPlaylist = ((GMBrowseSongsController *)controller).playlistIdentifier;
                    else if ([controller isKindOfClass:[GMPlaylistSongPicker class]]) openPlaylist = ((GMPlaylistSongPicker *)controller).playlistIdentifier;
                    if ([openPlaylist isEqualToString:stableIdentifier]) { containsDeletedPlaylist = YES; break; }
                }
                if (containsDeletedPlaylist) [navigation popToRootViewControllerAnimated:YES];
            }
            [shell reloadLibrary];
        }];
    }]];
    GMEditingShowController(self,alert);
}
- (void)confirmRemoveSongIdentifier:(NSString *)songIdentifier fromPlaylist:(NSString *)playlistIdentifier {
    GMTrack *track = GMEditingTrack(self,songIdentifier);
    GMPlaylist *playlist = GMEditingPlaylist(self,playlistIdentifier); if (!track || !playlist) return;
    NSString *songID = [songIdentifier copy], *playlistID = [playlistIdentifier copy];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Remove from Playlist?" message:[NSString stringWithFormat:@"Remove “%@” from “%@”? The song will stay in Music.",track.title,playlist.name] preferredStyle:1];
    __weak GMMusicShell *weakSelf = self; __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:1 handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:2 handler:^(UIAlertAction *action) {
        [weakAlert dismissViewControllerAnimated:YES completion:^{
            GMMusicShell *shell = weakSelf; NSError *error = nil;
            if (![shell.playlistStore removeTrackIdentifier:songID fromPlaylist:playlistID error:&error]) { GMEditingError(shell,@"Couldn't Remove Song",error); return; }
            [shell reloadLibrary];
        }];
    }]];
    GMEditingShowController(self,alert);
}
@end
