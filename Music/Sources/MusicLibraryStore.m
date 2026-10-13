// This implementation is imported into main.m after GMTrack is declared.
#import "MusicLibraryStore.h"

// Implemented by MusicArtwork.m; ImageIO creates a bounded thumbnail before
// UIImage decoding. The declaration also supports the isolated model compile.
extern UIImage *GMArtworkFromData(NSData *data);

#if !__has_include(<Foundation/Foundation.h>)
// Only the Linux cross-build needs these public Foundation declarations.
@interface NSCharacterSet (GMLibraryStoreCharacters)
+ (NSCharacterSet *)whitespaceAndNewlineCharacterSet;
+ (NSCharacterSet *)controlCharacterSet;
@end
@interface NSUUID : NSObject
+ (NSUUID *)UUID;
- (instancetype)initWithUUIDString:(NSString *)string;
@property(nonatomic, readonly, copy) NSString *UUIDString;
@end
@interface NSPropertyListSerialization : NSObject
+ (id)propertyListWithData:(NSData *)data options:(NSUInteger)options format:(NSUInteger *)format error:(NSError **)error;
+ (NSData *)dataWithPropertyList:(id)plist format:(NSUInteger)format options:(NSUInteger)options error:(NSError **)error;
@end
@interface NSString (GMLibraryStoreStrings)
- (NSString *)stringByTrimmingCharactersInSet:(NSCharacterSet *)set;
- (NSString *)substringFromIndex:(NSUInteger)index;
- (NSRange)rangeOfString:(NSString *)string;
- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)set;
- (NSInteger)compare:(NSString *)other;
@end
@interface NSArray<ObjectType> (GMLibraryStoreSorting)
- (NSArray<ObjectType> *)sortedArrayUsingComparator:(NSInteger (^)(ObjectType a, ObjectType b))comparator;
@end
@interface NSMutableArray<ObjectType> (GMLibraryStoreReplacement)
- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(ObjectType)object;
@end
@interface NSDictionary<KeyType, ObjectType> (GMLibraryStoreCounts)
@property(nonatomic, readonly) NSUInteger count;
@end
@interface NSData (GMLibraryStoreData)
@property(nonatomic, readonly) NSUInteger length;
+ (instancetype)dataWithContentsOfURL:(NSURL *)url options:(NSUInteger)options error:(NSError **)error;
- (BOOL)writeToURL:(NSURL *)url options:(NSUInteger)options error:(NSError **)error;
@end
@interface NSURL (GMLibraryStoreURLs)
@property(nonatomic, readonly) BOOL isFileURL;
@property(nonatomic, readonly, copy) NSURL *URLByDeletingLastPathComponent;
@end
@interface NSError (GMLibraryStoreErrors)
+ (instancetype)errorWithDomain:(NSString *)domain code:(NSInteger)code userInfo:(NSDictionary *)userInfo;
@end
extern NSString *const NSLocalizedDescriptionKey;
#endif

static const NSUInteger GMStoreMaximumPlaylists = 512;
static const NSUInteger GMStoreMaximumPlaylistTracks = 20000;
static const NSUInteger GMStoreMaximumNameLength = 120;
static const NSUInteger GMStoreMaximumFileBytes = 4 * 1024 * 1024;
static const NSUInteger GMStoreMaximumArtworkBytes = 3 * 1024 * 1024;
static const CGFloat GMStoreMaximumArtworkPixels = 1200;

