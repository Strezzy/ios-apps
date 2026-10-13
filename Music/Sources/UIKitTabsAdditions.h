// Additional public declarations used only by the Linux cross-build.
// Include at the end of MiniSDK.h. Xcode uses Apple's actual SDK headers.
// Signatures checked against Apple's iOS 26 public UIKit/Foundation headers;
// current API documentation and availability notes are in Support/API-NOTES.txt.
#ifndef GLASS_MUSIC_UIKIT_TABS_ADDITIONS
#define GLASS_MUSIC_UIKIT_TABS_ADDITIONS

@class UIBarItem, UIBarButtonItem, UITabBarItem, UITabBar, UITabAccessory;
@class UINavigationItem, UINavigationBar, UINavigationController, UITabBarController;
@class UITableViewController, UISegmentedControl, UIGestureRecognizer, UITapGestureRecognizer;
@class UITraitCollection, UIPresentationController, UISheetPresentationController;
@class UISheetPresentationControllerDetent, UIImageConfiguration, UIImageSymbolConfiguration;
@class MPVolumeView;

// UIKit's enum backing types are NSInteger, including UIImageSymbolWeight.
// Symbol weight is not the CGFloat weight accepted by UIFont methods.
typedef NSInteger UIImageSymbolWeight;
enum {
    UIImageSymbolWeightUnspecified = 0,
    UIImageSymbolWeightUltraLight = 1,
    UIImageSymbolWeightThin = 2,
    UIImageSymbolWeightLight = 3,
    UIImageSymbolWeightRegular = 4,
    UIImageSymbolWeightMedium = 5,
    UIImageSymbolWeightSemibold = 6,
    UIImageSymbolWeightBold = 7,
    UIImageSymbolWeightHeavy = 8,
    UIImageSymbolWeightBlack = 9
};
typedef NSInteger UIImageRenderingMode;
enum {
    UIImageRenderingModeAutomatic = 0,
    UIImageRenderingModeAlwaysOriginal = 1,
    UIImageRenderingModeAlwaysTemplate = 2
};
typedef NSInteger UIBarButtonItemStyle;
enum {
    UIBarButtonItemStylePlain = 0,
    UIBarButtonItemStyleBordered = 1,
    UIBarButtonItemStyleDone = 2,
    UIBarButtonItemStyleProminent = 2 // New name in iOS 26; same value as Done.
};
typedef NSInteger UIBarButtonSystemItem;
enum {
    UIBarButtonSystemItemDone = 0,
    UIBarButtonSystemItemCancel = 1,
    UIBarButtonSystemItemEdit = 2,
    UIBarButtonSystemItemSave = 3,
    UIBarButtonSystemItemAdd = 4,
    UIBarButtonSystemItemFlexibleSpace = 5,
    UIBarButtonSystemItemFixedSpace = 6,
    UIBarButtonSystemItemTrash = 16,
    UIBarButtonSystemItemPlay = 17,
    UIBarButtonSystemItemPause = 18,
    UIBarButtonSystemItemClose = 24
};
typedef NSInteger UINavigationItemLargeTitleDisplayMode;
enum {
    UINavigationItemLargeTitleDisplayModeAutomatic = 0,
    UINavigationItemLargeTitleDisplayModeAlways = 1,
    UINavigationItemLargeTitleDisplayModeNever = 2
};
typedef NSInteger UITableViewStyle;
enum {
    UITableViewStylePlain = 0,
    UITableViewStyleGrouped = 1,
    UITableViewStyleInsetGrouped = 2
};
typedef NSInteger UITableViewCellAccessoryType;
enum {
    UITableViewCellAccessoryNone = 0,
    UITableViewCellAccessoryDisclosureIndicator = 1,
    UITableViewCellAccessoryDetailDisclosureButton = 2,
    UITableViewCellAccessoryCheckmark = 3,
    UITableViewCellAccessoryDetailButton = 4
};
typedef NSInteger UITabBarMinimizeBehavior;
enum {
    UITabBarMinimizeBehaviorAutomatic = 0,
    UITabBarMinimizeBehaviorNever = 1,
    UITabBarMinimizeBehaviorOnScrollDown = 2,
    UITabBarMinimizeBehaviorOnScrollUp = 3
};
typedef NSInteger UITabAccessoryEnvironment;
enum {
    UITabAccessoryEnvironmentUnspecified = 0,
    UITabAccessoryEnvironmentNone = 1,
    UITabAccessoryEnvironmentRegular = 2,
    UITabAccessoryEnvironmentInline = 3
};

