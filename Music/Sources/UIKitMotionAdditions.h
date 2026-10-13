// Narrow public declarations for the Linux arm64 build. Include last in
// MiniSDK.h; real Apple SDK builds use UIKit/QuartzCore framework headers.
// Verified against Apple's public iOS 26 SDK headers and current DocC pages.
#ifndef GLASS_MUSIC_UIKIT_MOTION_ADDITIONS
#define GLASS_MUSIC_UIKIT_MOTION_ADDITIONS

@class UIGlassContainerEffect, UICornerConfiguration;
@class UIViewPropertyAnimator;
@class CAAnimation, CAPropertyAnimation, CAKeyframeAnimation;
@class CAMediaTimingFunction, CATransaction;

// UIGlassEffect's regular/clear styles and UIVisualEffectView's init, contentView
// and effect property are already declared in the preceding headers.
// iOS 26+: resolve both new classes dynamically with NSClassFromString.
// Nest UIGlassEffect-backed views inside the container effect's contentView.
// Keep effect views AND their superviews at alpha 1; move/resize the children
// to merge/separate glass. The spacing is the distance where merging begins.
@interface UIGlassContainerEffect : UIVisualEffect
@property(nonatomic) CGFloat spacing;
@end

@interface UICornerConfiguration : NSObject <NSCopying>
+ (instancetype)capsuleConfiguration;
+ (instancetype)capsuleConfigurationWithMaximumRadius:(CGFloat)maximumRadius;
@end
@interface UIView (GMMotionGlassCorners)
// iOS 26+: guard setCornerConfiguration: on the receiver.
@property(nonatomic, copy) UICornerConfiguration *cornerConfiguration;
@end

