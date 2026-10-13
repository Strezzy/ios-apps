// Narrow public declarations for the Linux arm64 build. Include after the
// other MiniSDK additions. A real Apple SDK build uses its framework headers.
// Checked against Apple's public iOS 26 SDK: UIKit, PhotosUI, Foundation,
// UniformTypeIdentifiers, CoreGraphics, CoreFoundation, and ImageIO.
#ifndef GLASS_MUSIC_UIKIT_EDITING_ADDITIONS
#define GLASS_MUSIC_UIKIT_EDITING_ADDITIONS

@class UIMenuElement, UIMenu, UIAction, UICommand;
@class PHPickerFilter, PHPickerConfiguration, PHPickerResult, PHPickerViewController;
@class NSItemProvider, NSProgress;
@class UIPanGestureRecognizer, UITouch, UIEvent, UIAccessibilityCustomAction;
@class UIContextualAction, UISwipeActionsConfiguration;

// Menus and actions are available before the minimum supported iOS 16.
typedef NSString *UIActionIdentifier;
typedef NSString *UIMenuIdentifier;
typedef NSInteger UIMenuElementState;
enum { UIMenuElementStateOff = 0, UIMenuElementStateOn = 1, UIMenuElementStateMixed = 2 };
typedef NSUInteger UIMenuElementAttributes;
enum {
    UIMenuElementAttributesDisabled = 1UL << 0,
    UIMenuElementAttributesDestructive = 1UL << 1,
    UIMenuElementAttributesHidden = 1UL << 2,
    UIMenuElementAttributesKeepsMenuPresented = 1UL << 3
};
typedef NSUInteger UIMenuOptions;
enum {
    UIMenuOptionsDisplayInline = 1UL << 0,
    UIMenuOptionsDestructive = 1UL << 1,
    UIMenuOptionsSingleSelection = 1UL << 5
};
typedef void (^UIActionHandler)(__kindof UIAction *action);

@interface UIMenuElement : NSObject <NSCopying>
@property(nonatomic, readonly) NSString *title;
@property(nonatomic, copy) NSString *subtitle;
@property(nonatomic, readonly) UIImage *image;
@end

@interface UIAction : UIMenuElement
+ (instancetype)actionWithTitle:(NSString *)title image:(UIImage *)image identifier:(UIActionIdentifier)identifier handler:(UIActionHandler)handler;
+ (instancetype)actionWithHandler:(UIActionHandler)handler;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) UIImage *image;
@property(nonatomic, copy) NSString *discoverabilityTitle;
@property(nonatomic, readonly) UIActionIdentifier identifier;
@property(nonatomic) UIMenuElementAttributes attributes;
@property(nonatomic) UIMenuElementState state;
@property(nonatomic, readonly) id sender;
@end

@interface UICommand : UIMenuElement
+ (instancetype)commandWithTitle:(NSString *)title image:(UIImage *)image action:(SEL)action propertyList:(id)propertyList;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) UIImage *image;
@property(nonatomic, copy) NSString *discoverabilityTitle;
@property(nonatomic, readonly) SEL action;
@property(nonatomic, readonly) id propertyList;
@property(nonatomic) UIMenuElementAttributes attributes;
@property(nonatomic) UIMenuElementState state;
@end

@interface UIMenu : UIMenuElement
+ (UIMenu *)menuWithChildren:(NSArray<UIMenuElement *> *)children;
+ (UIMenu *)menuWithTitle:(NSString *)title children:(NSArray<UIMenuElement *> *)children;
+ (UIMenu *)menuWithTitle:(NSString *)title image:(UIImage *)image identifier:(UIMenuIdentifier)identifier options:(UIMenuOptions)options children:(NSArray<UIMenuElement *> *)children;
- (UIMenu *)menuByReplacingChildren:(NSArray<UIMenuElement *> *)newChildren;
@property(nonatomic, readonly) UIMenuIdentifier identifier;
@property(nonatomic, readonly) UIMenuOptions options;
@property(nonatomic, readonly) NSArray<UIMenuElement *> *children;
@end

@interface UIButton (GMEditingMenus)
@property(nonatomic, copy) UIMenu *menu;
@end
@interface UIControl (GMEditingMenus)
@property(nonatomic) BOOL showsMenuAsPrimaryAction;
@end

