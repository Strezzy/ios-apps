// Imported after MusicLibraryStore.m into main.m. Its private validation and
// artwork helpers are shared; Apple's SDK builds use the real framework APIs.
#import "MusicEditsStore.h"

static const NSUInteger GMEditsMaximumTracks = 20000;
static const NSUInteger GMEditsMaximumFieldLength = 512;
static const NSUInteger GMEditsMaximumFileBytes = 8 * 1024 * 1024;

static NSError *GMEditsError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:@"com.billy.glassmusic.edits" code:code
                          userInfo:@{NSLocalizedDescriptionKey:description}];
}

static BOOL GMEditsValidText(id value, BOOL allowEmpty) {
    if (![value isKindOfClass:[NSString class]]) return NO;
    NSString *text = value;
    return (allowEmpty || GMStoreTrimmedString(text).length > 0) && text.length <= GMEditsMaximumFieldLength &&
        [text rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location == NSNotFound;
}

static BOOL GMEditsValidBoolean(id value) {
    return [value isKindOfClass:[NSNumber class]] &&
        ([value doubleValue] == 0 || [value doubleValue] == 1);
}

static BOOL GMEditsValidOrder(id value) {
    if (![value isKindOfClass:[NSNumber class]]) return NO;
    double number = [value doubleValue];
    return number >= 1 && number <= 100000 && number == (double)[value integerValue];
}

static BOOL GMEditsValidRecord(NSDictionary *record, NSString *trackID) {
    if (![record isKindOfClass:[NSDictionary class]] || record.count > 9) return NO;
    for (id key in record) {
        if (![key isKindOfClass:[NSString class]]) return NO;
        id value = record[key];
        if ([key isEqualToString:@"title"]) {
            if (!GMEditsValidText(value, NO)) return NO;
        } else if ([key isEqualToString:@"artist"] || [key isEqualToString:@"album"] || [key isEqualToString:@"albumArtist"]) {
            if (!GMEditsValidText(value, YES)) return NO;
        } else if ([key isEqualToString:@"artworkFilename"]) {
            if (!GMStoreValidArtworkFilename(value)) return NO;
        } else if ([key isEqualToString:@"artworkCleared"]) {
            if (!GMEditsValidBoolean(value)) return NO;
        } else if ([key isEqualToString:@"hidden"]) {
            if (![trackID isEqualToString:@"demo:glass-study"] || !GMEditsValidBoolean(value)) return NO;
        } else if ([key isEqualToString:@"trackNumber"] || [key isEqualToString:@"discNumber"]) {
            if (!GMEditsValidOrder(value)) return NO;
        } else return NO; // Never silently discard an unknown future field.
    }
    return !(record[@"artworkFilename"] && [record[@"artworkCleared"] unsignedIntegerValue]);
}

@interface GMTrackEditsStore ()
@property(nonatomic, readwrite, copy) NSURL *fileURL;
@property(nonatomic, readwrite, strong) NSError *lastError;
@property(nonatomic, copy) NSDictionary<NSString *, NSDictionary *> *overrides;
@property(nonatomic) BOOL loadedSuccessfully;
// One shared album cover stays decoded while its consecutive tracks load.
// A bounded single-entry cache prevents a batch from decoding the same image
// once for every song without retaining all artwork in a second global cache.
@property(nonatomic, copy) NSString *cachedArtworkFilename;
@property(nonatomic, strong) UIImage *cachedArtwork;
- (BOOL)fail:(NSError *)issue error:(NSError **)error;
- (BOOL)readyWithError:(NSError **)error;
- (NSURL *)artworkDirectory;
- (BOOL)commitOverrides:(NSDictionary<NSString *, NSDictionary *> *)overrides error:(NSError **)error;
- (BOOL)saveFields:(NSDictionary<NSString *, NSString *> *)fields forTrack:(GMTrack *)track
          artwork:(UIImage *)artwork replaceArtwork:(BOOL)replaceArtwork error:(NSError **)error;
@end

@implementation GMTrackEditsStore
- (instancetype)initWithFileURL:(NSURL *)fileURL {
    self = [super init];
    if (self) {
        self.fileURL = fileURL; self.overrides = [NSDictionary dictionary];
        [self reloadWithError:NULL];
    }
    return self;
}

- (BOOL)fail:(NSError *)issue error:(NSError **)error {
    self.lastError = issue ?: GMEditsError(1, @"Your song changes couldn't be saved.");
    if (error) *error = self.lastError;
    return NO;
}

- (BOOL)readyWithError:(NSError **)error {
    if (error) *error = nil;
    if (!self.loadedSuccessfully) return [self fail:self.lastError ?: GMEditsError(2,
        @"Your saved song changes couldn't be read. The original file hasn't been changed.") error:error];
    return YES;
}

- (NSURL *)artworkDirectory {
    return [self.fileURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"MusicEditsArtwork"];
}

- (BOOL)reloadWithError:(NSError **)error {
    if (error) *error = nil;
    self.loadedSuccessfully = NO;
    self.cachedArtworkFilename = nil; self.cachedArtwork = nil;
    if (!self.fileURL.isFileURL || !self.fileURL.path.length) {
        return [self fail:GMEditsError(3, @"Song editing storage is unavailable.") error:error];
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.fileURL.path]) {
        self.overrides = [NSDictionary dictionary]; self.loadedSuccessfully = YES; self.lastError = nil;
        return YES;
    }
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:self.fileURL options:1 error:&readError];
    if (!data) return [self fail:readError error:error];
    if (!data.length || data.length > GMEditsMaximumFileBytes) {
        return [self fail:GMEditsError(4, @"The song changes file is empty or too large. It hasn't been changed.") error:error];
    }
    id document = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&readError];
    if (![document isKindOfClass:[NSDictionary class]]) {
        return [self fail:readError ?: GMEditsError(5, @"Your saved song changes couldn't be read. They haven't been changed.") error:error];
    }
    id version = document[@"formatVersion"], entries = document[@"tracks"];
    if ([document count] != 2 || ![version isKindOfClass:[NSNumber class]] || [version doubleValue] != 1 ||
        ![entries isKindOfClass:[NSDictionary class]] || [entries count] > GMEditsMaximumTracks) {
        return [self fail:GMEditsError(6, @"The saved song changes format isn't supported. It hasn't been changed.") error:error];
    }
    NSMutableDictionary<NSString *, NSDictionary *> *loaded = [NSMutableDictionary dictionary];
    for (id trackID in entries) {
        id entry = entries[trackID];
        if (!GMStoreValidTrackIdentifier(trackID) || !GMEditsValidRecord(entry, trackID)) {
            return [self fail:GMEditsError(7, @"A saved song change is invalid. The original file hasn't been changed.") error:error];
        }
        loaded[trackID] = [entry copy];
    }
    self.overrides = loaded; self.loadedSuccessfully = YES; self.lastError = nil;
    return YES;
}

