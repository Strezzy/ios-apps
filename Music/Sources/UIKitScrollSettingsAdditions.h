// Narrow public UIKit declarations for the Linux arm64 build.
#ifndef MUSIC_UIKIT_SCROLL_SETTINGS_ADDITIONS
#define MUSIC_UIKIT_SCROLL_SETTINGS_ADDITIONS

@interface UISwitch : UIControl
@property(nonatomic, getter=isOn) BOOL on;
@property(nonatomic, strong) UIColor *onTintColor;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
@end

#endif