// UIScrollView tracking (all available before the iOS 16 minimum).
// Read adjustedContentInset to recognize the actual top including large titles.
@interface UIScrollView (GMMotionScrolling)
@property(nonatomic, readonly) UIEdgeInsets adjustedContentInset;
@property(nonatomic, readonly, getter=isTracking) BOOL tracking;
@property(nonatomic, readonly, getter=isDragging) BOOL dragging;
@property(nonatomic, readonly, getter=isDecelerating) BOOL decelerating;
@property(nonatomic, getter=isScrollEnabled) BOOL scrollEnabled;
- (void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated;
@end
@interface UITableView (GMMotionVisibleRows)
@property(nonatomic, readonly) NSArray<__kindof UITableViewCell *> *visibleCells;
@end

typedef NSUInteger NSDirectionalRectEdge;
enum {
    NSDirectionalRectEdgeNone = 0,
    NSDirectionalRectEdgeTop = 1UL << 0,
    NSDirectionalRectEdgeLeading = 1UL << 1,
    NSDirectionalRectEdgeBottom = 1UL << 2,
    NSDirectionalRectEdgeTrailing = 1UL << 3,
    NSDirectionalRectEdgeAll = 15
};
@interface UIViewController (GMMotionContentScroll)
// iOS 15+: explicitly register a custom controller's main scrolling content.
// set accepts combined edges; contentScrollViewForEdge: requires ONE edge.
- (void)setContentScrollView:(UIScrollView *)scrollView forEdge:(NSDirectionalRectEdge)edge;
- (UIScrollView *)contentScrollViewForEdge:(NSDirectionalRectEdge)edge;
@end

@protocol UITabBarControllerDelegate <NSObject>
@optional
- (BOOL)tabBarController:(UITabBarController *)tabBarController shouldSelectViewController:(UIViewController *)viewController;
- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController;
@end
@interface UITabBarController (GMMotionTabVisibility)
@property(nonatomic, weak) id<UITabBarControllerDelegate> delegate;
// Apple's property is assign; the viewControllers array retains the child.
@property(nonatomic, assign) __kindof UIViewController *selectedViewController;
// iOS 18+: this controls visibility, not the native minimized state.
// There is no public setMinimized:/expand selector in the iOS 26 API.
@property(nonatomic, getter=isTabBarHidden) BOOL tabBarHidden;
- (void)setTabBarHidden:(BOOL)hidden animated:(BOOL)animated;
@end
// Existing public enums in UIKitTabsAdditions.h remain authoritative:
// MinimizeBehavior Automatic=0, NEVER=1, OnScrollDown=2, OnScrollUp=3.
// AccessoryEnvironment Unspecified=0, None=1, Regular=2, Inline=3.

// Interruptible spring animations, available on all supported versions.
typedef NSInteger UIViewAnimatingState;
enum {
    UIViewAnimatingStateInactive = 0,
    UIViewAnimatingStateActive = 1,
    UIViewAnimatingStateStopped = 2
};
typedef NSInteger UIViewAnimatingPosition;
enum {
    UIViewAnimatingPositionEnd = 0,
    UIViewAnimatingPositionStart = 1,
    UIViewAnimatingPositionCurrent = 2
};
typedef NSInteger UIViewAnimationCurve;
enum {
    UIViewAnimationCurveEaseInOut = 0,
    UIViewAnimationCurveEaseIn = 1,
    UIViewAnimationCurveEaseOut = 2,
    UIViewAnimationCurveLinear = 3
};
@interface UIViewPropertyAnimator : NSObject <NSCopying>
- (instancetype)initWithDuration:(NSTimeInterval)duration dampingRatio:(CGFloat)ratio animations:(void (^)(void))animations;
- (instancetype)initWithDuration:(NSTimeInterval)duration curve:(UIViewAnimationCurve)curve animations:(void (^)(void))animations;
@property(nonatomic, readonly) UIViewAnimatingState state;
@property(nonatomic, readonly, getter=isRunning) BOOL running;
@property(nonatomic, getter=isReversed) BOOL reversed;
@property(nonatomic) CGFloat fractionComplete;
@property(nonatomic, getter=isUserInteractionEnabled) BOOL userInteractionEnabled;
@property(nonatomic) BOOL scrubsLinearly;
- (void)startAnimation;
- (void)pauseAnimation;
- (void)stopAnimation:(BOOL)withoutFinishing;
- (void)finishAnimationAtPosition:(UIViewAnimatingPosition)finalPosition;
- (void)addAnimations:(void (^)(void))animation;
- (void)addCompletion:(void (^)(UIViewAnimatingPosition finalPosition))completion;
@end
// On interruption, stopAnimation:NO updates the model to its rendered values
// and enters Stopped. Only then finishAnimationAtPosition:Current. Read the
// app-owned foreground's transform.tx afterwards to continue without a jump.
// Completion blocks should ignore Current and stale animator identities.

@interface UIView (GMMotionAnimation)
+ (void)performWithoutAnimation:(void (^)(void))actionsWithoutAnimation;
+ (void)animateWithDuration:(NSTimeInterval)duration delay:(NSTimeInterval)delay usingSpringWithDamping:(CGFloat)dampingRatio initialSpringVelocity:(CGFloat)velocity options:(UIViewAnimationOptions)options animations:(void (^)(void))animations completion:(void (^)(BOOL finished))completion;
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;
- (UIView *)snapshotViewAfterScreenUpdates:(BOOL)afterUpdates;
- (void)didMoveToWindow;
- (void)tintColorDidChange;
@end

// QuartzCore keyframes for the playback indicator. Every API below predates
// iOS 16. repeatCount is a 32-bit float; duration is a 64-bit time interval.
typedef NSString *CAAnimationCalculationMode;
typedef NSString *CAMediaTimingFunctionName;
@interface CAMediaTimingFunction : NSObject
+ (instancetype)functionWithName:(CAMediaTimingFunctionName)name;
@end
extern CAMediaTimingFunctionName const kCAMediaTimingFunctionLinear;
extern CAMediaTimingFunctionName const kCAMediaTimingFunctionEaseInEaseOut;

@interface CAAnimation : NSObject <NSCopying>
@property NSTimeInterval duration;
@property float repeatCount;
@property BOOL autoreverses;
@property(strong) CAMediaTimingFunction *timingFunction;
@end
@interface CAPropertyAnimation : CAAnimation
+ (instancetype)animationWithKeyPath:(NSString *)path;
@property(copy) NSString *keyPath;
@end
@interface CAKeyframeAnimation : CAPropertyAnimation
@property(copy) NSArray *values;
@property(copy) NSArray<NSNumber *> *keyTimes;
@property(copy) NSArray<CAMediaTimingFunction *> *timingFunctions;
@property(copy) CAAnimationCalculationMode calculationMode;
@end
extern CAAnimationCalculationMode const kCAAnimationLinear;

@interface CALayer (GMMotionLayers)
@property CGRect bounds;
@property CGPoint position;
@property CGPoint anchorPoint;
- (instancetype)presentationLayer;
- (CGAffineTransform)affineTransform;
- (void)setAffineTransform:(CGAffineTransform)transform;
- (void)addAnimation:(CAAnimation *)animation forKey:(NSString *)key;
- (void)removeAnimationForKey:(NSString *)key;
- (void)removeAllAnimations;
@end
@interface CATransaction : NSObject
+ (void)begin;
+ (void)commit;
+ (void)setDisableActions:(BOOL)flag;
@end

// Foundation notification (NSString *), not a numeric accessibility event.
// UIAccessibilityIsReduceMotionEnabled is already in Appearance additions.
extern NSString *const UIAccessibilityReduceMotionStatusDidChangeNotification;

#endif