@interface NSNumber (GMTabsValues)
@property(nonatomic, readonly) BOOL boolValue;
@property(nonatomic, readonly) NSInteger integerValue;
@end

@interface NSDictionary<KeyType, ObjectType> (GMTabsPropertyLists)
+ (NSDictionary<KeyType, ObjectType> *)dictionaryWithContentsOfURL:(NSURL *)url;
+ (NSDictionary<NSString *, ObjectType> *)dictionaryWithContentsOfURL:(NSURL *)url error:(NSError **)error;
- (BOOL)writeToURL:(NSURL *)url error:(NSError **)error;
- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)atomically;
@end

@interface NSURL (GMTabsParentURL)
@property(nonatomic, readonly, copy) NSURL *URLByDeletingLastPathComponent;
@end

@interface NSIndexPath (GMTabsSections)
@property(nonatomic, readonly) NSInteger section;
+ (NSIndexPath *)indexPathForRow:(NSInteger)row inSection:(NSInteger)section;
@end

@interface UIColor (GMTabsSemanticColors)
+ (UIColor *)labelColor;
+ (UIColor *)secondaryLabelColor;
+ (UIColor *)tertiaryLabelColor;
+ (UIColor *)quaternaryLabelColor;
+ (UIColor *)separatorColor;
+ (UIColor *)opaqueSeparatorColor;
+ (UIColor *)systemBackgroundColor;
+ (UIColor *)secondarySystemBackgroundColor;
+ (UIColor *)tertiarySystemBackgroundColor;
+ (UIColor *)systemGroupedBackgroundColor;
+ (UIColor *)secondarySystemGroupedBackgroundColor;
+ (UIColor *)tertiarySystemGroupedBackgroundColor;
+ (UIColor *)systemFillColor;
+ (UIColor *)secondarySystemFillColor;
+ (UIColor *)tertiarySystemFillColor;
+ (UIColor *)systemRedColor;
+ (UIColor *)systemPinkColor;
+ (UIColor *)systemBlueColor;
+ (UIColor *)systemGrayColor;
+ (UIColor *)systemGray5Color;
+ (UIColor *)systemGray6Color;
@end

@interface UIImageConfiguration : NSObject
@end

@interface UIImageSymbolConfiguration : UIImageConfiguration
+ (instancetype)configurationWithPointSize:(CGFloat)pointSize weight:(UIImageSymbolWeight)weight;
@end

@interface UIImage (GMTabsSymbols)
+ (UIImage *)systemImageNamed:(NSString *)name withConfiguration:(UIImageConfiguration *)configuration;
- (UIImage *)imageWithRenderingMode:(UIImageRenderingMode)renderingMode;
- (UIImage *)imageWithTintColor:(UIColor *)color;
- (UIImage *)imageWithTintColor:(UIColor *)color renderingMode:(UIImageRenderingMode)renderingMode;
@property(nonatomic, readonly) CGSize size;
@end

@interface UITraitCollection : NSObject
@property(nonatomic, readonly) NSInteger userInterfaceStyle;
// iOS 26+: test respondsToSelector: before reading on the iOS 16-18 fallback.
@property(nonatomic, readonly) UITabAccessoryEnvironment tabAccessoryEnvironment;
@end

@interface UIView (GMTabsLayout)
@property(nonatomic) CGPoint center;
@property(nonatomic, readonly) UIView *superview;
@property(nonatomic, readonly) UITraitCollection *traitCollection;
@property(nonatomic, readonly) CGSize intrinsicContentSize;
- (void)layoutSubviews;
- (void)invalidateIntrinsicContentSize;
- (CGSize)sizeThatFits:(CGSize)size;
- (void)sizeToFit;
- (void)safeAreaInsetsDidChange;
- (void)addGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer;
- (void)removeGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer;
- (void)bringSubviewToFront:(UIView *)view;
@end