static NSString *GMStoreTrimmedString(id value) {
    if (![value isKindOfClass:[NSString class]]) return @"";
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL GMStoreValidName(NSString *name) {
    return name.length > 0 && name.length <= GMStoreMaximumNameLength &&
        [name rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location == NSNotFound;
}

static BOOL GMStoreValidTrackIdentifier(id value) {
    if (![value isKindOfClass:[NSString class]]) return NO;
    NSString *identifier = value;
    if ([identifier isEqualToString:@"demo:glass-study"]) return YES;
    if (![identifier hasPrefix:@"local:"] || identifier.length <= 6 || identifier.length > 1030) return NO;
    NSString *filename = [identifier substringFromIndex:6];
    return ![filename isEqualToString:@"."] && ![filename isEqualToString:@".."] &&
        [filename rangeOfString:@"/"].location == NSNotFound;
}

// Shared by MusicEditsStore.m in main.m's single translation unit. The manifest
// contains only UUID basenames, never arbitrary paths. Replacements get a new
// filename so an unsuccessful manifest write cannot damage the previous cover.
static BOOL GMStoreValidArtworkFilename(id value) {
    if (![value isKindOfClass:[NSString class]]) return NO;
    NSString *filename = value;
    if (filename.length != 40 || ![filename.pathExtension isEqualToString:@"jpg"] ||
        ![filename.lastPathComponent isEqualToString:filename]) return NO;
    return [[NSUUID alloc] initWithUUIDString:filename.stringByDeletingPathExtension] != nil;
}

static BOOL GMStoreValidArtworkImage(UIImage *image) {
    if (![image isKindOfClass:[UIImage class]]) return NO;
    CGFloat width = image.size.width * image.scale, height = image.size.height * image.scale;
    // The comparisons also reject zero, negative, nonfinite, and NaN sizes.
    return width > 0 && height > 0 && width <= GMStoreMaximumArtworkPixels && height <= GMStoreMaximumArtworkPixels;
}

static NSError *GMStoreArtworkError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:@"com.billy.glassmusic.artwork" code:code
                          userInfo:@{NSLocalizedDescriptionKey:description}];
}

static UIImage *GMStoreReadArtwork(NSURL *directory, NSString *filename) {
    if (!directory.isFileURL || !GMStoreValidArtworkFilename(filename)) return nil;
    NSData *data = [NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:filename] options:1 error:NULL];
    if (!data.length || data.length > GMStoreMaximumArtworkBytes) return nil;
    UIImage *image = GMArtworkFromData(data);
    return GMStoreValidArtworkImage(image) ? image : nil;
}

static void GMStoreRemoveArtwork(NSURL *directory, NSString *filename) {
    if (directory.isFileURL && GMStoreValidArtworkFilename(filename)) {
        [[NSFileManager defaultManager] removeItemAtURL:[directory URLByAppendingPathComponent:filename] error:NULL];
    }
}