- (void)applyToTrack:(GMTrack *)track {
    NSString *trackID = GMTrackIdentifier(track);
    if (!trackID) return;
    NSDictionary *record = self.overrides[trackID];
    if (!record) return;
    if (record[@"title"]) track.title = record[@"title"];
    if (record[@"artist"]) track.artist = record[@"artist"];
    if (record[@"album"]) track.album = record[@"album"];
    if (record[@"albumArtist"]) track.albumArtist = record[@"albumArtist"];
    if (record[@"trackNumber"]) track.trackNumber = [record[@"trackNumber"] integerValue];
    if (record[@"discNumber"]) track.discNumber = [record[@"discNumber"] integerValue];
    if ([record[@"artworkCleared"] unsignedIntegerValue]) track.artwork = nil;
    else if (record[@"artworkFilename"]) {
        NSString *filename = record[@"artworkFilename"];
        UIImage *artwork = [self.cachedArtworkFilename isEqualToString:filename] ? self.cachedArtwork : nil;
        if (!artwork) {
            artwork = GMStoreReadArtwork([self artworkDirectory], filename);
            self.cachedArtworkFilename = artwork ? filename : nil;
            self.cachedArtwork = artwork;
        }
        // A missing/corrupt custom image preserves the caller's raw embedded
        // image. An explicit clear above is deliberately different.
        if (artwork) track.artwork = artwork;
    }
}

- (BOOL)isTrackHidden:(GMTrack *)track {
    NSString *trackID = GMTrackIdentifier(track);
    return trackID && [self.overrides[trackID][@"hidden"] unsignedIntegerValue] != 0;
}

- (BOOL)commitOverrides:(NSDictionary<NSString *, NSDictionary *> *)overrides error:(NSError **)error {
    if (![self readyWithError:error]) return NO;
    if (overrides.count > GMEditsMaximumTracks) {
        return [self fail:GMEditsError(10, @"Your saved song changes have reached the track limit.") error:error];
    }
    NSError *writeError = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:@{@"formatVersion":@1, @"tracks":overrides}
                                                              format:200 options:0 error:&writeError];
    if (!data) return [self fail:writeError error:error];
    if (data.length > GMEditsMaximumFileBytes) {
        return [self fail:GMEditsError(10, @"Your saved song changes have reached the storage limit.") error:error];
    }
    if (![[NSFileManager defaultManager] createDirectoryAtURL:self.fileURL.URLByDeletingLastPathComponent
                                  withIntermediateDirectories:YES attributes:nil error:&writeError] ||
        ![data writeToURL:self.fileURL options:1 error:&writeError]) {
        return [self fail:writeError error:error];
    }
    NSDictionary<NSString *, NSDictionary *> *previous = self.overrides;
    self.overrides = overrides; self.lastError = nil;
    NSMutableDictionary *referencedArtwork = [NSMutableDictionary dictionary];
    for (NSString *trackID in overrides) {
        NSString *filename = overrides[trackID][@"artworkFilename"];
        if (filename) referencedArtwork[filename] = @YES;
    }
    if (self.cachedArtworkFilename && !referencedArtwork[self.cachedArtworkFilename]) {
        self.cachedArtworkFilename = nil; self.cachedArtwork = nil;
    }
    // This cleanup cannot alter the audio directory or any currently referenced
    // cover. Failed cleanup merely leaves an unused UUID image behind.
    for (NSString *trackID in previous) {
        NSString *filename = previous[trackID][@"artworkFilename"];
        if (filename && !referencedArtwork[filename]) GMStoreRemoveArtwork([self artworkDirectory], filename);
    }
    return YES;
}