@protocol UIGestureRecognizerDelegate @end
@interface UIGestureRecognizer : NSObject
- (instancetype)initWithTarget:(id)target action:(SEL)action;
@property(nonatomic, weak) id<UIGestureRecognizerDelegate> delegate;
@property(nonatomic, getter=isEnabled) BOOL enabled;
@property(nonatomic) BOOL cancelsTouchesInView;
@property(nonatomic, readonly) UIView *view;
- (CGPoint)locationInView:(UIView *)view;
@end

@interface UITapGestureRecognizer : UIGestureRecognizer
@property(nonatomic) NSUInteger numberOfTapsRequired;
@property(nonatomic) NSUInteger numberOfTouchesRequired;
@end

@interface UIScrollView (GMTabsScrolling)
@property(nonatomic) CGPoint contentOffset;
@property(nonatomic) NSInteger contentInsetAdjustmentBehavior;
@property(nonatomic) UIEdgeInsets scrollIndicatorInsets;
@property(nonatomic) BOOL showsHorizontalScrollIndicator;
@end

@interface UITableView (GMTabsSections)
@property(nonatomic, strong) UIView *tableHeaderView;
@property(nonatomic, strong) UIView *backgroundView;
@property(nonatomic) UIEdgeInsets separatorInset;
@property(nonatomic) CGFloat sectionHeaderHeight;
@property(nonatomic) CGFloat sectionFooterHeight;
@property(nonatomic) CGFloat sectionHeaderTopPadding;
@property(nonatomic) CGFloat estimatedRowHeight;
@property(nonatomic) BOOL allowsSelection;
@end

@interface UITableViewCell (GMTabsAccessories)
@property(nonatomic) UITableViewCellAccessoryType accessoryType;
@property(nonatomic) UIEdgeInsets separatorInset;
@end

@interface UIViewController (GMTabsNavigation)
@property(nonatomic, copy) NSString *title;
@property(nonatomic, readonly, strong) UINavigationItem *navigationItem;
@property(nonatomic, strong) UITabBarItem *tabBarItem;
@property(nonatomic, readonly, strong) UINavigationController *navigationController;
@property(nonatomic, readonly, strong) UITabBarController *tabBarController;
@property(nonatomic, readonly) UIViewController *presentingViewController;
@property(nonatomic, readonly) UIViewController *parentViewController;
@property(nonatomic, readonly) UITraitCollection *traitCollection;
@property(nonatomic) UIEdgeInsets additionalSafeAreaInsets;
@property(nonatomic) BOOL hidesBottomBarWhenPushed;
@property(nonatomic, readonly) UISheetPresentationController *sheetPresentationController;
- (void)loadViewIfNeeded;
- (void)viewWillAppear:(BOOL)animated;
- (void)viewDidAppear:(BOOL)animated;
- (void)viewWillDisappear:(BOOL)animated;
- (void)viewDidDisappear:(BOOL)animated;
@end

@interface UITableViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
- (instancetype)initWithStyle:(UITableViewStyle)style;
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic) BOOL clearsSelectionOnViewWillAppear;
@end

@interface UIBarItem : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, strong) UIImage *image;
@property(nonatomic, getter=isEnabled) BOOL enabled;
@property(nonatomic) NSInteger tag;
@end

@interface UIBarButtonItem : UIBarItem
- (instancetype)initWithBarButtonSystemItem:(UIBarButtonSystemItem)systemItem target:(id)target action:(SEL)action;
- (instancetype)initWithTitle:(NSString *)title style:(UIBarButtonItemStyle)style target:(id)target action:(SEL)action;
- (instancetype)initWithImage:(UIImage *)image style:(UIBarButtonItemStyle)style target:(id)target action:(SEL)action;
- (instancetype)initWithCustomView:(UIView *)customView;
@property(nonatomic, weak) id target;
@property(nonatomic) SEL action;
@property(nonatomic) UIBarButtonItemStyle style;
@property(nonatomic, strong) UIColor *tintColor;
@property(nonatomic, strong) UIView *customView;
@end