static NSString *GMStoreWriteArtwork(UIImage *image, NSURL *directory, NSError **error) {
    if (error) *error = nil;
    if (!GMStoreValidArtworkImage(image)) {
        if (error) *error = GMStoreArtworkError(1, @"Choose artwork no larger than 1200 pixels on each side.");
        return nil;
    }
    NSData *data = UIImageJPEGRepresentation(image, .88);
    if (!data.length || data.length > GMStoreMaximumArtworkBytes) {
        if (error) *error = GMStoreArtworkError(2, @"That artwork couldn't be saved within the 3 MB image limit.");
        return nil;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    if (!directory.isFileURL ||
        ![fm createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    for (NSUInteger attempt = 0; attempt < 4; attempt++) {
        NSString *filename = [[NSUUID UUID].UUIDString stringByAppendingString:@".jpg"];
        NSURL *destination = [directory URLByAppendingPathComponent:filename];
        if ([fm fileExistsAtPath:destination.path]) continue;
        if (![data writeToURL:destination options:1 error:error]) return nil;
        return filename;
    }
    if (error) *error = GMStoreArtworkError(3, @"A unique artwork file couldn't be created. Try again.");
    return nil;
}

NSString *GMTrackIdentifier(GMTrack *track) {
    if (![track isKindOfClass:[GMTrack class]]) return nil;
    if (track.demo) return @"demo:glass-study";
    NSString *filename = track.url.lastPathComponent;
    if (!filename.length) return nil;
    NSString *identifier = [@"local:" stringByAppendingString:filename];
    return GMStoreValidTrackIdentifier(identifier) ? identifier : nil;
}

NSInteger GMTrackIndexForIdentifier(NSArray<GMTrack *> *tracks, NSString *identifier) {
    if (![tracks isKindOfClass:[NSArray class]] || !GMStoreValidTrackIdentifier(identifier)) return NSNotFound;
    for (NSUInteger i = 0; i < tracks.count; i++) {
        if ([GMTrackIdentifier(tracks[i]) isEqualToString:identifier]) return (NSInteger)i;
    }
    return NSNotFound;
}

@interface GMAlbum ()
@property(nonatomic, readwrite, copy) NSString *identifier;
@property(nonatomic, readwrite, copy) NSString *title;
@property(nonatomic, readwrite, copy) NSString *artist;
@property(nonatomic, readwrite, strong) UIImage *artwork;
@property(nonatomic, readwrite, copy) NSArray<NSNumber *> *trackIndexes;
@end
@implementation GMAlbum @end

NSArray<GMAlbum *> *GMAlbumsForTracks(NSArray<GMTrack *> *tracks) {
    if (![tracks isKindOfClass:[NSArray class]]) return [NSArray array];
    NSMutableDictionary<NSString *, GMAlbum *> *groups = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *indexes = [NSMutableDictionary dictionary];
    NSMutableArray<GMAlbum *> *albums = [NSMutableArray array];
    for (NSUInteger i = 0; i < tracks.count; i++) {
        GMTrack *track = tracks[i];
        if (![track isKindOfClass:[GMTrack class]]) continue;
        NSString *title = GMStoreTrimmedString(track.album);
        if (!title.length) title = @"Unknown Album";
        NSString *artist = GMStoreTrimmedString(track.albumArtist);
        if (!artist.length) artist = GMStoreTrimmedString(track.artist);
        if (!artist.length) artist = @"Unknown Artist";
        NSString *foldedArtist = artist.lowercaseString;
        NSString *key = [NSString stringWithFormat:@"%lu:%@%@", (unsigned long)foldedArtist.length,
                         foldedArtist, title.lowercaseString];
        GMAlbum *album = groups[key];
        if (!album) {
            album = [GMAlbum new];
            album.identifier = key; album.title = title; album.artist = artist;
            groups[key] = album; indexes[key] = [NSMutableArray array];
            [albums addObject:album];
        }
        if (!album.artwork && track.artwork) album.artwork = track.artwork;
        [indexes[key] addObject:@(i)];
    }
    for (GMAlbum *album in albums) {
        album.trackIndexes = [indexes[album.identifier] sortedArrayUsingComparator:^NSInteger(NSNumber *a, NSNumber *b) {
            GMTrack *left = tracks[a.unsignedIntegerValue], *right = tracks[b.unsignedIntegerValue];
            NSInteger leftDisc = left.discNumber > 0 ? left.discNumber : 1;
            NSInteger rightDisc = right.discNumber > 0 ? right.discNumber : 1;
            if (leftDisc != rightDisc) return leftDisc < rightDisc ? -1 : 1;
            NSInteger leftNumber = left.trackNumber > 0 ? left.trackNumber : NSNotFound;
            NSInteger rightNumber = right.trackNumber > 0 ? right.trackNumber : NSNotFound;
            if (leftNumber != rightNumber) return leftNumber < rightNumber ? -1 : 1;
            NSString *leftTitle = GMStoreTrimmedString(left.title);
            NSString *rightTitle = GMStoreTrimmedString(right.title);
            NSInteger comparison = [leftTitle localizedCaseInsensitiveCompare:rightTitle];
            if (comparison) return comparison;
            return a.unsignedIntegerValue < b.unsignedIntegerValue ? -1 :
                (a.unsignedIntegerValue > b.unsignedIntegerValue ? 1 : 0);
        }];
    }
    return [albums sortedArrayUsingComparator:^NSInteger(GMAlbum *a, GMAlbum *b) {
        NSInteger comparison = [a.title localizedCaseInsensitiveCompare:b.title];
        if (!comparison) comparison = [a.artist localizedCaseInsensitiveCompare:b.artist];
        if (!comparison) comparison = [a.identifier compare:b.identifier];
        return comparison;
    }];
}

@interface GMPlaylist ()
@property(nonatomic, readwrite, copy) NSString *identifier;
@property(nonatomic, readwrite, copy) NSString *name;
@property(nonatomic, readwrite, copy) NSArray<NSString *> *trackIdentifiers;
@property(nonatomic, copy) NSString *artworkFilename;
@property(nonatomic, copy) NSURL *artworkDirectoryURL;
@end
@implementation GMPlaylist
- (UIImage *)artwork {
    // Decode on demand instead of retaining every full cover when a large
    // playlist manifest loads. Missing/invalid images use the UI's fallback.
    return GMStoreReadArtwork(self.artworkDirectoryURL, self.artworkFilename);
}
@end

static GMPlaylist *GMStorePlaylist(NSString *identifier, NSString *name, NSArray<NSString *> *trackIdentifiers,
                                  NSString *artworkFilename, NSURL *artworkDirectoryURL) {
    GMPlaylist *playlist = [GMPlaylist new];
    playlist.identifier = identifier; playlist.name = name; playlist.trackIdentifiers = trackIdentifiers;
    playlist.artworkFilename = artworkFilename; playlist.artworkDirectoryURL = artworkDirectoryURL;
    return playlist;
}

static NSError *GMStoreError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:@"com.billy.glassmusic.playlists" code:code
                          userInfo:@{NSLocalizedDescriptionKey:description}];
}

@interface GMPlaylistStore ()
@property(nonatomic, readwrite, copy) NSURL *fileURL;
@property(nonatomic, readwrite, copy) NSArray<GMPlaylist *> *playlists;
@property(nonatomic, readwrite, strong) NSError *lastError;
@property(nonatomic) BOOL loadedSuccessfully;
- (BOOL)fail:(NSError *)issue error:(NSError **)error;
- (BOOL)readyWithError:(NSError **)error;
- (BOOL)commitPlaylists:(NSArray<GMPlaylist *> *)playlists error:(NSError **)error;
- (NSInteger)indexForPlaylist:(NSString *)identifier;
- (NSString *)validatedName:(NSString *)name excludingPlaylist:(NSString *)identifier error:(NSError **)error;
- (NSURL *)artworkDirectory;
@end

@implementation GMPlaylistStore
- (instancetype)initWithFileURL:(NSURL *)fileURL {
    self = [super init];
    if (self) {
        self.fileURL = fileURL; self.playlists = [NSArray array];
        [self reloadWithError:NULL];
    }
    return self;
}

- (BOOL)fail:(NSError *)issue error:(NSError **)error {
    self.lastError = issue ?: GMStoreError(1, @"Your playlists couldn't be saved.");
    if (error) *error = self.lastError;
    return NO;
}

- (BOOL)readyWithError:(NSError **)error {
    if (error) *error = nil;
    if (!self.loadedSuccessfully) return [self fail:self.lastError ?: GMStoreError(2,
        @"Your saved playlists couldn't be read. They haven't been changed.") error:error];
    return YES;
}

- (NSURL *)artworkDirectory {
    return [self.fileURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"MusicPlaylistArtwork"];
}

- (BOOL)reloadWithError:(NSError **)error {
    if (error) *error = nil;
    self.loadedSuccessfully = NO;
    if (!self.fileURL.isFileURL || !self.fileURL.path.length) {
        return [self fail:GMStoreError(3, @"Playlist storage is unavailable.") error:error];
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:self.fileURL.path]) {
        self.playlists = [NSArray array]; self.loadedSuccessfully = YES; self.lastError = nil;
        return YES;
    }
    NSError *readError = nil;
    // NSDataReadingMappedIfSafe avoids eagerly copying a large unexpected file.
    NSData *data = [NSData dataWithContentsOfURL:self.fileURL options:1 error:&readError];
    if (!data) return [self fail:readError error:error];
    if (!data.length || data.length > GMStoreMaximumFileBytes) {
        return [self fail:GMStoreError(4, @"The saved playlist file is empty or too large. It hasn't been changed.") error:error];
    }
    id document = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&readError];
    if (![document isKindOfClass:[NSDictionary class]]) {
        return [self fail:readError ?: GMStoreError(5, @"Your saved playlists couldn't be read. They haven't been changed.") error:error];
    }
    id version = document[@"formatVersion"], entries = document[@"playlists"];
    if (![version isKindOfClass:[NSNumber class]] || [version doubleValue] != 1 ||
        ![entries isKindOfClass:[NSArray class]] || [entries count] > GMStoreMaximumPlaylists) {
        return [self fail:GMStoreError(6, @"The saved playlist format isn't supported. It hasn't been changed.") error:error];
    }
    NSMutableArray<GMPlaylist *> *loaded = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSNumber *> *seenIDs = [NSMutableDictionary dictionary];
    for (id entry in entries) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            return [self fail:GMStoreError(7, @"A saved playlist is invalid. Your playlist file hasn't been changed.") error:error];
        }
        id rawID = entry[@"identifier"], rawName = entry[@"name"], rawTracks = entry[@"trackIdentifiers"];
        id rawArtwork = entry[@"artworkFilename"];
        if (![rawID isKindOfClass:[NSString class]] || [rawID length] != 36 ||
            ![rawName isKindOfClass:[NSString class]] || [rawName length] > GMStoreMaximumNameLength ||
            ![rawTracks isKindOfClass:[NSArray class]] || [rawTracks count] > GMStoreMaximumPlaylistTracks ||
            (rawArtwork && !GMStoreValidArtworkFilename(rawArtwork))) {
            return [self fail:GMStoreError(7, @"A saved playlist is invalid. Your playlist file hasn't been changed.") error:error];
        }
        NSString *identifier = [[NSUUID alloc] initWithUUIDString:rawID].UUIDString;
        NSString *name = GMStoreTrimmedString(rawName);
        if (!identifier || seenIDs[identifier] || !GMStoreValidName(name)) {
            return [self fail:GMStoreError(7, @"A saved playlist is invalid. Your playlist file hasn't been changed.") error:error];
        }
        for (GMPlaylist *other in loaded) {
            if ([name localizedCaseInsensitiveCompare:other.name] == 0) {
                return [self fail:GMStoreError(8, @"Two saved playlists have the same name. Your playlist file hasn't been changed.") error:error];
            }
        }
        seenIDs[identifier] = @YES;
        NSMutableArray<NSString *> *trackIDs = [NSMutableArray array];
        NSMutableDictionary<NSString *, NSNumber *> *seenTracks = [NSMutableDictionary dictionary];
        for (id trackID in rawTracks) {
            if (!GMStoreValidTrackIdentifier(trackID) || seenTracks[trackID]) {
                return [self fail:GMStoreError(7, @"A saved playlist contains invalid or repeated tracks. Your playlist file hasn't been changed.") error:error];
            }
            seenTracks[trackID] = @YES;
            [trackIDs addObject:trackID];
        }
        [loaded addObject:GMStorePlaylist(identifier, name, trackIDs, rawArtwork, [self artworkDirectory])];
    }
    self.playlists = loaded; self.loadedSuccessfully = YES; self.lastError = nil;
    return YES;
}

