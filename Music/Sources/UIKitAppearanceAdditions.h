// Public declarations for the Linux build; include after UIKitTabsAdditions.h.
// Apple SDK builds use the SDK's own headers and must not include this file.
// Signatures verified against Apple's public iOS 26 SDK and current DocC pages.
#ifndef GLASS_MUSIC_UIKIT_APPEARANCE_ADDITIONS
#define GLASS_MUSIC_UIKIT_APPEARANCE_ADDITIONS

@class NSCharacterSet, UIButtonConfiguration, UIAction, UIGlassEffect;
@class UIColorPickerViewController, UITextField, UISearchTextField;
@class UISearchController, UISearchBar;
@class UIBarAppearance, UITabBarAppearance, UINavigationBarAppearance;

typedef struct {
    CGFloat top, leading, bottom, trailing;
} NSDirectionalEdgeInsets;
static inline NSDirectionalEdgeInsets NSDirectionalEdgeInsetsMake(CGFloat top, CGFloat leading, CGFloat bottom, CGFloat trailing) {
    return (NSDirectionalEdgeInsets){top, leading, bottom, trailing};
}

typedef NSInteger UIUserInterfaceStyle;
enum {
    UIUserInterfaceStyleUnspecified = 0,
    UIUserInterfaceStyleLight = 1,
    UIUserInterfaceStyleDark = 2
};
typedef NSInteger UIGlassEffectStyle;
enum { UIGlassEffectStyleRegular = 0, UIGlassEffectStyleClear = 1 };
typedef NSInteger UIButtonConfigurationCornerStyle;
enum {
    UIButtonConfigurationCornerStyleFixed = -1,
    UIButtonConfigurationCornerStyleDynamic = 0,
    UIButtonConfigurationCornerStyleSmall = 1,
    UIButtonConfigurationCornerStyleMedium = 2,
    UIButtonConfigurationCornerStyleLarge = 3,
    UIButtonConfigurationCornerStyleCapsule = 4
};
typedef NSInteger UIButtonConfigurationSize;
enum {
    UIButtonConfigurationSizeMedium = 0,
    UIButtonConfigurationSizeSmall = 1,
    UIButtonConfigurationSizeMini = 2,
    UIButtonConfigurationSizeLarge = 3
};
typedef NSInteger UITextAutocapitalizationType;
enum {
    UITextAutocapitalizationTypeNone = 0,
    UITextAutocapitalizationTypeWords = 1,
    UITextAutocapitalizationTypeSentences = 2,
    UITextAutocapitalizationTypeAllCharacters = 3
};
typedef NSInteger UITextAutocorrectionType;
enum {
    UITextAutocorrectionTypeDefault = 0,
    UITextAutocorrectionTypeNo = 1,
    UITextAutocorrectionTypeYes = 2
};
typedef NSInteger UITextFieldViewMode;
enum {
    UITextFieldViewModeNever = 0,
    UITextFieldViewModeWhileEditing = 1,
    UITextFieldViewModeUnlessEditing = 2,
    UITextFieldViewModeAlways = 3
};

@interface NSCharacterSet : NSObject <NSCopying>
+ (NSCharacterSet *)whitespaceAndNewlineCharacterSet;
@end

@interface NSString (GMAppearanceSearching)
@property(nonatomic, readonly) NSInteger integerValue;
- (BOOL)localizedCaseInsensitiveContainsString:(NSString *)string;
- (BOOL)localizedStandardContainsString:(NSString *)string;
- (NSString *)stringByTrimmingCharactersInSet:(NSCharacterSet *)set;
@end

@interface UIColor (GMAppearanceComponents)
+ (UIColor *)colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha;
+ (UIColor *)colorWithHue:(CGFloat)hue saturation:(CGFloat)saturation brightness:(CGFloat)brightness alpha:(CGFloat)alpha;
+ (UIColor *)colorWithDynamicProvider:(UIColor *(^)(UITraitCollection *traits))dynamicProvider;
- (UIColor *)initWithDynamicProvider:(UIColor *(^)(UITraitCollection *traits))dynamicProvider;
- (UIColor *)resolvedColorWithTraitCollection:(UITraitCollection *)traits;
- (BOOL)getRed:(CGFloat *)red green:(CGFloat *)green blue:(CGFloat *)blue alpha:(CGFloat *)alpha;
- (BOOL)getWhite:(CGFloat *)white alpha:(CGFloat *)alpha;
- (BOOL)getHue:(CGFloat *)hue saturation:(CGFloat *)saturation brightness:(CGFloat *)brightness alpha:(CGFloat *)alpha;
@end

@interface UITraitCollection (GMAppearanceTraits)
+ (UITraitCollection *)traitCollectionWithUserInterfaceStyle:(UIUserInterfaceStyle)style;
- (BOOL)hasDifferentColorAppearanceComparedToTraitCollection:(UITraitCollection *)traits;
@end

