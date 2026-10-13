// Narrow public-API declarations for the Linux arm64 cross-build.
// An Xcode build uses Apple's SDK headers instead (see main.m).
#ifndef GLASS_MUSIC_MINI_SDK
#define GLASS_MUSIC_MINI_SDK
typedef _Bool BOOL;
typedef long NSInteger;
typedef unsigned long NSUInteger;
typedef double CGFloat;
typedef double NSTimeInterval;
typedef struct { CGFloat x,y; } CGPoint;
typedef struct { CGFloat width,height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;
typedef struct { CGFloat top,left,bottom,right; } UIEdgeInsets;
typedef struct { NSUInteger location,length; } NSRange;
typedef const void *CGColorRef;
#define YES ((BOOL)1)
#define NO ((BOOL)0)
#define nil ((id)0)
#define NULL ((void *)0)
#define NSNotFound ((NSInteger)0x7fffffffffffffffL)
static inline CGRect CGRectMake(CGFloat x,CGFloat y,CGFloat w,CGFloat h){return (CGRect){{x,y},{w,h}};}
static inline CGPoint CGPointMake(CGFloat x,CGFloat y){return (CGPoint){x,y};}
static inline CGSize CGSizeMake(CGFloat x,CGFloat y){return (CGSize){x,y};}
static inline UIEdgeInsets UIEdgeInsetsMake(CGFloat t,CGFloat l,CGFloat b,CGFloat r){return (UIEdgeInsets){t,l,b,r};}
static const CGRect CGRectZero={{0,0},{0,0}};
@class NSString, NSArray, NSDictionary, NSError, NSURL, NSData, NSNotification;
@protocol NSObject
- (BOOL)respondsToSelector:(SEL)selector;
@end
@protocol NSCopying @end
typedef struct { unsigned long state; id __unsafe_unretained *itemsPtr; unsigned long *mutationsPtr; unsigned long extra[5]; } NSFastEnumerationState;
@protocol NSFastEnumeration
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained *)buffer count:(NSUInteger)len;
@end
__attribute__((objc_root_class))
@interface NSObject <NSObject>
{
    // NSObject's real root layout contains its isa word. Clang can fold offsets
    // in direct subclasses to constants, so this word must never be omitted.
    Class isa;
}
+ (id)alloc; + (id)new; + (Class)class;
- (id)init; - (Class)class; - (BOOL)isKindOfClass:(Class)c;
- (BOOL)isEqual:(id)object; - (BOOL)respondsToSelector:(SEL)selector;
- (id)copy; - (id)mutableCopy;
@end
@interface NSString : NSObject <NSCopying>
@property(readonly) NSUInteger length;
@property(readonly) NSString *lastPathComponent;
@property(readonly) NSString *pathExtension;
@property(readonly) NSString *stringByDeletingPathExtension;
@property(readonly) NSString *lowercaseString;
+ (id)stringWithFormat:(NSString *)format,...;
- (id)initWithData:(NSData *)data encoding:(NSUInteger)encoding;
- (NSString *)stringByAppendingPathComponent:(NSString *)component;
- (NSString *)stringByAppendingString:(NSString *)string;
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)a withString:(NSString *)b;
- (BOOL)isEqualToString:(NSString *)other;
- (BOOL)hasPrefix:(NSString *)prefix;
- (NSInteger)localizedCaseInsensitiveCompare:(NSString *)string;
@end
@interface NSNumber : NSObject
+ (NSNumber *)numberWithDouble:(double)x;
+ (NSNumber *)numberWithFloat:(float)x;
+ (NSNumber *)numberWithInteger:(NSInteger)x;
+ (NSNumber *)numberWithUnsignedInteger:(NSUInteger)x;
+ (NSNumber *)numberWithInt:(int)x;
+ (NSNumber *)numberWithBool:(BOOL)x;
@property(readonly) double doubleValue;
@property(readonly) NSUInteger unsignedIntegerValue;
@end
@interface NSArray<ObjectType> : NSObject <NSCopying,NSFastEnumeration>
@property(readonly) NSUInteger count;
@property(readonly) ObjectType firstObject;
+ (id)array;
+ (id)arrayWithObjects:(const id [])objects count:(NSUInteger)count;
- (ObjectType)objectAtIndexedSubscript:(NSUInteger)idx;
- (NSArray *)sortedArrayUsingSelector:(SEL)selector;
- (BOOL)containsObject:(id)object;
@end
@interface NSMutableArray<ObjectType> : NSArray<ObjectType>
- (void)addObject:(ObjectType)object;
- (void)removeObjectAtIndex:(NSUInteger)index;
- (void)removeAllObjects;
@end
@interface NSDictionary<KeyType,ObjectType> : NSObject <NSCopying,NSFastEnumeration>
+ (id)dictionary;
+ (id)dictionaryWithObjects:(const id [])objects forKeys:(const id<NSCopying> [])keys count:(NSUInteger)count;
- (ObjectType)objectForKeyedSubscript:(KeyType)key;
@end
@interface NSMutableDictionary<KeyType,ObjectType> : NSDictionary<KeyType,ObjectType>
- (void)setObject:(ObjectType)obj forKeyedSubscript:(KeyType)key;
@end
@interface NSURL : NSObject <NSCopying>
@property(readonly) NSString *path;
@property(readonly) NSString *lastPathComponent;
@property(readonly) NSString *pathExtension;
+ (NSURL *)fileURLWithPath:(NSString *)path;
- (NSURL *)URLByAppendingPathComponent:(NSString *)component;
- (BOOL)startAccessingSecurityScopedResource;
- (void)stopAccessingSecurityScopedResource;
@end
@interface NSError : NSObject
@property(readonly) NSString *localizedDescription;
@end
@interface NSData : NSObject
+ (id)dataWithContentsOfURL:(NSURL *)url;
@end
@interface NSFileManager : NSObject
+ (id)defaultManager;
- (NSArray<NSURL *> *)URLsForDirectory:(NSUInteger)directory inDomains:(NSUInteger)domains;
- (BOOL)createDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)create attributes:(NSDictionary *)attributes error:(NSError **)error;
- (NSArray<NSString *> *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)fileExistsAtPath:(NSString *)path;
- (BOOL)copyItemAtURL:(NSURL *)source toURL:(NSURL *)dest error:(NSError **)error;
- (BOOL)removeItemAtURL:(NSURL *)url error:(NSError **)error;
@end
@interface NSBundle : NSObject
+ (NSBundle *)mainBundle;
- (NSURL *)URLForResource:(NSString *)name withExtension:(NSString *)extension;
@end
@interface NSIndexPath : NSObject
@property(readonly) NSInteger row;
@end
@interface NSThread : NSObject
+ (BOOL)isMainThread;
@end
@interface NSTimer : NSObject
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)interval target:(id)target selector:(SEL)selector userInfo:(id)info repeats:(BOOL)repeats;
- (void)invalidate;
@end
@interface NSNotification : NSObject
@property(readonly) NSDictionary *userInfo;
@end
@interface NSNotificationCenter : NSObject
+ (id)defaultCenter;
- (void)addObserver:(id)observer selector:(SEL)selector name:(NSString *)name object:(id)object;
- (void)removeObserver:(id)observer;
@end
extern Class NSClassFromString(NSString *name);
extern NSString *NSStringFromClass(Class cls);
extern SEL NSSelectorFromString(NSString *name);
typedef void (^dispatch_block_t)(void);
typedef struct dispatch_queue_s *dispatch_queue_t;
extern struct dispatch_queue_s _dispatch_main_q;
static inline dispatch_queue_t dispatch_get_main_queue(void){return &_dispatch_main_q;}
extern dispatch_queue_t dispatch_get_global_queue(long priority, unsigned long flags);
extern void dispatch_async(dispatch_queue_t queue, dispatch_block_t block);

