// Public UIKit context-menu declarations for the narrow Linux arm64 build.
// UIControl hooks are iOS 14+; native shared bar backgrounds are iOS 26+.
#ifndef MUSIC_UIKIT_IMPORT_MENU_ADDITIONS
#define MUSIC_UIKIT_IMPORT_MENU_ADDITIONS

@class UIContextMenuInteraction, UIContextMenuConfiguration;
@protocol UIContextMenuInteractionAnimating <NSObject>
- (void)addCompletion:(void (^)(void))completion;
@end
@interface UIControl (GMImportMenuLifecycle)
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                          configurationForMenuAtLocation:(CGPoint)location;
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction
 willDisplayMenuForConfiguration:(UIContextMenuConfiguration *)configuration
                     animator:(id<UIContextMenuInteractionAnimating>)animator __attribute__((objc_requires_super));
- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction
      willEndForConfiguration:(UIContextMenuConfiguration *)configuration
                     animator:(id<UIContextMenuInteractionAnimating>)animator __attribute__((objc_requires_super));
@end
@interface UIBarButtonItem (GMImportMenuBackground)
@property(nonatomic) BOOL hidesSharedBackground;
@end

#endif