// PHPicker (iOS 14+) uses the system selection UI; no broad Photos permission
// request is needed. Its delegate MUST dismiss the picker on both selection
// and cancellation: unlike UIColorPicker, this picker does not auto-dismiss.
typedef NSInteger PHPickerConfigurationAssetRepresentationMode;
enum {
    PHPickerConfigurationAssetRepresentationModeAutomatic = 0,
    PHPickerConfigurationAssetRepresentationModeCurrent = 1,
    PHPickerConfigurationAssetRepresentationModeCompatible = 2
};
@interface PHPickerFilter : NSObject <NSCopying>
+ (PHPickerFilter *)imagesFilter;
@end
@interface PHPickerConfiguration : NSObject <NSCopying>
- (instancetype)init;
@property(nonatomic) PHPickerConfigurationAssetRepresentationMode preferredAssetRepresentationMode;
@property(nonatomic) NSInteger selectionLimit;
@property(nonatomic, copy) PHPickerFilter *filter;
@end
@interface PHPickerResult : NSObject
@property(nonatomic, readonly) NSItemProvider *itemProvider;
@property(nonatomic, readonly) NSString *assetIdentifier;
@end
@protocol PHPickerViewControllerDelegate <NSObject>
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results;
@end
@interface PHPickerViewController : UIViewController
- (instancetype)initWithConfiguration:(PHPickerConfiguration *)configuration;
@property(nonatomic, copy, readonly) PHPickerConfiguration *configuration;
@property(nonatomic, weak) id<PHPickerViewControllerDelegate> delegate;
@end

@interface NSItemProvider : NSObject <NSCopying>
@property(atomic, copy, readonly) NSArray<NSString *> *registeredTypeIdentifiers;
@property(atomic, copy) NSString *suggestedName;
- (BOOL)hasItemConformingToTypeIdentifier:(NSString *)typeIdentifier;
// The URL's temporary file is deleted when the completion block returns.
// Consume it synchronously in that block or copy it before dispatching work.
- (NSProgress *)loadFileRepresentationForTypeIdentifier:(NSString *)typeIdentifier completionHandler:(void (^)(NSURL *url, NSError *error))completionHandler;
- (NSProgress *)loadDataRepresentationForTypeIdentifier:(NSString *)typeIdentifier completionHandler:(void (^)(NSData *data, NSError *error))completionHandler;
@end

@interface UTType (GMEditingImageTypes)
@property(readonly) NSString *identifier;
- (BOOL)conformsToType:(UTType *)type;
@end
extern UTType *const UTTypeImage;
extern UTType *const UTTypeJPEG;

// ImageIO creates a bounded thumbnail without first making a full-size UIImage.
// Create/Copy results below are owned by the caller: release source/image when
// finished. UIImageJPEGRepresentation returns an ARC-managed NSData object.
typedef __SIZE_TYPE__ size_t;
typedef const void *CFTypeRef;
typedef const struct __CFURL *CFURLRef;
typedef const struct __CFData *CFDataRef;
typedef const struct __CFDictionary *CFDictionaryRef;
typedef const struct __CFString *CFStringRef;
typedef struct CGImageSource *CGImageSourceRef;
typedef struct CGImage *CGImageRef;
extern void CFRelease(CFTypeRef object);
extern CGImageSourceRef CGImageSourceCreateWithURL(CFURLRef url, CFDictionaryRef options);
extern CGImageSourceRef CGImageSourceCreateWithData(CFDataRef data, CFDictionaryRef options);
extern size_t CGImageSourceGetCount(CGImageSourceRef source);
extern CGImageRef CGImageSourceCreateThumbnailAtIndex(CGImageSourceRef source, size_t index, CFDictionaryRef options);
extern void CGImageRelease(CGImageRef image);
extern size_t CGImageGetWidth(CGImageRef image);
extern size_t CGImageGetHeight(CGImageRef image);
extern CFStringRef const kCGImageSourceShouldCache;
extern CFStringRef const kCGImageSourceShouldCacheImmediately;
extern CFStringRef const kCGImageSourceCreateThumbnailFromImageAlways;
extern CFStringRef const kCGImageSourceCreateThumbnailWithTransform;
extern CFStringRef const kCGImageSourceThumbnailMaxPixelSize;

typedef NSInteger UIImageOrientation;
enum {
    UIImageOrientationUp = 0, UIImageOrientationDown = 1,
    UIImageOrientationLeft = 2, UIImageOrientationRight = 3,
    UIImageOrientationUpMirrored = 4, UIImageOrientationDownMirrored = 5,
    UIImageOrientationLeftMirrored = 6, UIImageOrientationRightMirrored = 7
};
@interface UIImage (GMEditingArtwork)
+ (UIImage *)imageWithContentsOfFile:(NSString *)path;
+ (UIImage *)imageWithCGImage:(CGImageRef)image;
+ (UIImage *)imageWithCGImage:(CGImageRef)image scale:(CGFloat)scale orientation:(UIImageOrientation)orientation;
@property(nonatomic, readonly) CGFloat scale;
@property(nonatomic, readonly) UIImageOrientation imageOrientation;
@property(nonatomic, readonly) CGImageRef CGImage __attribute__((objc_returns_inner_pointer));
@end
extern NSData *UIImageJPEGRepresentation(UIImage *image, CGFloat compressionQuality);
@interface NSData (GMEditingArtworkFiles)
+ (instancetype)dataWithContentsOfURL:(NSURL *)url options:(NSUInteger)options error:(NSError **)error;
- (BOOL)writeToURL:(NSURL *)url options:(NSUInteger)options error:(NSError **)error;
@end