@interface UIColor : NSObject
+ (UIColor *)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (UIColor *)whiteColor; + (UIColor *)blackColor; + (UIColor *)clearColor;
- (UIColor *)colorWithAlphaComponent:(CGFloat)alpha;
@property(readonly) CGColorRef CGColor;
@end
@interface UIFont : NSObject
+ (UIFont *)systemFontOfSize:(CGFloat)size weight:(CGFloat)weight;
+ (UIFont *)monospacedDigitSystemFontOfSize:(CGFloat)size weight:(CGFloat)weight;
@end
@interface CALayer : NSObject
+ (id)layer;
@property CGRect frame;
@property CGFloat cornerRadius;
@property CGFloat borderWidth;
@property CGColorRef borderColor;
@property CGColorRef backgroundColor;
@property CGColorRef shadowColor;
@property float shadowOpacity;
@property CGFloat shadowRadius;
@property CGSize shadowOffset;
@property BOOL masksToBounds;
- (void)addSublayer:(CALayer *)layer;
- (void)insertSublayer:(CALayer *)layer atIndex:(unsigned)index;
@end
@interface CAGradientLayer : CALayer
@property(copy) NSArray *colors;
@property(copy) NSArray *locations;
@property CGPoint startPoint;
@property CGPoint endPoint;
@property(copy) NSString *type;
@end
@interface UIView : NSObject
- (id)initWithFrame:(CGRect)frame;
@property CGRect frame;
@property CGRect bounds;
@property CGFloat alpha;
@property(getter=isHidden) BOOL hidden;
@property BOOL clipsToBounds;
@property(getter=isUserInteractionEnabled) BOOL userInteractionEnabled;
@property(getter=isOpaque) BOOL opaque;
@property NSInteger tag;
@property NSInteger contentMode;
@property NSUInteger autoresizingMask;
@property(strong) UIColor *backgroundColor;
@property(strong) UIColor *tintColor;
@property(readonly) CALayer *layer;
@property(readonly) UIEdgeInsets safeAreaInsets;
@property(copy) NSString *accessibilityLabel;
@property(copy) NSString *accessibilityValue;
@property(copy) NSString *accessibilityHint;
@property BOOL isAccessibilityElement;
- (void)addSubview:(UIView *)view;
- (void)removeFromSuperview;
- (UIView *)viewWithTag:(NSInteger)tag;
- (void)setNeedsLayout;
- (void)layoutIfNeeded;
@end
@interface UILabel : UIView
@property(copy) NSString *text;
@property(strong) UIFont *font;
@property(strong) UIColor *textColor;
@property NSInteger textAlignment;
@property NSInteger numberOfLines;
@property NSInteger lineBreakMode;
@property BOOL adjustsFontSizeToFitWidth;
@property CGFloat minimumScaleFactor;
@end
@interface UIImage : NSObject
+ (UIImage *)systemImageNamed:(NSString *)name;
+ (UIImage *)imageNamed:(NSString *)name;
+ (UIImage *)imageWithData:(NSData *)data;
@end
@interface UIImageView : UIView
- (id)initWithImage:(UIImage *)image;
@property(strong) UIImage *image;
@end
@interface UIControl : UIView
@property(getter=isEnabled) BOOL enabled;
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(NSUInteger)events;
@end
@interface UIButton : UIControl
+ (UIButton *)buttonWithType:(NSInteger)type;
@property(readonly) UILabel *titleLabel;
@property(readonly) UIImageView *imageView;
@property UIEdgeInsets contentEdgeInsets;
- (void)setTitle:(NSString *)title forState:(NSUInteger)state;
- (void)setTitleColor:(UIColor *)color forState:(NSUInteger)state;
- (void)setImage:(UIImage *)image forState:(NSUInteger)state;
@end
@interface UISlider : UIControl
@property float value;
@property float minimumValue;
@property float maximumValue;
@property(strong) UIColor *minimumTrackTintColor;
@property(strong) UIColor *maximumTrackTintColor;
@property(strong) UIColor *thumbTintColor;
@end
@interface UIVisualEffect : NSObject @end
@interface UIBlurEffect : UIVisualEffect
+ (id)effectWithStyle:(NSInteger)style;
@end
@interface UIVisualEffectView : UIView
- (id)initWithEffect:(UIVisualEffect *)effect;
@property(readonly) UIView *contentView;
@end
@interface UIScrollView : UIView
@property CGSize contentSize;
@property UIEdgeInsets contentInset;
@property BOOL showsVerticalScrollIndicator;
@property BOOL alwaysBounceVertical;
@end
@protocol UITableViewDataSource @end
@protocol UITableViewDelegate @end
@interface UITableView : UIScrollView
- (id)initWithFrame:(CGRect)frame style:(NSInteger)style;
@property(weak) id<UITableViewDataSource> dataSource;
@property(weak) id<UITableViewDelegate> delegate;
@property CGFloat rowHeight;
@property NSInteger separatorStyle;
@property(strong) UIView *tableFooterView;
- (void)reloadData;
- (id)dequeueReusableCellWithIdentifier:(NSString *)identifier;
- (void)deselectRowAtIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated;
@end
@interface UITableViewCell : UIView
- (id)initWithStyle:(NSInteger)style reuseIdentifier:(NSString *)identifier;
@property(readonly) UILabel *textLabel;
@property(readonly) UILabel *detailTextLabel;
@property(readonly) UIImageView *imageView;
@property(readonly) UIView *contentView;
@property NSInteger selectionStyle;
@property(strong) UIView *accessoryView;
@end
@interface UIViewController : NSObject
@property(strong) UIView *view;
@property(readonly) UIViewController *presentedViewController;
@property NSInteger overrideUserInterfaceStyle;
@property NSInteger modalPresentationStyle;
- (void)viewDidLoad;
- (void)viewDidLayoutSubviews;
- (void)viewSafeAreaInsetsDidChange;
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion;
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion;
@end
@interface UTType : NSObject @end
extern UTType *const UTTypeAudio;
@protocol UIDocumentPickerDelegate @end
@interface UIDocumentPickerViewController : UIViewController
- (id)initForOpeningContentTypes:(NSArray<UTType *> *)types asCopy:(BOOL)copy;
@property BOOL allowsMultipleSelection;
@property(weak) id<UIDocumentPickerDelegate> delegate;
@end
@interface UIAlertAction : NSObject
+ (id)actionWithTitle:(NSString *)title style:(NSInteger)style handler:(void (^)(UIAlertAction *action))handler;
@end
@interface UIAlertController : UIViewController
+ (id)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(NSInteger)style;
- (void)addAction:(UIAlertAction *)action;
@end
@interface UIScene : NSObject @end
@interface UIWindowScene : UIScene @end
@interface UISceneSession : NSObject
@property(readonly) NSString *role;
@end
@interface UISceneConnectionOptions : NSObject @end
@interface UISceneConfiguration : NSObject
- (id)initWithName:(NSString *)name sessionRole:(NSString *)role;
@property Class sceneClass;
@property Class delegateClass;
@end
@interface UIWindow : UIView
- (id)initWithWindowScene:(UIWindowScene *)windowScene;
@property(strong) UIViewController *rootViewController;
- (void)makeKeyAndVisible;
@end
@protocol UIApplicationDelegate @end
@protocol UIWindowSceneDelegate @end
@interface UIApplication : NSObject
+ (id)sharedApplication;
@end
extern int UIApplicationMain(int argc,char **argv,NSString *principalClassName,NSString *delegateClassName);