@interface UINavigationItem : NSObject
- (instancetype)initWithTitle:(NSString *)title;
@property(nonatomic, copy) NSString *title;
@property(nonatomic) UINavigationItemLargeTitleDisplayMode largeTitleDisplayMode;
@property(nonatomic, strong) UIBarButtonItem *leftBarButtonItem;
@property(nonatomic, strong) UIBarButtonItem *rightBarButtonItem;
@property(nonatomic, copy) NSArray<UIBarButtonItem *> *leftBarButtonItems;
@property(nonatomic, copy) NSArray<UIBarButtonItem *> *rightBarButtonItems;
@end

@interface UINavigationBar : UIView
@property(nonatomic) BOOL prefersLargeTitles;
@property(nonatomic, getter=isTranslucent) BOOL translucent;
@end

@interface UINavigationController : UIViewController
- (instancetype)initWithRootViewController:(UIViewController *)rootViewController;
@property(nonatomic, readonly) UINavigationBar *navigationBar;
@property(nonatomic, readonly, strong) UIViewController *topViewController;
@property(nonatomic, copy) NSArray<UIViewController *> *viewControllers;
@property(nonatomic, getter=isNavigationBarHidden) BOOL navigationBarHidden;
- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated;
- (UIViewController *)popViewControllerAnimated:(BOOL)animated;
- (void)setNavigationBarHidden:(BOOL)hidden animated:(BOOL)animated;
@end

@interface UITabBarItem : UIBarItem
- (instancetype)initWithTitle:(NSString *)title image:(UIImage *)image tag:(NSInteger)tag;
- (instancetype)initWithTitle:(NSString *)title image:(UIImage *)image selectedImage:(UIImage *)selectedImage;
@property(nonatomic, strong) UIImage *selectedImage;
@end

@interface UITabBar : UIView
@property(nonatomic, strong) UIColor *unselectedItemTintColor;
@end

// iOS 26+. This is an NSObject model, not a view. UIKit supplies its glass.
// Resolve using NSClassFromString to avoid a strong dependency on iOS 16-18.
@interface UITabAccessory : NSObject
- (instancetype)initWithContentView:(UIView *)contentView;
@property(nonatomic, strong, readonly) UIView *contentView;
- (instancetype)init __attribute__((unavailable("Use initWithContentView:")));
+ (instancetype)new __attribute__((unavailable("Use initWithContentView:")));
@end

@interface UITabBarController : UIViewController
@property(nonatomic, copy) NSArray<UIViewController *> *viewControllers;
@property(nonatomic) NSUInteger selectedIndex;
@property(nonatomic, readonly) UITabBar *tabBar;
- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated;
// iOS 26+ only; test respondsToSelector: before use on older systems.
@property(nonatomic, strong) UITabAccessory *bottomAccessory;
- (void)setBottomAccessory:(UITabAccessory *)bottomAccessory animated:(BOOL)animated;
@property(nonatomic) UITabBarMinimizeBehavior tabBarMinimizeBehavior;
@end

@interface UISegmentedControl : UIControl
- (instancetype)initWithItems:(NSArray *)items;
@property(nonatomic) NSInteger selectedSegmentIndex;
@property(nonatomic, strong) UIColor *selectedSegmentTintColor;
- (void)setTitle:(NSString *)title forSegmentAtIndex:(NSUInteger)segment;
@end

@interface UIPresentationController : NSObject
@end

@interface UISheetPresentationControllerDetent : NSObject
+ (instancetype)mediumDetent;
+ (instancetype)largeDetent;
@end

@interface UISheetPresentationController : UIPresentationController
@property(nonatomic, copy) NSArray<UISheetPresentationControllerDetent *> *detents;
@property(nonatomic) BOOL prefersGrabberVisible;
@end

@interface MPVolumeView : UIView
@property(nonatomic) BOOL showsVolumeSlider;
// Deprecated by Apple in favor of AVRoutePickerView, but available on iPhone.
@property(nonatomic) BOOL showsRouteButton;
@end

#endif
