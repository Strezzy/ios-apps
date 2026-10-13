// Whole-album import joins main.m after the shared PlayerController engine.
#ifndef MUSIC_ALBUM_IMPORT
#define MUSIC_ALBUM_IMPORT

@class PlayerController;

@interface GMAlbumImporter : NSObject
@property(nonatomic, readonly) BOOL busy;
- (instancetype)initWithPlayer:(PlayerController *)player;
// Presents the folder / multiple-song choice, then a draft album review.
// The shell retains the importer. Call from the main queue after any active
// search presentation has finished dismissing.
- (void)presentFromViewController:(UIViewController *)presenter;
@end

#endif
