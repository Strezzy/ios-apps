// Public UIKit/QuartzCore declarations for the Linux arm64 build only.
// Real Apple SDK builds use the framework headers included by main.m.
#ifndef GLASS_MUSIC_UIKIT_ROW_POLISH_ADDITIONS
#define GLASS_MUSIC_UIKIT_ROW_POLISH_ADDITIONS

// CACornerMask is NSUInteger (64 bits on arm64). The MaxX corners are the
// physical right edge; MinY and MaxY cover its top and bottom respectively.
typedef NSUInteger CACornerMask;
enum {
    kCALayerMinXMinYCorner = 1UL << 0,
    kCALayerMaxXMinYCorner = 1UL << 1,
    kCALayerMinXMaxYCorner = 1UL << 2,
    kCALayerMaxXMaxYCorner = 1UL << 3
};
@interface CALayer (GMRowPolishCorners)
@property CACornerMask maskedCorners;
@end

@interface UITableViewCell (GMRowPolishSelection)
@property(nonatomic, strong) UIView *selectedBackgroundView;
@end

#endif