- (BOOL)commitPlaylists:(NSArray<GMPlaylist *> *)playlists error:(NSError **)error {
    if (![self readyWithError:error]) return NO;
    NSMutableArray *entries = [NSMutableArray array];
    for (GMPlaylist *playlist in playlists) {
        NSMutableDictionary *entry = [@{@"identifier":playlist.identifier, @"name":playlist.name,
                                       @"trackIdentifiers":playlist.trackIdentifiers} mutableCopy];
        if (playlist.artworkFilename) entry[@"artworkFilename"] = playlist.artworkFilename;
        [entries addObject:entry];
    }
    NSError *writeError = nil;
    // NSPropertyListBinaryFormat_v1_0; NSDataWritingAtomic writes a temporary
    // sibling and replaces the destination only after a successful full write.
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:@{@"formatVersion":@1, @"playlists":entries}
                                                              format:200 options:0 error:&writeError];
    if (!data) return [self fail:writeError error:error];
    if (data.length > GMStoreMaximumFileBytes) {
        return [self fail:GMStoreError(9, @"Your playlists have reached the available size limit.") error:error];
    }
    if (![[NSFileManager defaultManager] createDirectoryAtURL:self.fileURL.URLByDeletingLastPathComponent
                                 withIntermediateDirectories:YES attributes:nil error:&writeError] ||
        ![data writeToURL:self.fileURL options:1 error:&writeError]) {
        return [self fail:writeError error:error];
    }
    NSArray<GMPlaylist *> *previous = self.playlists;
    self.playlists = playlists; self.lastError = nil;
    NSMutableDictionary *referencedArtwork = [NSMutableDictionary dictionary];
    for (GMPlaylist *playlist in playlists) {
        if (playlist.artworkFilename) referencedArtwork[playlist.artworkFilename] = @YES;
    }
    // Delete only superseded images, only after a successful manifest commit,
    // and only when no remaining playlist references the same filename.
    for (GMPlaylist *playlist in previous) {
        if (playlist.artworkFilename && !referencedArtwork[playlist.artworkFilename])
            GMStoreRemoveArtwork([self artworkDirectory], playlist.artworkFilename);
    }
    return YES;
}

