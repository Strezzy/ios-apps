#ifndef MUSIC_ARTWORK_BACKDROP
#define MUSIC_ARTWORK_BACKDROP
// Local artwork analysis; no remote lookup, texture download, or per-frame CPU work.
@interface GMArtworkBackdrop : UIView
@property(nonatomic) BOOL groupedBackground;
- (void)setArtwork:(UIImage *)artwork animated:(BOOL)animated;
- (void)applyTheme;
@end
#endif
