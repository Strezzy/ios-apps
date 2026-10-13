// Local album grouping and playlist persistence. Import after the GMTrack
// declaration; MusicLibraryStore.m joins main.m's single translation unit.
#ifndef GLASS_MUSIC_LIBRARY_STORE
#define GLASS_MUSIC_LIBRARY_STORE

@class GMTrack, UIImage;

// Local filenames survive sandbox/container path changes. The bundled demo has
// its own reserved identifier. Invalid tracks produce nil / NSNotFound.
NSString *GMTrackIdentifier(GMTrack *track);
NSInteger GMTrackIndexForIdentifier(NSArray<GMTrack *> *tracks, NSString *identifier);

@interface GMAlbum : NSObject
@property(nonatomic, readonly, copy) NSString *identifier;
@property(nonatomic, readonly, copy) NSString *title;
@property(nonatomic, readonly, copy) NSString *artist;
@property(nonatomic, readonly, strong) UIImage *artwork;
@property(nonatomic, readonly, copy) NSArray<NSNumber *> *trackIndexes;
@end

// Groups by normalized album title + album artist (falling back to artist).
// Album order is alphabetical; tracks use disc/track numbers when available.
NSArray<GMAlbum *> *GMAlbumsForTracks(NSArray<GMTrack *> *tracks);

@interface GMPlaylist : NSObject
@property(nonatomic, readonly, copy) NSString *identifier;
@property(nonatomic, readonly, copy) NSString *name;
@property(nonatomic, readonly, copy) NSArray<NSString *> *trackIdentifiers;
// Custom cover only. nil lets the UI fall back to its songs' artwork.
@property(nonatomic, readonly, strong) UIImage *artwork;
@end

// Main-thread store. Pass Documents/MusicPlaylists.plist as fileURL. Init loads
// existing data; a missing file means an empty library. Inspect lastError for a
// load failure. A failed load prevents overwriting the unreadable original.
// Each successful mutation commits atomically before publishing new state.
@interface GMPlaylistStore : NSObject
@property(nonatomic, readonly, copy) NSURL *fileURL;
@property(nonatomic, readonly, copy) NSArray<GMPlaylist *> *playlists;
@property(nonatomic, readonly, strong) NSError *lastError;
- (instancetype)initWithFileURL:(NSURL *)fileURL;
- (BOOL)reloadWithError:(NSError **)error;
- (GMPlaylist *)createPlaylistWithName:(NSString *)name error:(NSError **)error;
- (BOOL)renamePlaylist:(NSString *)identifier name:(NSString *)name error:(NSError **)error;
// NO preserves custom art; YES with nil removes custom art. Name and cover
// commit together, and failed writes preserve the previous playlist and image.
- (BOOL)updatePlaylist:(NSString *)identifier name:(NSString *)name artwork:(UIImage *)artwork
       replaceArtwork:(BOOL)replaceArtwork error:(NSError **)error;
- (BOOL)deletePlaylist:(NSString *)identifier error:(NSError **)error;
- (BOOL)addTracks:(NSArray<GMTrack *> *)tracks toPlaylist:(NSString *)identifier error:(NSError **)error;
- (BOOL)removeTrackIdentifier:(NSString *)trackIdentifier fromPlaylist:(NSString *)identifier error:(NSError **)error;
// Missing audio is skipped without discarding its saved identifier. Reimporting
// that filename restores its position; playlist edits never delete audio files.
- (NSArray<NSNumber *> *)trackIndexesForPlaylist:(NSString *)identifier tracks:(NSArray<GMTrack *> *)tracks;
@end

#endif