- (BOOL)saveFields:(NSDictionary<NSString *, NSString *> *)fields forTrack:(GMTrack *)track
          artwork:(UIImage *)artwork replaceArtwork:(BOOL)replaceArtwork error:(NSError **)error {
    if (![self readyWithError:error]) return NO;
    NSString *trackID = GMTrackIdentifier(track);
    if (!trackID) return [self fail:GMEditsError(8, @"That song is no longer available.") error:error];
    NSMutableDictionary *record = [self.overrides[trackID] mutableCopy] ?: [NSMutableDictionary dictionary];
    for (NSString *key in fields) record[key] = fields[key];
    if (!GMEditsValidRecord(record, trackID)) {
        return [self fail:GMEditsError(9, @"Use a nonempty song title and up to 512 characters per field, each on one line.") error:error];
    }
    NSString *newFilename = nil;
    if (replaceArtwork && artwork) {
        NSError *artworkError = nil;
        newFilename = GMStoreWriteArtwork(artwork, [self artworkDirectory], &artworkError);
        if (!newFilename) return [self fail:artworkError error:error];
    }
    if (replaceArtwork) {
        record[@"artworkFilename"] = newFilename;
        record[@"artworkCleared"] = newFilename ? nil : @YES;
    }
    if (!record.count) { self.lastError = nil; return YES; }
    NSMutableDictionary *updated = [self.overrides mutableCopy];
    updated[trackID] = [record copy];
    if (![self commitOverrides:updated error:error]) {
        GMStoreRemoveArtwork([self artworkDirectory], newFilename);
        return NO;
    }
    [self applyToTrack:track];
    return YES;
}

- (BOOL)saveTrack:(GMTrack *)track title:(NSString *)title artist:(NSString *)artist
           album:(NSString *)album artwork:(UIImage *)artwork
  replaceArtwork:(BOOL)replaceArtwork error:(NSError **)error {
    if (![self readyWithError:error]) return NO;
    if (!GMTrackIdentifier(track)) return [self fail:GMEditsError(8, @"That song is no longer available.") error:error];
    NSString *cleanTitle = title ? GMStoreTrimmedString(title) : nil;
    NSString *cleanArtist = artist ? GMStoreTrimmedString(artist) : nil;
    NSString *cleanAlbum = album ? GMStoreTrimmedString(album) : nil;
    if ((title && (![title isKindOfClass:[NSString class]] || !GMEditsValidText(cleanTitle, NO))) ||
        (artist && (![artist isKindOfClass:[NSString class]] || !GMEditsValidText(cleanArtist, YES))) ||
        (album && (![album isKindOfClass:[NSString class]] || !GMEditsValidText(cleanAlbum, YES)))) {
        return [self fail:GMEditsError(9, @"Use a nonempty song title and up to 512 characters per field, each on one line.") error:error];
    }
    NSMutableDictionary<NSString *, NSString *> *fields = [NSMutableDictionary dictionary];
    if (title) fields[@"title"] = cleanTitle;
    if (artist) fields[@"artist"] = cleanArtist;
    if (album) {
        fields[@"album"] = cleanAlbum;
        if (![cleanAlbum isEqualToString:GMStoreTrimmedString(track.album)]) {
            fields[@"albumArtist"] = cleanArtist ?: GMStoreTrimmedString(track.artist);
        }
        // An unchanged album leaves its existing albumArtist override intact.
    }
    return [self saveFields:fields forTrack:track artwork:artwork replaceArtwork:replaceArtwork error:error];
}

