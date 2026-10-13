// Public AVKit/CoreGraphics/QuartzCore APIs used by Music 0.7.
// Included only by the narrow Linux SDK, after the existing declarations.
#ifndef MUSIC_UIKIT_PLAYBACK_ADDITIONS
#define MUSIC_UIKIT_PLAYBACK_ADDITIONS

@interface AVRoutePickerView : UIView
@property(nonatomic, strong) UIColor *activeTintColor;
@property(nonatomic) BOOL prioritizesVideoDevices;
@end
@interface AVAudioPlayer (GMPlaybackLooping)
@property(nonatomic) NSInteger numberOfLoops;
@end
@interface NSMutableArray<ObjectType> (GMPlaybackShuffle)
- (void)exchangeObjectAtIndex:(NSUInteger)first withObjectAtIndex:(NSUInteger)second;
@end
extern unsigned int arc4random_uniform(unsigned int upperBound);
static inline CGAffineTransform CGAffineTransformMakeScale(CGFloat sx, CGFloat sy) {
    return (CGAffineTransform){sx,0,0,sy,0,0};
}

typedef struct CGContext *CGContextRef;
typedef struct CGColorSpace *CGColorSpaceRef;
typedef unsigned int CGBitmapInfo;
enum { kCGImageAlphaPremultipliedLast = 1, kCGBitmapByteOrder32Big = 4 << 12 };
extern CGColorSpaceRef CGColorSpaceCreateDeviceRGB(void);
extern void CGColorSpaceRelease(CGColorSpaceRef space);
extern CGContextRef CGBitmapContextCreate(void *data, size_t width, size_t height,
    size_t bitsPerComponent, size_t bytesPerRow, CGColorSpaceRef space, CGBitmapInfo bitmapInfo);
extern void CGContextDrawImage(CGContextRef context, CGRect rect, CGImageRef image);
extern void CGContextRelease(CGContextRef context);

@interface NSValue : NSObject <NSCopying>
+ (NSValue *)valueWithCGPoint:(CGPoint)point;
@end
@interface CABasicAnimation : CAPropertyAnimation
@property(nonatomic, strong) id fromValue;
@property(nonatomic, strong) id toValue;
@end
#endif