@interface UIView (GMAppearanceTraits)
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection;
@end

@interface UIViewController (GMAppearancePresentation)
@property(nonatomic) BOOL definesPresentationContext;
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection;
- (void)setEditing:(BOOL)editing animated:(BOOL)animated;
@end

// iOS 26+: resolve dynamically or guard class availability on iOS 16-18.
// This effect is for UIVisualEffectView. UIBarAppearance.backgroundEffect
// explicitly takes UIBlurEffect, not UIGlassEffect.
@interface UIGlassEffect : UIVisualEffect
+ (UIGlassEffect *)effectWithStyle:(UIGlassEffectStyle)style;
@property(nonatomic, getter=isInteractive) BOOL interactive;
@property(nonatomic, copy) UIColor *tintColor;
@end

@interface UIVisualEffectView (GMAppearanceEffect)
@property(nonatomic, copy) UIVisualEffect *effect;
@end

// UIButtonConfiguration exists on every supported version (iOS 15+).
// The two glass factories require iOS 26: test respondsToSelector: before use.
@interface UIButtonConfiguration : NSObject <NSCopying>
+ (instancetype)plainButtonConfiguration;
+ (instancetype)tintedButtonConfiguration;
+ (instancetype)filledButtonConfiguration;
+ (instancetype)glassButtonConfiguration;
+ (instancetype)prominentGlassButtonConfiguration;
@property(nonatomic) UIButtonConfigurationCornerStyle cornerStyle;
@property(nonatomic) UIButtonConfigurationSize buttonSize;
@property(nonatomic, strong) UIColor *baseForegroundColor;
@property(nonatomic, strong) UIColor *baseBackgroundColor;
@property(nonatomic, strong) UIImage *image;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *subtitle;
@property(nonatomic, copy) UIImageSymbolConfiguration *preferredSymbolConfigurationForImage;
@property(nonatomic) NSDirectionalEdgeInsets contentInsets;
@property(nonatomic) CGFloat imagePadding;
@property(nonatomic) BOOL automaticallyUpdateForSelection;
@end

@interface UIButton (GMAppearanceConfiguration)
@property(nonatomic, copy) UIButtonConfiguration *configuration;
- (UIImage *)imageForState:(NSUInteger)state;
- (NSString *)titleForState:(NSUInteger)state;
+ (instancetype)buttonWithConfiguration:(UIButtonConfiguration *)configuration primaryAction:(UIAction *)primaryAction;
- (void)setNeedsUpdateConfiguration;
@end

// iOS 15+: the handler runs after -updateConfiguration, including updates for
// pressed/disabled states. Store the current model image here rather than
// relying on a one-time image mutation to survive a later state update.
typedef void (^UIButtonConfigurationUpdateHandler)(__kindof UIButton *button);
@interface UIButton (GMAppearanceConfigurationUpdates)
@property(nonatomic, copy) UIButtonConfigurationUpdateHandler configurationUpdateHandler;
@property(nonatomic) BOOL automaticallyUpdatesConfiguration;
- (void)updateConfiguration;
@end

@interface UIButtonConfiguration (GMAppearanceConfigurationUpdates)
- (instancetype)updatedConfigurationForButton:(UIButton *)button;
@end

// The picker and all declared delegate callbacks are available at minimum iOS 16.
// Set supportsAlpha=NO for an opaque accent color. The continuous callback can
// preview color changes; persist after a completed change or picker dismissal.
@protocol UIColorPickerViewControllerDelegate <NSObject>
@optional
- (void)colorPickerViewController:(UIColorPickerViewController *)viewController didSelectColor:(UIColor *)color continuously:(BOOL)continuously;
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController;
- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController;
@end

@interface UIColorPickerViewController : UIViewController
@property(nonatomic, weak) id<UIColorPickerViewControllerDelegate> delegate;
@property(nonatomic, strong) UIColor *selectedColor;
@property(nonatomic) BOOL supportsAlpha;
@end

@protocol UITextFieldDelegate <NSObject> @end
@interface UITextField : UIControl
@property(nonatomic, copy) NSString *text;
@property(nonatomic, copy) NSString *placeholder;
@property(nonatomic, strong) UIColor *textColor;
@property(nonatomic, strong) UIFont *font;
@property(nonatomic) NSInteger textAlignment;
@property(nonatomic, weak) id<UITextFieldDelegate> delegate;
@property(nonatomic) UITextFieldViewMode clearButtonMode;
@property(nonatomic) UITextAutocapitalizationType autocapitalizationType;
@property(nonatomic) UITextAutocorrectionType autocorrectionType;
@property(nonatomic) NSInteger keyboardType;
@property(nonatomic) NSInteger returnKeyType;
@property(nonatomic, getter=isSecureTextEntry) BOOL secureTextEntry;
@end

