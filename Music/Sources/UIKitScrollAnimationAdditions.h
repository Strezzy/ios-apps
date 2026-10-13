// Narrow public APIs used by Music's app-local scrolling entry effects.
// The Xcode build uses Apple's UIKit and QuartzCore SDK declarations instead.
#ifndef MUSIC_UIKIT_SCROLL_ANIMATION_ADDITIONS
#define MUSIC_UIKIT_SCROLL_ANIMATION_ADDITIONS

@interface CASpringAnimation : CABasicAnimation
@property CGFloat mass;
@property CGFloat stiffness;
@property CGFloat damping;
@property CGFloat initialVelocity;
@property(readonly) NSTimeInterval settlingDuration;
@end

@interface CALayer (GMScrollAnimationProperties)
@property float opacity;
@end

@interface CAAnimation (GMScrollSpringTiming)
@property float speed;
@end

@class UIEvent;
@interface UIView (GMScrollAnimationHitTesting)
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;
@end

@interface UITableView (GMScrollAnimationRows)
- (UITableViewCell *)cellForRowAtIndexPath:(NSIndexPath *)indexPath;
@end

@interface NSMutableArray<ObjectType> (GMScrollAnimationRecords)
- (void)removeObject:(ObjectType)object;
@end

extern NSString *const UIApplicationDidEnterBackgroundNotification;

#endif
