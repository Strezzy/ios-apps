#ifndef MUSIC_UIKIT_DYNAMIC_ADDITIONS
#define MUSIC_UIKIT_DYNAMIC_ADDITIONS
// Public Foundation notification API, used to share one artwork palette.
@interface NSNotificationCenter (GMDynamicPalette)
- (void)postNotificationName:(NSString *)name object:(id)object userInfo:(NSDictionary *)userInfo;
@end
#endif