// Text field content/font/keyboard properties already exist in Appearance.
typedef NSInteger UIReturnKeyType;
enum {
    UIReturnKeyDefault = 0, UIReturnKeyGo = 1, UIReturnKeyNext = 4,
    UIReturnKeySearch = 6, UIReturnKeyDone = 9, UIReturnKeyContinue = 11
};
typedef NSInteger UITextBorderStyle;
enum { UITextBorderStyleNone = 0, UITextBorderStyleLine = 1, UITextBorderStyleBezel = 2, UITextBorderStyleRoundedRect = 3 };
enum {
    UIControlEventEditingDidBegin = 1UL << 16,
    UIControlEventEditingChanged = 1UL << 17,
    UIControlEventEditingDidEnd = 1UL << 18,
    UIControlEventEditingDidEndOnExit = 1UL << 19
};
@interface UITextField (GMEditingTextEntry)
@property(nonatomic) UITextBorderStyle borderStyle;
@property(nonatomic) BOOL enablesReturnKeyAutomatically;
@property(nonatomic, readonly, getter=isEditing) BOOL editing;
@property(nonatomic, strong) UIView *leftView;
@property(nonatomic) UITextFieldViewMode leftViewMode;
@property(nonatomic, strong) UIView *rightView;
@property(nonatomic) UITextFieldViewMode rightViewMode;
@end
@interface UIView (GMEditingFirstResponder)
- (BOOL)endEditing:(BOOL)force;
- (BOOL)becomeFirstResponder;
- (BOOL)resignFirstResponder;
@property(nonatomic, readonly) BOOL isFirstResponder;
@end
// Existing delegate protocol stubs stay untouched. Implement these public
// methods on the delegate as needed (all are optional in Apple's SDK):
// - (BOOL)textFieldShouldReturn:(UITextField *)textField;
// - (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:
//     (NSRange)range replacementString:(NSString *)string;

// UISheetPresentationController and medium/large factories are in Tabs.
typedef NSString *UISheetPresentationControllerDetentIdentifier;
extern UISheetPresentationControllerDetentIdentifier const UISheetPresentationControllerDetentIdentifierMedium;
extern UISheetPresentationControllerDetentIdentifier const UISheetPresentationControllerDetentIdentifierLarge;
@interface UISheetPresentationController (GMEditingSheet)
@property(nonatomic, copy) UISheetPresentationControllerDetentIdentifier selectedDetentIdentifier;
@property(nonatomic) CGFloat preferredCornerRadius;
@property(nonatomic) BOOL prefersScrollingExpandsWhenScrolledToEdge;
@property(nonatomic) BOOL prefersEdgeAttachedInCompactHeight;
- (void)animateChanges:(void (^)(void))changes;
@end
@interface UIViewController (GMEditingSheet)
@property(nonatomic, getter=isModalInPresentation) BOOL modalInPresentation;
@property(nonatomic, readonly, getter=isBeingDismissed) BOOL beingDismissed;
@end
@interface UINavigationController (GMEditingNavigation)
- (NSArray<__kindof UIViewController *> *)popToRootViewControllerAnimated:(BOOL)animated;
@end

