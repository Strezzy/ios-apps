#import "MusicArtworkBackdrop.h"
#import "ArtworkPalette.h"

static NSArray<UIColor *> *GMColorsForArtwork(UIImage *artwork) {
    CGImageRef image = artwork.CGImage;
    if (!image) return nil;
    unsigned char pixels[40*40*4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    if (!space) return nil;
    CGContextRef context = CGBitmapContextCreate(pixels,40,40,8,40*4,space,
        kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return nil;
    CGContextDrawImage(context,CGRectMake(0,0,40,40),image);
    CGContextRelease(context);
    double palette[3][3];
    if (!GMExtractArtworkPalette(pixels,40*40,palette)) return nil;
    return @[GMColor(palette[0][0],palette[0][1],palette[0][2],1),
             GMColor(palette[1][0],palette[1][1],palette[1][2],1),
             GMColor(palette[2][0],palette[2][1],palette[2][2],1)];
}
// Now Playing and every Dynamic page share one bounded analysis per cover.
// A late result from an earlier song can never replace the current palette.
static NSString *const GMArtworkPaletteDidChange = @"GMArtworkPaletteDidChange";
@interface GMArtworkPaletteState : NSObject
@property(strong) UIImage *artwork;
@property(copy) NSArray<UIColor *> *palette;
@property NSUInteger generation;
@property BOOL initialized;
- (void)useArtwork:(UIImage *)artwork animated:(BOOL)animated;
@end
@implementation GMArtworkPaletteState
- (void)publishPalette:(NSArray<UIColor *> *)palette animated:(BOOL)animated {
    self.palette = palette;
    [[NSNotificationCenter defaultCenter] postNotificationName:GMArtworkPaletteDidChange
        object:self userInfo:@{@"animated":@(animated)}];
}
- (void)useArtwork:(UIImage *)artwork animated:(BOOL)animated {
    if (self.initialized && self.artwork == artwork) return;
    self.initialized = YES; self.artwork = artwork;
    NSUInteger generation = ++self.generation;
    if (!artwork.CGImage) { [self publishPalette:nil animated:animated]; return; }
    dispatch_async(dispatch_get_global_queue(0,0),^{
        @autoreleasepool {
            NSArray *palette = GMColorsForArtwork(artwork);
            dispatch_async(dispatch_get_main_queue(),^{
                if (generation != self.generation) return;
                [self publishPalette:palette animated:animated];
            });
        }
    });
}
@end
static GMArtworkPaletteState *GMSharedArtworkPalette(void) {
    // All entry points are UIKit presentation/update calls on the main queue.
    static GMArtworkPaletteState *state;
    if (!state) state = [GMArtworkPaletteState new];
    return state;
}
static UIColor *GMBackdropTone(UIColor *color, BOOL dark, UITraitCollection *traits) {
    // Covers can be almost white or black. Keep their hue while moving the
    // backdrop's tones away from the system foreground, including where
    // multiple radial fields overlap behind an ungrouped song row.
    CGFloat r=0,g=0,b=0; GMReadRGB(color,traits,&r,&g,&b);
    if (dark) {
        CGFloat peak = GMMax(r,GMMax(g,b));
        CGFloat scale = peak > .52 ? .52/peak : 1;
        r *= scale; g *= scale; b *= scale;
    } else {
        CGFloat low = r < g ? r : g; low = low < b ? low : b;
        CGFloat amount = low < .55 ? (.55-low)/(1-low) : 0;
        r += (1-r)*amount; g += (1-g)*amount; b += (1-b)*amount;
    }
    return GMColor(r,g,b,1);
}
static void GMAnimateBackdropColors(CAGradientLayer *layer, NSArray *colors, NSTimeInterval duration) {
    CAGradientLayer *presentation = layer.presentationLayer;
    NSArray *previous = presentation.colors ?: layer.colors;
    [CATransaction begin]; [CATransaction setDisableActions:YES]; layer.colors = colors; [CATransaction commit];
    if (duration <= 0 || !previous || previous.count != colors.count) { [layer removeAnimationForKey:@"MusicPalette"]; return; }
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"colors"];
    animation.fromValue = previous; animation.toValue = colors;
    animation.duration = duration;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:@"easeInEaseOut"];
    [layer addAnimation:animation forKey:@"MusicPalette"];
}
static void GMAnimateBackdropPoint(CAGradientLayer *layer, CGPoint point, BOOL start, NSTimeInterval duration) {
    CAGradientLayer *presentation = layer.presentationLayer ?: layer;
    CGPoint previous = start ? presentation.startPoint : presentation.endPoint;
    NSString *path = start ? @"startPoint" : @"endPoint";
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    if (start) layer.startPoint = point; else layer.endPoint = point;
    [CATransaction commit];
    if (duration <= 0) { [layer removeAnimationForKey:path]; return; }
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:path];
    animation.fromValue = [NSValue valueWithCGPoint:previous]; animation.toValue = [NSValue valueWithCGPoint:point];
    animation.duration = duration;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:@"easeInEaseOut"];
    [layer addAnimation:animation forKey:path];
}

