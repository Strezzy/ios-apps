// Offline lyrics storage and the art-sized Now Playing lyrics panel.
#ifndef MUSIC_LYRICS
#define MUSIC_LYRICS

// Main-thread store. Missing files start empty. Unreadable/unsupported files
// block writes until a successful reload, preserving their original contents.
@interface GMLyricsStore : NSObject
@property(nonatomic, readonly, copy) NSURL *fileURL;
@property(nonatomic, readonly, strong) NSError *lastError;
- (instancetype)initWithFileURL:(NSURL *)fileURL;
- (BOOL)reloadWithError:(NSError **)error;
- (NSString *)lyricsForIdentifier:(NSString *)identifier;
// Stores the source text, including optional LRC tags. Empty text removes the
// entry. Commits atomically before updating the in-memory result.
- (BOOL)saveLyrics:(NSString *)lyrics forIdentifier:(NSString *)identifier error:(NSError **)error;
@end

@interface GMLyricsView : UIView
@property(nonatomic, weak) UIViewController *presenter;
@property(nonatomic, strong) GMLyricsStore *store;
@property(nonatomic, copy) NSString *songIdentifier;
@property(nonatomic, copy) NSString *songTitle;
- (void)configureForSongIdentifier:(NSString *)identifier title:(NSString *)title;
- (void)applyTheme;
// Plain scrollable lyrics; LRC timestamps are stripped for display. There is
// no synchronized highlighting. This hook is intentionally a no-op.
- (void)updatePlaybackTime:(NSTimeInterval)time;
@end

#endif
