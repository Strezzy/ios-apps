// App-local scrolling animation preferences and the native style picker.
#ifndef MUSIC_SCROLL_SETTINGS
#define MUSIC_SCROLL_SETTINGS

extern NSString *const GMScrollSettingsDidChangeNotification;

@interface GMScrollSettings : NSObject
+ (instancetype)sharedSettings;
@property(nonatomic, readonly) BOOL enabled;
@property(nonatomic, readonly, copy) NSString *presetIdentifier;
@property(nonatomic, readonly, strong) NSError *lastError;
- (BOOL)setAnimationsEnabled:(BOOL)enabled error:(NSError **)error;
- (BOOL)selectPresetIdentifier:(NSString *)identifier error:(NSError **)error;
@end

// Embedded directly in the existing Settings table. The native menu opens
// from the style button; its sibling preview never contains a glass control.
@interface GMScrollStyleCell : UITableViewCell
@property(nonatomic, weak) UIViewController *presenter;
- (void)refreshStyle;
- (void)applyTheme;
@end

@interface GMScrollCreditsController : UIViewController
- (void)applyTheme;
@end

#endif
