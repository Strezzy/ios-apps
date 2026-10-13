// Modified adaptation of Cask 3 by Ryan Nair, Apache License 2.0.
// Cask 3 is inspired by the original Cask by Ryan Petrich.
// Pinned source: f82e252334d69a151afa8f20db3d59e7a84ee592, Sources/Cask.swift.
// Full source and license are included in Support/Upstream/Cask3.
// MODIFICATIONS: public app-local animation hosts replace system hooks;
// Rotate's radians and Shake's key-time mismatch are corrected; Bounce is
// time-scaled to settle in .5 seconds; Glitch is bounded; colors use a subtle
// host-local tint. Visibility, reuse, touch, and accessibility resets are added.
#import "MusicScrollAnimations.h"
#import "MusicScrollSettings.h"

NSArray<NSString *> *GMScrollPresetIdentifiers(void) {
    return @[@"fade",@"flip",@"bounce",@"color",@"permanentColor",@"glitch",@"helix",@"rotate",
             @"zoom",@"drop",@"stretch",@"slide",@"shake",@"swing",@"jiggle"];
}
NSString *GMScrollPresetName(NSString *identifier) {
    NSArray *identifiers = GMScrollPresetIdentifiers();
    NSArray *names = @[@"Fade",@"Flip",@"Bounce",@"Color",@"Permanent Color",@"Glitch",@"Helix",@"Rotate",
                       @"Zoom",@"Drop",@"Stretch",@"Slide",@"Shake",@"Swing",@"Jiggle"];
    for (NSUInteger index=0;index<identifiers.count;index++)
        if ([identifiers[index] isEqualToString:identifier]) return names[index];
    return @"Fade";
}
NSString *GMScrollPresetDetail(NSString *identifier) {
    NSDictionary *details = @{
        @"fade":@"Rows fade into view.",
        @"flip":@"A half-turn around the horizontal axis.",
        @"bounce":@"A narrow row springs out to full width.",
        @"color":@"A soft random color fades behind the row.",
        @"permanentColor":@"A soft row color cycles while it stays visible.",
        @"glitch":@"A bounded, springy stretch in both directions.",
        @"helix":@"A half-turn around the vertical axis.",
        @"rotate":@"One full turn into place.",
        @"zoom":@"Content shrinks from five times its normal size.",
        @"drop":@"Content drops into place from above.",
        @"stretch":@"A narrow row eases out to full width.",
        @"slide":@"Content slides in from the right.",
        @"shake":@"A short side-to-side shake.",
        @"swing":@"A wider side-to-side swing.",
        @"jiggle":@"A small rotational jiggle."
    };
    return identifier ? (details[identifier] ?: details[@"fade"]) : details[@"fade"];
}

static const NSTimeInterval GMScrollEntryDuration = .5;
static NSString *const GMScrollEntryOpacityKey = @"Music.ScrollEntry.Opacity";
static NSString *const GMScrollEntryHorizontalKey = @"Music.ScrollEntry.Horizontal";
static NSString *const GMScrollEntryVerticalKey = @"Music.ScrollEntry.Vertical";
static NSString *const GMScrollEntryRotationKey = @"Music.ScrollEntry.Rotation";
static NSString *const GMScrollEntryColorKey = @"Music.ScrollEntry.Color";

static CABasicAnimation *GMScrollBasic(NSString *path, id from, id to, BOOL linear) {
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:path];
    animation.fromValue = from; animation.toValue = to;
    animation.duration = GMScrollEntryDuration;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:linear ? @"linear" : @"easeOut"];
    return animation;
}
static CAKeyframeAnimation *GMScrollKeyframes(NSString *path, NSArray<NSNumber *> *values,
                                             NSArray<NSNumber *> *times, BOOL ease) {
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:path];
    animation.values = values; animation.keyTimes = times;
    animation.calculationMode = @"linear";
    animation.duration = GMScrollEntryDuration;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:ease ? @"easeInEaseOut" : @"linear"];
    return animation;
}

@interface GMScrollAnimationView ()
@property(nonatomic, readwrite, strong) UIView *contentView;
@property(nonatomic, strong) UIView *colorView;
@property(nonatomic) CGSize animationSize;
- (void)animationEnvironmentChanged:(NSNotification *)notification;
@end