@interface UIAlertController (GMAppearanceTextInput)
@property(nonatomic, readonly) NSArray<UITextField *> *textFields;
- (void)addTextFieldWithConfigurationHandler:(void (^)(UITextField *textField))configurationHandler;
@end

@interface UIAlertAction (GMAppearanceEnabled)
@property(nonatomic, getter=isEnabled) BOOL enabled;
@end

@interface UISearchTextField : UITextField @end
@protocol UISearchBarDelegate <NSObject> @end
@interface UISearchBar : UIView
@property(nonatomic, copy) NSString *text;
@property(nonatomic, copy) NSString *placeholder;
@property(nonatomic, weak) id<UISearchBarDelegate> delegate;
@property(nonatomic, readonly) UISearchTextField *searchTextField;
@property(nonatomic) NSInteger searchBarStyle;
@property(nonatomic, strong) UIColor *barTintColor;
@property(nonatomic) UITextAutocapitalizationType autocapitalizationType;
@property(nonatomic) UITextAutocorrectionType autocorrectionType;
@end

@protocol UISearchResultsUpdating <NSObject>
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController;
@end
@protocol UISearchControllerDelegate <NSObject>
@optional
- (void)willPresentSearchController:(UISearchController *)searchController;
- (void)didPresentSearchController:(UISearchController *)searchController;
- (void)willDismissSearchController:(UISearchController *)searchController;
- (void)didDismissSearchController:(UISearchController *)searchController;
@end
@interface UISearchController : UIViewController
- (instancetype)initWithSearchResultsController:(UIViewController *)searchResultsController;
@property(nonatomic, weak) id<UISearchControllerDelegate> delegate;
@property(nonatomic, weak) id<UISearchResultsUpdating> searchResultsUpdater;
@property(nonatomic, strong, readonly) UIViewController *searchResultsController;
@property(nonatomic, strong, readonly) UISearchBar *searchBar;
@property(nonatomic, getter=isActive) BOOL active;
@property(nonatomic) BOOL obscuresBackgroundDuringPresentation;
@property(nonatomic) BOOL hidesNavigationBarDuringPresentation;
@property(nonatomic) BOOL automaticallyShowsCancelButton;
@end

@interface UINavigationItem (GMAppearanceSearch)
@property(nonatomic, strong) UISearchController *searchController;
@property(nonatomic) BOOL hidesSearchBarWhenScrolling;
@end

@interface UITableView (GMAppearanceEditing)
@property(nonatomic, strong) UIColor *separatorColor;
@property(nonatomic, getter=isEditing) BOOL editing;
@property(nonatomic) BOOL allowsMultipleSelection;
@property(nonatomic) BOOL allowsSelectionDuringEditing;
@property(nonatomic) BOOL allowsMultipleSelectionDuringEditing;
@property(nonatomic, readonly) NSArray<NSIndexPath *> *indexPathsForSelectedRows;
- (void)setEditing:(BOOL)editing animated:(BOOL)animated;
- (void)selectRowAtIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated scrollPosition:(NSInteger)scrollPosition;
- (void)insertRowsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths withRowAnimation:(NSInteger)animation;
- (void)deleteRowsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths withRowAnimation:(NSInteger)animation;
- (void)reloadRowsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths withRowAnimation:(NSInteger)animation;
- (void)beginUpdates;
- (void)endUpdates;
- (void)performBatchUpdates:(void (^)(void))updates completion:(void (^)(BOOL finished))completion;
@end

// Public bar appearance APIs are declared for completeness. Replacing a native
// iOS 26 bar's backgroundEffect with UIBlurEffect is not a documented way to
// change the opacity of Liquid Glass. Preserve default native appearances when
// retaining their glass/selection behavior; tint content beneath the bar instead.
@interface UIBarAppearance : NSObject <NSCopying>
- (void)configureWithDefaultBackground;
- (void)configureWithOpaqueBackground;
- (void)configureWithTransparentBackground;
@property(nonatomic, copy) UIBlurEffect *backgroundEffect;
@property(nonatomic, copy) UIColor *backgroundColor;
@property(nonatomic, copy) UIColor *shadowColor;
@end

@interface UITabBarAppearance : UIBarAppearance @end
@interface UINavigationBarAppearance : UIBarAppearance
@property(nonatomic, copy) NSDictionary<NSString *, id> *titleTextAttributes;
@property(nonatomic, copy) NSDictionary<NSString *, id> *largeTitleTextAttributes;
@end

@interface UITabBar (GMAppearanceBackground)
@property(nonatomic, getter=isTranslucent) BOOL translucent;
@property(nonatomic, copy) UITabBarAppearance *standardAppearance;
@property(nonatomic, copy) UITabBarAppearance *scrollEdgeAppearance;
@end