- (NSInteger)indexForPlaylist:(NSString *)identifier {
    if (![identifier isKindOfClass:[NSString class]]) return NSNotFound;
    for (NSUInteger i = 0; i < self.playlists.count; i++) {
        if ([self.playlists[i].identifier isEqualToString:identifier]) return (NSInteger)i;
    }
    return NSNotFound;
}

- (NSString *)validatedName:(NSString *)name excludingPlaylist:(NSString *)identifier error:(NSError **)error {
    NSString *trimmed = GMStoreTrimmedString(name);
    if (!GMStoreValidName(trimmed)) {
        [self fail:GMStoreError(10, @"Use a playlist name with 1–120 characters on one line.") error:error];
        return nil;
    }
    for (GMPlaylist *playlist in self.playlists) {
        if ([playlist.identifier isEqualToString:identifier]) continue;
        if ([trimmed localizedCaseInsensitiveCompare:playlist.name] == 0) {
            [self fail:GMStoreError(11, @"A playlist with that name already exists.") error:error];
            return nil;
        }
    }
    return trimmed;
}

- (GMPlaylist *)createPlaylistWithName:(NSString *)name error:(NSError **)error {
    if (![self readyWithError:error]) return nil;
    NSString *validName = [self validatedName:name excludingPlaylist:nil error:error];
    if (!validName) return nil;
    if (self.playlists.count >= GMStoreMaximumPlaylists) {
        [self fail:GMStoreError(12, @"You've reached the playlist limit.") error:error]; return nil;
    }
    GMPlaylist *playlist = GMStorePlaylist([NSUUID UUID].UUIDString, validName, [NSArray array], nil, [self artworkDirectory]);
    NSMutableArray *updated = [self.playlists mutableCopy]; [updated addObject:playlist];
    return [self commitPlaylists:updated error:error] ? playlist : nil;
}

