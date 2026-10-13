// Local overrides applied after embedded metadata has been read. Audio files
// and their stable filename-based track identifiers are never renamed here.
#ifndef MUSIC_EDITS_STORE
#define MUSIC_EDITS_STORE

#import "MusicLibraryStore.h"

// Main-thread store. Use Documents/MusicEdits.plist. Its images are UUID-named
// JPEG files in the sibling MusicEditsArtwork directory. A corrupt manifest
// remains untouched and blocks mutations until a successful reload.
@interface GMTrackEditsStore : NSObject
@property(nonatomic, readonly, copy) NSURL *fileURL;
@property(nonatomic, readonly, strong) NSError *lastError;
- (instancetype)initWithFileURL:(NSURL *)fileURL;
- (BOOL)reloadWithError:(NSError **)error;
- (void)applyToTrack:(GMTrack *)track;
// Hides the bundled demo without trying to modify the signed app bundle.
// Imported audio deletion is handled separately by the player/file manager.
- (BOOL)isTrackHidden:(GMTrack *)track;
- (BOOL)hideTrack:(GMTrack *)track error:(NSError **)error;
// nil text fields preserve their existing override; nonnil fields are saved
// independently. Title must be nonempty; artist and album may be empty.
// NO preserves artwork. YES with nil explicitly clears embedded/custom art.
// UIImage input must be at most 1200 pixels per side. Passed tracks are updated
// only after the manifest has committed successfully.
- (BOOL)saveTrack:(GMTrack *)track title:(NSString *)title artist:(NSString *)artist
           album:(NSString *)album artwork:(UIImage *)artwork
  replaceArtwork:(BOOL)replaceArtwork error:(NSError **)error;
// Preserves title; copies the target's album title, album artist into both
// artist fields, and cover (including an explicit clear for an unillustrated
// album). Resolve the album against the current tracks before assigning it.
- (BOOL)assignTrack:(GMTrack *)track toAlbum:(GMAlbum *)album
             tracks:(NSArray<GMTrack *> *)tracks error:(NSError **)error;
// Atomically adds one imported album's overrides. Every track must be a new,
// non-demo identifier without an existing override, with a valid title and
// positive track/disc order. A single bounded cover is shared by the batch.
// The caller stages/moves audio separately and rolls those copies back if this
// commit fails. Existing records and live tracks remain intact on failure.
- (BOOL)saveImportedAlbumTracks:(NSArray<GMTrack *> *)tracks album:(NSString *)album
                         artist:(NSString *)artist artwork:(UIImage *)artwork
                          error:(NSError **)error;
@end

#endif