@implementation GMScrollAnimationView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor]; self.opaque = NO;
    self.clipsToBounds = YES;
    self.colorView = [[UIView alloc] initWithFrame:self.bounds];
    self.colorView.backgroundColor = [UIColor clearColor];
    self.colorView.userInteractionEnabled = NO; self.colorView.accessibilityElementsHidden = YES;
    self.contentView = [[UIView alloc] initWithFrame:self.bounds];
    self.contentView.backgroundColor = [UIColor clearColor];
    [self addSubview:self.colorView]; [self addSubview:self.contentView];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(animationEnvironmentChanged:)
                   name:GMScrollSettingsDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(animationEnvironmentChanged:)
                   name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(animationEnvironmentChanged:)
                   name:UIApplicationDidEnterBackgroundNotification object:nil];
    return self;
}
- (void)animationEnvironmentChanged:(NSNotification *)notification {
    if (![NSThread isMainThread]) {
        __weak GMScrollAnimationView *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(),^{ [weakSelf resetScrollAnimation]; });
        return;
    }
    [self resetScrollAnimation];
}
- (void)resetScrollAnimation {
    // These keys belong only to this host. The waveform's child layers and
    // its independently running pulse are never inspected or interrupted.
    CALayer *layer = self.contentView.layer;
    [layer removeAnimationForKey:GMScrollEntryOpacityKey];
    [layer removeAnimationForKey:GMScrollEntryHorizontalKey];
    [layer removeAnimationForKey:GMScrollEntryVerticalKey];
    [layer removeAnimationForKey:GMScrollEntryRotationKey];
    [self.colorView.layer removeAnimationForKey:GMScrollEntryColorKey];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    [layer setAffineTransform:CGAffineTransformIdentity]; layer.opacity = 1;
    self.colorView.layer.backgroundColor = [UIColor clearColor].CGColor;
    [CATransaction commit];
}
- (void)animateWithPreset:(NSString *)presetIdentifier {
    [self resetScrollAnimation];
    if (!self.window || UIAccessibilityIsReduceMotionEnabled() || UIAccessibilityPrefersCrossFadeTransitions()) return;
    [self layoutIfNeeded];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    if (!(width > 0 && height > 0)) return;
    self.animationSize = self.bounds.size;
    NSString *preset = presetIdentifier && [GMScrollPresetIdentifiers() containsObject:presetIdentifier] ? presetIdentifier : @"fade";
    CALayer *layer = self.contentView.layer;
    const double pi = 3.14159265358979323846;
    if ([preset isEqualToString:@"fade"]) {
        [layer addAnimation:GMScrollBasic(@"opacity",@0,@1,NO) forKey:GMScrollEntryOpacityKey];
    } else if ([preset isEqualToString:@"flip"] || [preset isEqualToString:@"helix"]) {
        // Cask's Helix translates along y around a y-axis rotation. Those
        // translations cancel; the faithful result is a pi y rotation.
        NSString *path = [preset isEqualToString:@"flip"] ? @"transform.rotation.x" : @"transform.rotation.y";
        [layer addAnimation:GMScrollBasic(path,@(pi),@0,NO) forKey:GMScrollEntryRotationKey];
    } else if ([preset isEqualToString:@"bounce"]) {
        CASpringAnimation *spring = [CASpringAnimation animationWithKeyPath:@"transform.scale.x"];
        spring.fromValue = @.01; spring.toValue = @1;
        spring.mass = 1; spring.stiffness = 144; spring.damping = 12;
        spring.initialVelocity = 10;
        // CASpring damping is a physical coefficient: 12/(2*sqrt(144))=.5.
        // Run the complete settled trajectory in the requested half-second,
        // rather than cutting a still-displaced spring at an arbitrary time.
        spring.duration = spring.settlingDuration;
        spring.speed = (float)(spring.duration/GMScrollEntryDuration);
        [layer addAnimation:spring forKey:GMScrollEntryHorizontalKey];
    } else if ([preset isEqualToString:@"color"] || [preset isEqualToString:@"permanentColor"]) {
        UIColor *color = [UIColor colorWithRed:arc4random_uniform(256)/255.0
            green:arc4random_uniform(256)/255.0 blue:arc4random_uniform(256)/255.0 alpha:.22];
        UIColor *clear = [color colorWithAlphaComponent:0];
        CABasicAnimation *animation = GMScrollBasic(@"backgroundColor",(__bridge id)color.CGColor,
                                                     (__bridge id)clear.CGColor,NO);
        if ([preset isEqualToString:@"permanentColor"]) {
            animation.autoreverses = YES; animation.repeatCount = __builtin_inff();
            animation.timingFunction = [CAMediaTimingFunction functionWithName:@"linear"];
        }
        [self.colorView.layer addAnimation:animation forKey:GMScrollEntryColorKey];
    } else if ([preset isEqualToString:@"glitch"]) {
        // Preserve the two-axis spring character without the upstream zero-
        // damping oscillation. It stays between .3 and 1.2, with no flashing.
        NSArray *times = @[@0,@.18,@.36,@.55,@.78,@1];
        [layer addAnimation:GMScrollKeyframes(@"transform.scale.x",@[@.3,@1.2,@.82,@1.1,@.96,@1],times,YES)
                    forKey:GMScrollEntryHorizontalKey];
        [layer addAnimation:GMScrollKeyframes(@"transform.scale.y",@[@.5,@1.14,@.88,@1.06,@.98,@1],times,YES)
                    forKey:GMScrollEntryVerticalKey];
    } else if ([preset isEqualToString:@"rotate"]) {
        // Correct Cask's 360-radians endpoint. Scalar angle keyframes retain
        // the intended full turn; a 2*pi affine matrix alone is identity.
        [layer addAnimation:GMScrollKeyframes(@"transform.rotation.z",@[@(2*pi),@(1.5*pi),@(pi),@(.5*pi),@0],nil,YES)
                    forKey:GMScrollEntryRotationKey];
    } else if ([preset isEqualToString:@"zoom"]) {
        [layer addAnimation:GMScrollBasic(@"transform.scale.x",@5,@1,YES) forKey:GMScrollEntryHorizontalKey];
        [layer addAnimation:GMScrollBasic(@"transform.scale.y",@5,@1,YES) forKey:GMScrollEntryVerticalKey];
    } else if ([preset isEqualToString:@"drop"]) {
        [layer addAnimation:GMScrollBasic(@"transform.translation.y",@(-150),@0,NO) forKey:GMScrollEntryVerticalKey];
    } else if ([preset isEqualToString:@"stretch"]) {
        [layer addAnimation:GMScrollBasic(@"transform.scale.x",@.01,@1,NO) forKey:GMScrollEntryHorizontalKey];
    } else if ([preset isEqualToString:@"slide"]) {
        [layer addAnimation:GMScrollBasic(@"transform.translation.x",@(width),@0,NO) forKey:GMScrollEntryHorizontalKey];
    } else if ([preset isEqualToString:@"shake"]) {
        // Upstream has eight values but nine key times. Evenly distribute
        // its unchanged eight values instead of supplying a mismatched array.
        [layer addAnimation:GMScrollKeyframes(@"transform.translation.x",@[@0,@10,@(-10),@10,@(-5),@5,@(-5),@0],nil,NO)
                    forKey:GMScrollEntryHorizontalKey];
    } else if ([preset isEqualToString:@"swing"]) {
        [layer addAnimation:GMScrollKeyframes(@"transform.translation.x",@[@0,@40,@(-50),@30,@0],@[@0,@.16,@.5,@.83,@1],NO)
                    forKey:GMScrollEntryHorizontalKey];
    } else if ([preset isEqualToString:@"jiggle"]) {
        [layer addAnimation:GMScrollKeyframes(@"transform.rotation.z",@[@0,@(-.075),@.075,@(-.075),@.075,@0],nil,YES)
                    forKey:GMScrollEntryRotationKey];
    }
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    if (self.animationSize.width != size.width || self.animationSize.height != size.height) {
        [self resetScrollAnimation]; self.animationSize = size;
    }
    self.contentView.frame = self.bounds; self.colorView.frame = self.bounds;
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // Real controls use their final model geometry. A new touch settles only
    // this visual entry effect before UIKit resolves its normal target.
    if (point.x >= 0 && point.y >= 0 && point.x <= self.bounds.size.width && point.y <= self.bounds.size.height)
        [self resetScrollAnimation];
    return [super hitTest:point withEvent:event];
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) [self resetScrollAnimation];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end
