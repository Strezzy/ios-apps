// Local font selection/imports and the app's bundled alternate-icon picker.
#ifndef MUSIC_PERSONALIZATION
#define MUSIC_PERSONALIZATION

@class GMPersonalizationStore;
// Call once before constructing app text. Imported fonts are registered for
// this process again at launch; a missing/unavailable choice falls back safely.
void GMLoadPersonalization(void);
GMPersonalizationStore *GMSharedPersonalization(void);
UIFont *GMAppFont(CGFloat size, CGFloat weight);
void GMApplyAppFontToViewTree(UIView *view);
void GMApplyAppFontToNavigation(UINavigationBar *bar);
void GMApplyAppFontToButton(UIButton *button);

@interface GMPersonalizationStore : NSObject
@property(nonatomic, readonly, copy) NSURL *directoryURL;
@property(nonatomic, readonly, copy) NSString *selectedFontName;
@property(nonatomic, readonly, strong) NSError *lastError;
@property(nonatomic, copy) void (^fontDidChange)(void);
- (instancetype)initWithDirectoryURL:(NSURL *)directoryURL;
- (BOOL)reloadWithError:(NSError **)error;
// nil selects System Default. Only available, successfully registered fonts
// are accepted. A failed save preserves the previous persistent selection.
- (BOOL)selectFontName:(NSString *)name error:(NSError **)error;
@end

// Both controllers use GMSharedPersonalization and native Save/Cancel sheets.
@interface GMFontSettingsController : UIViewController
- (void)applyTheme;
@end
@interface GMIconPickerController : UIViewController
- (void)applyTheme;
@end

#endif