- (BOOL)renamePlaylist:(NSString *)identifier name:(NSString *)name error:(NSError **)error {
    return [self updatePlaylist:identifier name:name artwork:nil replaceArtwork:NO error:error];
}

- (BOOL)updatePlaylist:(NSString *)identifier name:(NSString *)name artwork:(UIImage *)artwork
       replaceArtwork:(BOOL)replaceArtwork error:(NSError **)error {
    if (![self readyWithError:error]) return NO;
    NSInteger index = [self indexForPlaylist:identifier];
    if (index == NSNotFound) return [self fail:GMStoreError(13, @"That playlist is no longer available.") error:error];
    NSString *validName = [self validatedName:name excludingPlaylist:identifier error:error];
    if (!validName) return NO;
    GMPlaylist *old = self.playlists[index];
    if (!replaceArtwork && [validName isEqualToString:old.name]) { self.lastError = nil; return YES; }
    NSString *newFilename = nil;
    if (replaceArtwork && artwork) {
        NSError *artworkError = nil;
        newFilename = GMStoreWriteArtwork(artwork, [self artworkDirectory], &artworkError);
        if (!newFilename) return [self fail:artworkError error:error];
    }
    NSString *filename = replaceArtwork ? newFilename : old.artworkFilename;
    GMPlaylist *replacement = GMStorePlaylist(old.identifier, validName, old.trackIdentifiers, filename, [self artworkDirectory]);
    NSMutableArray *updated = [self.playlists mutableCopy];
    [updated replaceObjectAtIndex:(NSUInteger)index withObject:replacement];
    if ([self commitPlaylists:updated error:error]) return YES;
    GMStoreRemoveArtwork([self artworkDirectory], newFilename);
    return NO;
}

- (BOOL)deletePlaylist:(NSString *)identifier error:(NSError **)error {
    if (![self readyWithError:error]) return NO;
    NSInteger index = [self indexForPlaylist:identifier];
    if (index == NSNotFound) return [self fail:GMStoreError(13, @"That playlist is no longer available.") error:error];
    NSMutableArray *updated = [self.playlists mutableCopy]; [updated removeObjectAtIndex:(NSUInteger)index];
    return [self commitPlaylists:updated error:error];
}

