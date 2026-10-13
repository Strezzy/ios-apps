#ifndef MUSIC_CD_INSPECTOR_H
#define MUSIC_CD_INSPECTOR_H

@class GMMusicShell;

// A native, full-screen browser around one high-quality local CD renderer.
// The grid can keep forwarding its original window-level hold until release.
@interface GMCDAlbumInspector : UIViewController <UIGestureRecognizerDelegate>
- (instancetype)initWithShell:(GMMusicShell *)shell albumIdentifier:(NSString *)identifier;
- (void)beginHeldInspection;
- (void)updateHeldInspectionTranslation:(CGPoint)translation;
- (void)finishHeldInspection;
- (void)reloadLibrary;
- (void)refreshPlaybackIndicators;
- (void)applyTheme;
@end

#endif