- (BOOL)assignTrack:(GMTrack *)track toAlbum:(GMAlbum *)album
             tracks:(NSArray<GMTrack *> *)tracks error:(NSError **)error {
    if (![self readyWithError:error]) return NO;
    NSString *trackID = GMTrackIdentifier(track);
    if (!trackID || GMTrackIndexForIdentifier(tracks, trackID) == NSNotFound) {
        return [self fail:GMEditsError(8, @"That song is no longer available.") error:error];
    }
    if (![album isKindOfClass:[GMAlbum class]]) {
        return [self fail:GMEditsError(11, @"That album is no longer available.") error:error];
    }
    GMAlbum *target = nil;
    for (GMAlbum *candidate in GMAlbumsForTracks(tracks)) {
        if ([candidate.identifier isEqualToString:album.identifier]) { target = candidate; break; }
    }
    if (!target) return [self fail:GMEditsError(11, @"That album is no longer available.") error:error];
    if (!GMEditsValidText(target.title, YES) || !GMEditsValidText(target.artist, YES)) {
        return [self fail:GMEditsError(9, @"That album's name or artist exceeds the editing limit.") error:error];
    }
    // Setting both artist fields also handles two albums that share a title but
    // have different album artists. No title field is written or changed.
    NSDictionary *fields = @{@"album":target.title, @"artist":target.artist, @"albumArtist":target.artist};
    return [self saveFields:fields forTrack:track artwork:target.artwork replaceArtwork:YES error:error];
}

- (BOOL)saveImportedAlbumTracks:(NSArray<GMTrack *> *)tracks album:(NSString *)album
                         artist:(NSString *)artist artwork:(UIImage *)artwork
                          error:(NSError **)error {
    if (![self readyWithError:error]) return NO;
    NSString *name = GMStoreTrimmedString(album), *sharedArtist = GMStoreTrimmedString(artist);
    if (![tracks isKindOfClass:[NSArray class]] || !tracks.count || tracks.count > 500 ||
        !GMEditsValidText(name,NO) || !GMEditsValidText(sharedArtist,NO)) {
        return [self fail:GMEditsError(13,@"Choose up to 500 songs and a nonempty album name and artist, each on one line with at most 512 characters.") error:error];
    }
    if (self.overrides.count+tracks.count > GMEditsMaximumTracks)
        return [self fail:GMEditsError(10,@"Your saved song changes have reached the track limit.") error:error];
    NSMutableDictionary *records = [NSMutableDictionary dictionary];
    for (GMTrack *track in tracks) {
        NSString *identifier = GMTrackIdentifier(track);
        if (!identifier || track.demo || self.overrides[identifier] || records[identifier] ||
            !GMEditsValidText(track.title,NO) || track.trackNumber < 1 || track.trackNumber > 100000 ||
            track.discNumber < 1 || track.discNumber > 100000) {
            return [self fail:GMEditsError(14,@"The album contains an invalid song or a filename already used by saved song details. No album details were changed.") error:error];
        }
        records[identifier] = [@{@"title":track.title, @"artist":sharedArtist,
                                 @"album":name, @"albumArtist":sharedArtist,
                                 @"trackNumber":@(track.trackNumber), @"discNumber":@(track.discNumber)} mutableCopy];
    }
    NSString *newFilename = nil;
    if (artwork) {
        NSError *artworkError = nil;
        newFilename = GMStoreWriteArtwork(artwork,[self artworkDirectory],&artworkError);
        if (!newFilename) return [self fail:artworkError error:error];
    }
    NSMutableDictionary *updated = [self.overrides mutableCopy];
    for (NSString *identifier in records) {
        NSMutableDictionary *record = records[identifier];
        if (newFilename) record[@"artworkFilename"] = newFilename;
        else record[@"artworkCleared"] = @YES;
        updated[identifier] = [record copy];
    }
    if (![self commitOverrides:updated error:error]) {
        GMStoreRemoveArtwork([self artworkDirectory],newFilename);
        return NO;
    }
    self.cachedArtworkFilename = newFilename; self.cachedArtwork = artwork;
    // All tracks share the same decoded cover. Publishing happens only after
    // the single manifest transaction succeeds, never once per song.
    for (GMTrack *track in tracks) {
        track.artist = sharedArtist; track.album = name; track.albumArtist = sharedArtist;
        track.artwork = artwork;
    }
    return YES;
}

- (BOOL)hideTrack:(GMTrack *)track error:(NSError **)error {
    if (![self readyWithError:error]) return NO;
    NSString *trackID = GMTrackIdentifier(track);
    if (![trackID isEqualToString:@"demo:glass-study"]) {
        return [self fail:GMEditsError(12, @"Only the bundled demo is hidden this way. Imported songs use local-file deletion.") error:error];
    }
    if ([self isTrackHidden:track]) { self.lastError = nil; return YES; }
    NSMutableDictionary *record = [self.overrides[trackID] mutableCopy] ?: [NSMutableDictionary dictionary];
    record[@"hidden"] = @YES;
    NSMutableDictionary *updated = [self.overrides mutableCopy];
    updated[trackID] = [record copy];
    return [self commitOverrides:updated error:error];
}
@end
