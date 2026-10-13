// Four compositor-driven bars; no per-cell timer or playback-engine changes.
#import "PlaybackIndicator.h"

static NSString *const GMPlaybackPulseKey = @"GMPlaybackPulse";

@interface GMPlaybackIndicatorView ()
@property(nonatomic, copy) NSArray<CALayer *> *barLayers;
@property(nonatomic) BOOL configured;
@property(nonatomic) BOOL playing;
@property(nonatomic) BOOL animating;
@property(nonatomic) CGFloat laidOutWidth;
@property(nonatomic) CGFloat laidOutHeight;
@property(nonatomic) CGFloat maximumBarHeight;
- (void)updateBarGeometry;
- (void)updateBarColors;
- (void)syncMotion;
- (void)stopMotion;
@end

@implementation GMPlaybackIndicatorView
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(frame.size.width > 0)) frame.size.width = 22;
    if (!(frame.size.height > 0)) frame.size.height = 22;
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO; self.userInteractionEnabled = NO;
    NSMutableArray<CALayer *> *bars = [NSMutableArray array];
    for (NSUInteger index = 0; index < 4; index++) {
        CALayer *bar = [CALayer layer];
        bar.anchorPoint = CGPointMake(.5,.5);
        [self.layer addSublayer:bar];
        [bars addObject:bar];
    }
    self.barLayers = bars;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(motionPreferenceChanged:)
                                                 name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
    [self reset];
    return self;
}

- (CGSize)intrinsicContentSize { return CGSizeMake(22,22); }

- (void)configurePlaying:(BOOL)playing {
    BOOL changed = !self.configured || self.playing != playing;
    self.configured = YES; self.playing = playing;
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = playing ? @"Playing" : @"Paused";
    self.hidden = NO;
    if (changed) [self updateBarGeometry];
    [self syncMotion];
}

- (void)reset {
    self.configured = NO; self.playing = NO;
    [self stopMotion];
    self.hidden = YES;
    self.isAccessibilityElement = NO;
    self.accessibilityLabel = nil;
    self.accessibilityValue = nil;
    [self updateBarGeometry];
}

- (void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
    [self syncMotion];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self updateBarGeometry];
    [self syncMotion];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateBarGeometry];
    [self syncMotion];
}

- (void)tintColorDidChange {
    [super tintColorDidChange];
    [self updateBarColors];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateBarColors];
}

- (void)motionPreferenceChanged:(NSNotification *)notification {
    (void)notification;
    [self syncMotion];
}

- (void)updateBarColors {
    UIColor *color = self.tintColor ?: [UIColor labelColor];
    color = [color resolvedColorWithTraitCollection:self.traitCollection];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (CALayer *bar in self.barLayers) bar.backgroundColor = color.CGColor;
    [CATransaction commit];
}

- (void)updateBarGeometry {
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    BOOL sizeChanged = width != self.laidOutWidth || height != self.laidOutHeight;
    if (sizeChanged && self.animating) [self stopMotion];
    self.laidOutWidth = width; self.laidOutHeight = height;
    CGFloat side = width < height ? width : height;
    if (!(side > 0)) { self.maximumBarHeight = 0; return; }
    CGFloat barWidth = side * (3.0/22.0), gap = side * (2.0/22.0);
    self.maximumBarHeight = side * (16.0/22.0);
    CGFloat startX = (width - (barWidth*4 + gap*3)) * .5;
    const CGFloat quiet[4] = {.30,.50,.36,.60};
    const CGFloat active[4] = {.52,.90,.70,.42};
    UIColor *color = self.tintColor ?: [UIColor labelColor];
    color = [color resolvedColorWithTraitCollection:self.traitCollection];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (NSUInteger index = 0; index < self.barLayers.count; index++) {
        CALayer *bar = self.barLayers[index];
        CGFloat ratio = self.playing ? active[index] : quiet[index];
        bar.bounds = CGRectMake(0,0,barWidth,self.maximumBarHeight*ratio);
        bar.position = CGPointMake(startX + index*(barWidth+gap) + barWidth*.5,height*.5);
        bar.cornerRadius = barWidth*.5;
        bar.backgroundColor = color.CGColor;
    }
    [CATransaction commit];
}

- (void)stopMotion {
    for (CALayer *bar in self.barLayers) [bar removeAnimationForKey:GMPlaybackPulseKey];
    self.animating = NO;
}

- (void)syncMotion {
    BOOL shouldAnimate = self.configured && self.playing && self.window && !self.hidden &&
        self.maximumBarHeight > 0 && self.barLayers.count == 4 && !UIAccessibilityIsReduceMotionEnabled();
    if (!shouldAnimate) {
        if (self.animating) [self stopMotion];
        return;
    }
    if (self.animating) return;
    const CGFloat pulses[4][7] = {
        {.52,.95,.38,.80,.45,.72,.52},
        {.90,.40,.68,1.0,.50,.76,.90},
        {.70,.32,.90,.48,.80,.42,.70},
        {.42,.74,.38,.90,.52,.98,.42}
    };
    const NSTimeInterval durations[4] = {.94,1.18,1.06,1.30};
    NSArray<NSNumber *> *times = @[@0,@.16,@.34,@.50,@.68,@.84,@1];
    CAMediaTimingFunction *ease = [CAMediaTimingFunction functionWithName:@"easeInEaseOut"];
    NSArray<CAMediaTimingFunction *> *curves = @[ease,ease,ease,ease,ease,ease];
    for (NSUInteger index = 0; index < self.barLayers.count; index++) {
        NSMutableArray<NSNumber *> *heights = [NSMutableArray array];
        for (NSUInteger point = 0; point < 7; point++)
            [heights addObject:@(self.maximumBarHeight*pulses[index][point])];
        CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"bounds.size.height"];
        animation.values = heights; animation.keyTimes = times; animation.timingFunctions = curves;
        animation.duration = durations[index];
        animation.repeatCount = 3.402823466e+38F;
        [self.barLayers[index] addAnimation:animation forKey:GMPlaybackPulseKey];
    }
    self.animating = YES;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopMotion];
}
@end
