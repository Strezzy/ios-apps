// Compact current-song accessory. Import after UIKit or MiniSDK.
#ifndef MUSIC_PLAYBACK_INDICATOR
#define MUSIC_PLAYBACK_INDICATOR

@interface GMPlaybackIndicatorView : UIView
// Suggested frame and intrinsic size: 22 x 22 points. Uses inherited tintColor.
// Repeated calls with the same state preserve the current animation phase.
- (void)configurePlaying:(BOOL)playing;
// Reuse hook: stops motion, hides the accessory, and clears accessibility state.
- (void)reset;
@end

#endif
