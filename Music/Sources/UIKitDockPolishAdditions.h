// Narrow public UIKit declaration for the persistent dock's selection state.
// Include only in MiniSDK.h; real SDK builds already import UIKit/UIControl.h.
#ifndef MUSIC_UIKIT_DOCK_POLISH_ADDITIONS
#define MUSIC_UIKIT_DOCK_POLISH_ADDITIONS
@interface UIControl (GMDockSelectionState)
@property(nonatomic, getter=isSelected) BOOL selected;
@end
#endif
