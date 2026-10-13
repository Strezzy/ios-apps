// Shared native navigation, appearance, and playback contract.
#ifndef GLASS_MUSIC_LIBRARY_UI
#define GLASS_MUSIC_LIBRARY_UI
@class PlayerController, GMPlaylistStore, GMTrackEditsStore, GMAlbum, UIMenu;
UIColor *GMPageColor(void);
UIColor *GMGroupedColor(void);
UIColor *GMCardColor(void);
UIColor *GMPrimaryTextColor(void);
UIColor *GMSecondaryTextColor(void);
UIColor *GMSeparatorColor(void);
UIColor *GMCurrentAccent(void);
void GMStyleGlassButton(UIButton *button, BOOL prominent);
void GMApplyPageBackground(UIView *page, UITableView *table, BOOL grouped);
UIView *GMNewPageBackdrop(CGRect frame, BOOL grouped);
UIImage *GMArtworkFromURL(NSURL *url);
UIImage *GMArtworkFromData(NSData *data);
@interface GMMusicShell : UITabBarController
@property(strong) PlayerController *player;
@property(strong) GMPlaylistStore *playlistStore;
@property(strong) GMTrackEditsStore *editsStore;
@property(copy) NSArray<GMAlbum *> *albums;
@property NSInteger appearanceMode;
@property(strong) UIColor *accentColor;
- (void)reloadLibrary;
- (void)refreshPlaybackState;
- (void)presentNowPlaying;
- (void)presentNowPlayingFromCaseRect:(CGRect)sourceRect;
- (void)warmPlayerCase;
- (BOOL)canImportMusic;
- (void)importSongs;
- (void)importAlbum;
- (void)setAppearanceMode:(NSInteger)mode persist:(BOOL)persist;
- (void)setAccentColor:(UIColor *)color persist:(BOOL)persist;
- (void)applyTheme;
@end
@interface GMMusicShell (GMEditing)
- (UIMenu *)songMenuForIdentifier:(NSString *)identifier fromView:(UIView *)view;
- (UIMenu *)playlistMenuForIdentifier:(NSString *)identifier fromView:(UIView *)view;
- (void)confirmDeleteSongWithIdentifier:(NSString *)identifier;
- (void)confirmDeletePlaylistWithIdentifier:(NSString *)identifier;
- (void)confirmRemoveSongIdentifier:(NSString *)songIdentifier fromPlaylist:(NSString *)playlistIdentifier;
- (void)editSongWithIdentifier:(NSString *)identifier fromView:(UIView *)view;
- (void)editPlaylistWithIdentifier:(NSString *)identifier fromView:(UIView *)view;
- (void)chooseAlbumForSongWithIdentifier:(NSString *)identifier;
- (void)choosePlaylistForSongWithIdentifier:(NSString *)identifier;
@end
#endif