@interface UINavigationBar (GMAppearanceBackground)
@property(nonatomic, copy) UINavigationBarAppearance *standardAppearance;
@property(nonatomic, copy) UINavigationBarAppearance *scrollEdgeAppearance;
@property(nonatomic, copy) UINavigationBarAppearance *compactAppearance;
@end

// Album/track metadata: these symbols are public and predate minimum iOS 16.
// Keep NSData's inner-pointer annotation: ARC must preserve its owner while a
// pointer obtained from -bytes is being consumed. Check length before reading.
@interface NSData (GMAppearanceMetadataBytes)
@property(nonatomic, readonly) NSUInteger length;
@property(nonatomic, readonly) const void *bytes __attribute__((objc_returns_inner_pointer));
- (void)getBytes:(void *)buffer length:(NSUInteger)length;
@end

typedef NSString *AVMetadataIdentifier;
@interface AVURLAsset (GMAppearanceAlbumMetadata)
@property(nonatomic, readonly) NSArray<AVMetadataItem *> *metadata;
@end

@interface AVMetadataItem (GMAppearanceAlbumMetadata)
@property(nonatomic, readonly, copy) AVMetadataIdentifier identifier;
@property(nonatomic, readonly, copy) id<NSObject, NSCopying> value;
@property(nonatomic, readonly) NSNumber *numberValue;
@end

extern AVMetadataIdentifier const AVMetadataIdentifieriTunesMetadataAlbumArtist;
extern AVMetadataIdentifier const AVMetadataIdentifierID3MetadataBand;
extern AVMetadataIdentifier const AVMetadataIdentifierID3MetadataTrackNumber;
extern AVMetadataIdentifier const AVMetadataIdentifierID3MetadataPartOfASet;
extern AVMetadataIdentifier const AVMetadataIdentifieriTunesMetadataTrackNumber;
extern AVMetadataIdentifier const AVMetadataIdentifieriTunesMetadataDiscNumber;

// iOS 18+: preferredTransition belongs to the controller being presented.
// Resolve the transition class dynamically and guard its factory plus the
// property's setter on older systems. Use nil options for native interaction.
@class UIViewControllerTransition, UIZoomTransitionOptions;
@class UIZoomTransitionSourceViewProviderContext, UIZoomTransitionInteractionContext;
@class UIZoomTransitionAlignmentRectContext;

typedef NSInteger UIModalTransitionStyle;
enum {
    UIModalTransitionStyleCoverVertical = 0,
    UIModalTransitionStyleFlipHorizontal = 1,
    UIModalTransitionStyleCrossDissolve = 2,
    UIModalTransitionStylePartialCurl = 3
};

@interface UIViewControllerTransition : NSObject
+ (instancetype)zoomWithOptions:(UIZoomTransitionOptions *)options
            sourceViewProvider:(UIView *(^)(UIZoomTransitionSourceViewProviderContext *context))sourceViewProvider;
+ (instancetype)crossDissolveTransition;
@end

@interface UIZoomTransitionSourceViewProviderContext : NSObject
@property(nonatomic, strong, readonly) UIViewController *sourceViewController;
@property(nonatomic, strong, readonly) UIViewController *zoomedViewController;
@end

@interface UIZoomTransitionOptions : NSObject <NSCopying>
@property(nonatomic, copy) BOOL (^interactiveDismissShouldBegin)(UIZoomTransitionInteractionContext *context);
@property(nonatomic, copy) CGRect (^alignmentRectProvider)(UIZoomTransitionAlignmentRectContext *context);
@property(nonatomic, strong) UIColor *dimmingColor;
@property(nonatomic, strong) UIBlurEffect *dimmingVisualEffect;
@end

@interface UIZoomTransitionInteractionContext : NSObject
@property(nonatomic, readonly) CGPoint location;
@property(nonatomic, readonly) BOOL willBegin;
@end

@interface UIZoomTransitionAlignmentRectContext : NSObject
@property(nonatomic, readonly) UIView *sourceView;
@property(nonatomic, readonly) UIViewController *zoomedViewController;
@end

@interface UIViewController (GMAppearanceZoomTransition)
@property(nonatomic, strong) UIViewControllerTransition *preferredTransition;
@property(nonatomic) UIModalTransitionStyle modalTransitionStyle;
@end

@interface UIView (GMAppearanceTransitionSource)
@property(nonatomic, readonly) UIWindow *window;
@end

// These C functions are available on every supported iOS version (8+/14+).
extern BOOL UIAccessibilityIsReduceMotionEnabled(void);
extern BOOL UIAccessibilityPrefersCrossFadeTransitions(void);

#endif