@interface GMArtworkBackdrop ()
@property(nonatomic, strong) CAGradientLayer *baseLayer;
@property(nonatomic, copy) NSArray<CAGradientLayer *> *washes;
@property(nonatomic) NSUInteger phase;
- (void)renderPaletteAnimated:(BOOL)animated;
@end

@implementation GMArtworkBackdrop
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.userInteractionEnabled = NO; self.accessibilityElementsHidden = YES;
    self.baseLayer = [CAGradientLayer layer];
    self.baseLayer.startPoint = CGPointMake(.12,0); self.baseLayer.endPoint = CGPointMake(.86,1);
    self.baseLayer.locations = @[@0,@.5,@1];
    [self.layer addSublayer:self.baseLayer];
    NSMutableArray *washes = [NSMutableArray array];
    for (NSUInteger i=0;i<3;i++) {
        CAGradientLayer *wash = [CAGradientLayer layer]; wash.type = @"radial";
        wash.locations = @[@0,@.45,@1];
        [washes addObject:wash]; [self.layer addSublayer:wash];
    }
    self.washes = washes;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(artworkPaletteChanged:)
        name:GMArtworkPaletteDidChange object:nil];
    [self renderPaletteAnimated:NO];
    return self;
}
- (void)setArtwork:(UIImage *)artwork animated:(BOOL)animated {
    [GMSharedArtworkPalette() useArtwork:artwork animated:animated];
}
- (void)artworkPaletteChanged:(NSNotification *)notification {
    [self renderPaletteAnimated:[notification.userInfo[@"animated"] boolValue]];
}
- (void)applyTheme { [self renderPaletteAnimated:self.window != nil]; }
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection]; [self applyTheme];
}
- (void)renderPaletteAnimated:(BOOL)animated {
    UIColor *base = [(self.groupedBackground ? GMGroupedColor() : GMPageColor()) resolvedColorWithTraitCollection:self.traitCollection];
    NSArray<UIColor *> *palette = GMSharedArtworkPalette().palette;
    NSArray<UIColor *> *colors = palette.count == 3 ? palette : @[GMCurrentAccent(),GMCurrentAccent(),GMCurrentAccent()];
    BOOL dark = self.traitCollection.userInterfaceStyle == 2;
    colors = @[GMBackdropTone(colors[0],dark,self.traitCollection),
               GMBackdropTone(colors[1],dark,self.traitCollection),
               GMBackdropTone(colors[2],dark,self.traitCollection)];
    BOOL reduced = UIAccessibilityIsReduceMotionEnabled() || UIAccessibilityPrefersCrossFadeTransitions();
    NSTimeInterval duration = animated && self.window ? (reduced ? .2 : 1.15) : 0;
    CGFloat strength = dark ? .40 : .22;
    self.backgroundColor = base;
    NSArray *foundation = @[(__bridge id)GMBlend(base,colors[0],strength,self.traitCollection).CGColor,
                            (__bridge id)GMBlend(base,colors[1],strength*.78,self.traitCollection).CGColor,
                            (__bridge id)GMBlend(base,colors[2],strength*.46,self.traitCollection).CGColor];
    GMAnimateBackdropColors(self.baseLayer,foundation,duration);
    self.phase++;
    const CGPoint first[3]={{.18,.20},{.86,.45},{.30,.90}};
    const CGPoint second[3]={{.34,.27},{.73,.60},{.62,.81}};
    for (NSUInteger i=0;i<3;i++) {
        UIColor *color = colors[i];
        CGFloat opacity = dark ? .29 : .24;
        NSArray *wash = @[(__bridge id)[color colorWithAlphaComponent:opacity].CGColor,
                          (__bridge id)[color colorWithAlphaComponent:opacity*.55].CGColor,
                          (__bridge id)[color colorWithAlphaComponent:0].CGColor];
        CAGradientLayer *layer = self.washes[i];
        GMAnimateBackdropColors(layer,wash,duration);
        CGPoint start = (self.phase%2) ? first[i] : second[i];
        CGPoint end = CGPointMake(start.x+.78,start.y+.68);
        // Broad radial fields flow to new positions while the colors blend.
        // No continuous timer or image processing runs during playback.
        GMAnimateBackdropPoint(layer,start,YES,reduced ? 0 : duration*1.12);
        GMAnimateBackdropPoint(layer,end,NO,reduced ? 0 : duration*1.12);
    }
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    self.baseLayer.frame = self.bounds;
    for (CAGradientLayer *wash in self.washes) wash.frame = self.bounds;
    [CATransaction commit];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end
