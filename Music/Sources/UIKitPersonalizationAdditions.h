// Narrow public UIKit/CoreText declarations for the Linux arm64 build.
// Xcode uses the real framework headers instead of this file.
#ifndef MUSIC_UIKIT_PERSONALIZATION_ADDITIONS
#define MUSIC_UIKIT_PERSONALIZATION_ADDITIONS

@class UIFontDescriptor, UIFontPickerViewControllerConfiguration, UIFontPickerViewController;
typedef unsigned int UIFontDescriptorSymbolicTraits;
extern NSString *const UIFontDescriptorTraitsAttribute;
extern NSString *const UIFontWeightTrait;
extern NSString *const NSFontAttributeName;
@interface UIFontDescriptor : NSObject <NSCopying>
@property(nonatomic, readonly) NSString *postscriptName;
@property(nonatomic, readonly) UIFontDescriptorSymbolicTraits symbolicTraits;
- (id)objectForKey:(NSString *)attribute;
- (UIFontDescriptor *)fontDescriptorByAddingAttributes:(NSDictionary<NSString *, id> *)attributes;
@end
@interface UIFont (GMPersonalizationFonts)
+ (UIFont *)fontWithName:(NSString *)fontName size:(CGFloat)fontSize;
+ (UIFont *)fontWithDescriptor:(UIFontDescriptor *)descriptor size:(CGFloat)pointSize;
@property(nonatomic, readonly, strong) NSString *fontName;
@property(nonatomic, readonly, strong) UIFontDescriptor *fontDescriptor;
@property(nonatomic, readonly) CGFloat pointSize;
@end
@interface UIFontPickerViewControllerConfiguration : NSObject <NSCopying>
@property(nonatomic) BOOL includeFaces;
@property(nonatomic) BOOL displayUsingSystemFont;
@property(nonatomic) UIFontDescriptorSymbolicTraits filteredTraits;
@end
@protocol UIFontPickerViewControllerDelegate <NSObject>
- (void)fontPickerViewControllerDidPickFont:(UIFontPickerViewController *)viewController;
- (void)fontPickerViewControllerDidCancel:(UIFontPickerViewController *)viewController;
@end
@interface UIFontPickerViewController : UIViewController
- (instancetype)initWithConfiguration:(UIFontPickerViewControllerConfiguration *)configuration;
@property(nonatomic, readonly, copy) UIFontPickerViewControllerConfiguration *configuration;
@property(nonatomic, weak) id<UIFontPickerViewControllerDelegate> delegate;
@property(nonatomic, strong) UIFontDescriptor *selectedFontDescriptor;
@end

@interface NSMapTable<KeyType, ObjectType> : NSObject
+ (NSMapTable<KeyType, ObjectType> *)weakToStrongObjectsMapTable;
- (ObjectType)objectForKey:(KeyType)key;
- (void)setObject:(ObjectType)object forKey:(KeyType)key;
@end
@interface UIView (GMPersonalizationTraversal)
@property(nonatomic, readonly, copy) NSArray<UIView *> *subviews;
@property(nonatomic, readonly) id nextResponder;
@end
@interface UINavigationBar (GMPersonalizationText)
@property(nonatomic, copy) NSDictionary<NSString *, id> *titleTextAttributes;
@property(nonatomic, copy) NSDictionary<NSString *, id> *largeTitleTextAttributes;
@end
typedef NSDictionary<NSString *, id> *(^UIConfigurationTextAttributesTransformer)(NSDictionary<NSString *, id> *);
@interface UIButtonConfiguration (GMPersonalizationText)
@property(nonatomic, copy) UIConfigurationTextAttributesTransformer titleTextAttributesTransformer;
@end

typedef const struct __CFArray *CFArrayRef;
typedef const struct __CFError *CFErrorRef;
typedef const struct __CTFontDescriptor *CTFontDescriptorRef;
typedef long CFIndex;
typedef unsigned int CTFontManagerScope;
enum { kCTFontManagerScopeProcess = 1 };
extern _Bool CTFontManagerRegisterFontsForURL(CFURLRef fontURL, CTFontManagerScope scope, CFErrorRef *error);
extern _Bool CTFontManagerUnregisterFontsForURL(CFURLRef fontURL, CTFontManagerScope scope, CFErrorRef *error);
extern CFArrayRef CTFontManagerCreateFontDescriptorsFromURL(CFURLRef fileURL);
extern CFTypeRef CTFontDescriptorCopyAttribute(CTFontDescriptorRef descriptor, CFStringRef attribute);
extern const CFStringRef kCTFontNameAttribute;
extern CFIndex CFArrayGetCount(CFArrayRef array);
extern const void *CFArrayGetValueAtIndex(CFArrayRef array, CFIndex index);

@interface UIApplication (GMPersonalizationIcons)
@property(nonatomic, readonly) BOOL supportsAlternateIcons;
@property(nonatomic, readonly) NSString *alternateIconName;
- (void)setAlternateIconName:(NSString *)alternateIconName completionHandler:(void (^)(NSError *error))completionHandler;
@end

@class UIGraphicsImageRendererFormat, UIGraphicsImageRendererContext;
@interface UIGraphicsRendererFormat : NSObject <NSCopying> @end
@interface UIGraphicsImageRendererFormat : UIGraphicsRendererFormat
+ (instancetype)defaultFormat;
@property(nonatomic) CGFloat scale;
@property(nonatomic) BOOL opaque;
@end
@interface UIGraphicsRendererContext : NSObject
- (void)fillRect:(CGRect)rect;
@end
@interface UIGraphicsImageRendererContext : UIGraphicsRendererContext @end
@interface UIGraphicsRenderer : NSObject @end
@interface UIGraphicsImageRenderer : UIGraphicsRenderer
- (instancetype)initWithSize:(CGSize)size format:(UIGraphicsImageRendererFormat *)format;
- (UIImage *)imageWithActions:(void (^)(UIGraphicsImageRendererContext *rendererContext))actions;
@end
@interface UIImage (GMPersonalizationDrawing)
- (void)drawInRect:(CGRect)rect;
@end
@interface UIColor (GMPersonalizationDrawing)
- (void)setFill;
@end
extern NSData *UIImagePNGRepresentation(UIImage *image);

@class UIActivity, UIPopoverPresentationController;
@interface UIActivityViewController : UIViewController
- (instancetype)initWithActivityItems:(NSArray *)activityItems applicationActivities:(NSArray<UIActivity *> *)applicationActivities;
@end
@interface UIPopoverPresentationController : UIPresentationController
@property(nonatomic, strong) UIView *sourceView;
@property(nonatomic) CGRect sourceRect;
@end
@interface UIViewController (GMPersonalizationSharing)
@property(nonatomic, readonly) UIPopoverPresentationController *popoverPresentationController;
@end

#endif