- (BOOL)addTracks:(NSArray<GMTrack *> *)tracks toPlaylist:(NSString *)identifier error:(NSError **)error {
    if (![self readyWithError:error]) return NO;
    NSInteger index = [self indexForPlaylist:identifier];
    if (index == NSNotFound) return [self fail:GMStoreError(13, @"That playlist is no longer available.") error:error];
    if (![tracks isKindOfClass:[NSArray class]] || tracks.count > GMStoreMaximumPlaylistTracks) {
        return [self fail:GMStoreError(14, @"Choose a smaller selection of tracks to add.") error:error];
    }
    GMPlaylist *old = self.playlists[index];
    NSMutableArray<NSString *> *trackIDs = [old.trackIdentifiers mutableCopy];
    NSMutableDictionary<NSString *, NSNumber *> *seen = [NSMutableDictionary dictionary];
    for (NSString *trackID in trackIDs) seen[trackID] = @YES;
    for (GMTrack *track in tracks) {
        NSString *trackID = GMTrackIdentifier(track);
        if (!trackID) return [self fail:GMStoreError(15, @"One of those tracks is no longer available.") error:error];
        if (seen[trackID]) continue;
        seen[trackID] = @YES; [trackIDs addObject:trackID];
        if (trackIDs.count > GMStoreMaximumPlaylistTracks) {
            return [self fail:GMStoreError(16, @"That playlist has reached its track limit.") error:error];
        }
    }
    if (trackIDs.count == old.trackIdentifiers.count) { self.lastError = nil; return YES; }
    GMPlaylist *replacement = GMStorePlaylist(old.identifier, old.name, trackIDs, old.artworkFilename, old.artworkDirectoryURL);
    NSMutableArray *updated = [self.playlists mutableCopy];
    [updated replaceObjectAtIndex:(NSUInteger)index withObject:replacement];
    return [self commitPlaylists:updated error:error];
}

- (BOOL)removeTrackIdentifier:(NSString *)trackIdentifier fromPlaylist:(NSString *)identifier error:(NSError **)error {
    if (![self readyWithError:error]) return NO;
    NSInteger index = [self indexForPlaylist:identifier];
    if (index == NSNotFound) return [self fail:GMStoreError(13, @"That playlist is no longer available.") error:error];
    if (!GMStoreValidTrackIdentifier(trackIdentifier)) {
        return [self fail:GMStoreError(15, @"That track is no longer available.") error:error];
    }
    GMPlaylist *old = self.playlists[index];
    NSMutableArray<NSString *> *trackIDs = [NSMutableArray array];
    for (NSString *saved in old.trackIdentifiers) {
        if (![saved isEqualToString:trackIdentifier]) [trackIDs addObject:saved];
    }
    if (trackIDs.count == old.trackIdentifiers.count) { self.lastError = nil; return YES; }
    GMPlaylist *replacement = GMStorePlaylist(old.identifier, old.name, trackIDs, old.artworkFilename, old.artworkDirectoryURL);
    NSMutableArray *updated = [self.playlists mutableCopy];
    [updated replaceObjectAtIndex:(NSUInteger)index withObject:replacement];
    return [self commitPlaylists:updated error:error];
}

- (NSArray<NSNumber *> *)trackIndexesForPlaylist:(NSString *)identifier tracks:(NSArray<GMTrack *> *)tracks {
    NSInteger index = [self indexForPlaylist:identifier];
    if (index == NSNotFound || ![tracks isKindOfClass:[NSArray class]]) return [NSArray array];
    NSMutableDictionary<NSString *, NSNumber *> *currentIndexes = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < tracks.count; i++) {
        NSString *trackID = GMTrackIdentifier(tracks[i]);
        if (trackID && !currentIndexes[trackID]) currentIndexes[trackID] = @(i);
    }
    NSMutableArray<NSNumber *> *resolved = [NSMutableArray array];
    for (NSString *trackID in self.playlists[index].trackIdentifiers) {
        NSNumber *current = currentIndexes[trackID];
        if (current) [resolved addObject:current];
    }
    return [resolved copy];
}
@end
