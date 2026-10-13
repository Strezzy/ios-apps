// Modified app-local adaptation of Cask 3 by Ryan Nair (Apache License 2.0),
// inspired by the original Cask by Ryan Petrich. See the .m modification notice.
#ifndef MUSIC_SCROLL_ANIMATIONS
#define MUSIC_SCROLL_ANIMATIONS

NSArray<NSString *> *GMScrollPresetIdentifiers(void);
NSString *GMScrollPresetName(NSString *identifier);
NSString *GMScrollPresetDetail(NSString *identifier);

// Place only ordinary row artwork/text in contentView. Native glass, swipe
// surfaces, UIKit's cell container, and the tab accessory remain outside it.
// Preview calls deliberately ignore the enable setting, but honor Reduce Motion.
@interface GMScrollAnimationView : UIView
@property(nonatomic, readonly, strong) UIView *contentView;
- (void)animateWithPreset:(NSString *)presetIdentifier;
- (void)resetScrollAnimation;
@end

#endif