@protocol AVAudioPlayerDelegate @end
@interface AVAudioPlayer : NSObject
- (id)initWithContentsOfURL:(NSURL *)url error:(NSError **)error;
@property(weak) id<AVAudioPlayerDelegate> delegate;
@property NSTimeInterval currentTime;
@property(readonly) NSTimeInterval duration;
@property(readonly,getter=isPlaying) BOOL playing;
@property float volume;
- (BOOL)prepareToPlay;
- (BOOL)play;
- (void)pause;
- (void)stop;
@end
@interface AVAudioSession : NSObject
+ (id)sharedInstance;
- (BOOL)setCategory:(NSString *)category error:(NSError **)error;
- (BOOL)setActive:(BOOL)active error:(NSError **)error;
@end
extern NSString *const AVAudioSessionCategoryPlayback;
extern NSString *const AVAudioSessionInterruptionNotification;
extern NSString *const AVAudioSessionInterruptionTypeKey;
extern NSString *const AVAudioSessionInterruptionOptionKey;
extern NSString *const AVAudioSessionRouteChangeNotification;
extern NSString *const AVAudioSessionRouteChangeReasonKey;
@interface AVMetadataItem : NSObject
@property(readonly) NSString *commonKey;
@property(readonly) NSString *stringValue;
@property(readonly) NSData *dataValue;
@end
@interface AVURLAsset : NSObject
+ (id)URLAssetWithURL:(NSURL *)url options:(NSDictionary *)options;
@property(readonly) NSArray<AVMetadataItem *> *commonMetadata;
@end
@interface MPRemoteCommand : NSObject
@property BOOL enabled;
- (void)addTarget:(id)target action:(SEL)action;
@end
@interface MPRemoteCommandCenter : NSObject
+ (id)sharedCommandCenter;
@property(readonly) MPRemoteCommand *playCommand;
@property(readonly) MPRemoteCommand *pauseCommand;
@property(readonly) MPRemoteCommand *togglePlayPauseCommand;
@property(readonly) MPRemoteCommand *nextTrackCommand;
@property(readonly) MPRemoteCommand *previousTrackCommand;
@property(readonly) MPRemoteCommand *changePlaybackPositionCommand;
@end
@interface MPRemoteCommandEvent : NSObject @end
@interface MPChangePlaybackPositionCommandEvent : MPRemoteCommandEvent
@property(readonly) NSTimeInterval positionTime;
@end
@interface MPNowPlayingInfoCenter : NSObject
+ (MPNowPlayingInfoCenter *)defaultCenter;
@property(copy) NSDictionary *nowPlayingInfo;
@end
@interface MPMediaItemArtwork : NSObject
- (id)initWithBoundsSize:(CGSize)boundsSize requestHandler:(UIImage *(^)(CGSize size))requestHandler;
@end
extern NSString *const MPMediaItemPropertyTitle;
extern NSString *const MPMediaItemPropertyArtist;
extern NSString *const MPMediaItemPropertyPlaybackDuration;
extern NSString *const MPMediaItemPropertyArtwork;
extern NSString *const MPNowPlayingInfoPropertyElapsedPlaybackTime;
extern NSString *const MPNowPlayingInfoPropertyPlaybackRate;
extern NSString *const MPNowPlayingInfoPropertyDefaultPlaybackRate;
#import "UIKitTabsAdditions.h"
#import "UIKitAppearanceAdditions.h"
#import "UIKitEditingAdditions.h"
#import "UIKitMotionAdditions.h"
#import "UIKitPlaybackAdditions.h"
#import "UIKitRowPolishAdditions.h"
#import "UIKitLyricsAdditions.h"
#import "UIKitDynamicAdditions.h"
#import "UIKitDockPolishAdditions.h"
#import "UIKitAlbumImportAdditions.h"
#import "UIKitPersonalizationAdditions.h"
#import "UIKitNativeDockAdditions.h"
#import "UIKitImportMenuAdditions.h"
#import "UIKitScrollAnimationAdditions.h"
#import "UIKitScrollSettingsAdditions.h"
#import "UIKitCDCaseAdditions.h"
#endif