// Horizontal reveal controls. CGAffineTransform is six consecutive CGFloat
// fields (48 bytes on arm64); declaring it as CGRect or a pointer breaks ABI.
typedef struct CGAffineTransform { CGFloat a, b, c, d, tx, ty; } CGAffineTransform;
static const CGAffineTransform CGAffineTransformIdentity = {1,0,0,1,0,0};
static inline CGAffineTransform CGAffineTransformMakeTranslation(CGFloat tx, CGFloat ty) {
    return (CGAffineTransform){1,0,0,1,tx,ty};
}
typedef NSInteger UIGestureRecognizerState;
enum {
    UIGestureRecognizerStatePossible = 0, UIGestureRecognizerStateBegan = 1,
    UIGestureRecognizerStateChanged = 2, UIGestureRecognizerStateEnded = 3,
    UIGestureRecognizerStateCancelled = 4, UIGestureRecognizerStateFailed = 5,
    UIGestureRecognizerStateRecognized = 3
};
@interface UIGestureRecognizer (GMEditingGestureState)
@property(nonatomic, readonly) UIGestureRecognizerState state;
- (void)requireGestureRecognizerToFail:(UIGestureRecognizer *)otherGestureRecognizer;
@end
@interface UIPanGestureRecognizer : UIGestureRecognizer
@property(nonatomic) NSUInteger minimumNumberOfTouches;
@property(nonatomic) NSUInteger maximumNumberOfTouches;
- (CGPoint)translationInView:(UIView *)view;
- (void)setTranslation:(CGPoint)translation inView:(UIView *)view;
- (CGPoint)velocityInView:(UIView *)view;
@end
@interface UITouch : NSObject
@property(nonatomic, readonly, strong) UIView *view;
- (CGPoint)locationInView:(UIView *)view;
@end
@interface UIScrollView (GMEditingPan)
// Apple prohibits replacing this recognizer's delegate.
@property(nonatomic, readonly) UIPanGestureRecognizer *panGestureRecognizer;
@end
// Public optional UIGestureRecognizerDelegate callbacks (the earlier protocol
// stub remains unchanged; concrete delegates implement these signatures):
// - (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer;
// - (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch;
// - (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other;
// - (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other;
// Returning YES in the last method makes `other` require `recognizer` to fail.

typedef NSUInteger UIViewAnimationOptions;
enum {
    UIViewAnimationOptionAllowUserInteraction = 1UL << 1,
    UIViewAnimationOptionBeginFromCurrentState = 1UL << 2,
    UIViewAnimationOptionCurveEaseInOut = 0UL << 16,
    UIViewAnimationOptionCurveEaseIn = 1UL << 16,
    UIViewAnimationOptionCurveEaseOut = 2UL << 16,
    UIViewAnimationOptionCurveLinear = 3UL << 16
};
@interface UIView (GMEditingReveal)
@property(nonatomic) CGAffineTransform transform;
- (void)insertSubview:(UIView *)view belowSubview:(UIView *)siblingSubview;
- (void)insertSubview:(UIView *)view atIndex:(NSInteger)index;
- (BOOL)isDescendantOfView:(UIView *)view;
+ (void)animateWithDuration:(NSTimeInterval)duration animations:(void (^)(void))animations completion:(void (^)(BOOL finished))completion;
+ (void)animateWithDuration:(NSTimeInterval)duration delay:(NSTimeInterval)delay options:(UIViewAnimationOptions)options animations:(void (^)(void))animations completion:(void (^)(BOOL finished))completion;
@end
@interface UITableViewCell (GMEditingReuse)
- (void)prepareForReuse;
@end

// The native swipe action exposes title/image/backgroundColor, not a glass
// configuration. These public APIs are available if a native swipe is wanted.
typedef NSInteger UIContextualActionStyle;
enum { UIContextualActionStyleNormal = 0, UIContextualActionStyleDestructive = 1 };
typedef void (^UIContextualActionHandler)(UIContextualAction *action, __kindof UIView *sourceView, void (^completionHandler)(BOOL actionPerformed));
@interface UIContextualAction : NSObject
+ (instancetype)contextualActionWithStyle:(UIContextualActionStyle)style title:(NSString *)title handler:(UIContextualActionHandler)handler;
@property(nonatomic, readonly) UIContextualActionStyle style;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) UIColor *backgroundColor;
@property(nonatomic, copy) UIImage *image;
@end
@interface UISwipeActionsConfiguration : NSObject
+ (instancetype)configurationWithActions:(NSArray<UIContextualAction *> *)actions;
@property(nonatomic, copy, readonly) NSArray<UIContextualAction *> *actions;
@property(nonatomic) BOOL performsFirstActionWithFullSwipe;
@end

// VoiceOver access to the revealed actions. The notification typedef is a
// 32-bit unsigned integer, NOT NSUInteger (which is 64-bit on arm64).
typedef unsigned int UIAccessibilityNotifications;
extern UIAccessibilityNotifications const UIAccessibilityLayoutChangedNotification;
extern void UIAccessibilityPostNotification(UIAccessibilityNotifications notification, id argument);
@interface UIAccessibilityCustomAction : NSObject
- (instancetype)initWithName:(NSString *)name target:(id)target selector:(SEL)selector;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, weak) id target;
@property(nonatomic) SEL selector;
@end
@interface UIView (GMEditingAccessibility)
@property(nonatomic, strong) NSArray<UIAccessibilityCustomAction *> *accessibilityCustomActions;
@property(nonatomic) BOOL accessibilityElementsHidden;
@end

#endif
