// Public trait observation used by the native UITabAccessory content view.
// Linux declarations only; the Xcode build uses UIKit's real SDK headers.
// Available since iOS 17. Resolve UITraitTabAccessoryEnvironment dynamically
// because that particular trait class is new in iOS 26.
#ifndef MUSIC_UIKIT_NATIVE_DOCK_ADDITIONS
#define MUSIC_UIKIT_NATIVE_DOCK_ADDITIONS

@protocol UITraitDefinition;
@protocol UITraitChangeRegistration <NSObject, NSCopying>
@end

@interface UIView (GMNativeDockTraitObservation)
// The action may take zero, one, or two parameters. UIKit manages registration
// lifetime; the opaque return value can be ignored for a permanent observation.
- (id<UITraitChangeRegistration>)registerForTraitChanges:(NSArray<Class<UITraitDefinition>> *)traits
                                            withTarget:(id)target
                                                action:(SEL)action;
@end

#endif
