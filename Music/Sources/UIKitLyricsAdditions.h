// Public declarations needed only by the narrow Linux arm64 build.
// A real Apple SDK build gets these declarations from UIKit/Foundation.
#ifndef MUSIC_UIKIT_LYRICS_ADDITIONS
#define MUSIC_UIKIT_LYRICS_ADDITIONS

typedef NSUInteger NSStringEncoding;
enum {
    NSUTF8StringEncoding = 4,
    NSUTF16StringEncoding = 10,
    NSUTF16BigEndianStringEncoding = 0x90000100,
    NSUTF16LittleEndianStringEncoding = 0x94000100
};
typedef unsigned short unichar;
@interface NSString (GMLyricsText)
- (NSArray<NSString *> *)componentsSeparatedByString:(NSString *)separator;
- (NSString *)substringWithRange:(NSRange)range;
- (unichar)characterAtIndex:(NSUInteger)index;
@property(nonatomic, readonly) const char *UTF8String __attribute__((objc_returns_inner_pointer));
@end
@interface NSArray<ObjectType> (GMLyricsJoining)
- (NSString *)componentsJoinedByString:(NSString *)separator;
@end
@interface NSData (GMLyricsBytes)
@property(nonatomic, readonly) NSUInteger length;
@property(nonatomic, readonly) const void *bytes __attribute__((objc_returns_inner_pointer));
@end
@interface NSMutableData : NSData
- (void)appendData:(NSData *)other;
@end
@interface NSFileHandle : NSObject
+ (instancetype)fileHandleForReadingFromURL:(NSURL *)url error:(NSError **)error;
- (NSData *)readDataUpToLength:(NSUInteger)length error:(NSError **)error;
- (BOOL)closeAndReturnError:(NSError **)error;
@end

@protocol UITextViewDelegate <NSObject> @end
@interface UITextView : UIScrollView
@property(nonatomic, weak) id<UITextViewDelegate> delegate;
@property(nonatomic, copy) NSString *text;
@property(nonatomic, strong) UIFont *font;
@property(nonatomic, strong) UIColor *textColor;
@property(nonatomic, getter=isEditable) BOOL editable;
@property(nonatomic, getter=isSelectable) BOOL selectable;
@property(nonatomic) UIEdgeInsets textContainerInset;
@end

@class UITrackingLayoutGuide, UIKeyboardLayoutGuide;
@interface UILayoutGuide : NSObject
@property(nonatomic, readonly) CGRect layoutFrame;
@end
@interface UITrackingLayoutGuide : UILayoutGuide @end
@interface UIKeyboardLayoutGuide : UITrackingLayoutGuide @end
@interface UIView (GMLyricsKeyboard)
@property(nonatomic, readonly, strong) UIKeyboardLayoutGuide *keyboardLayoutGuide;
@end

@interface UTType (GMLyricsTypes)
+ (instancetype)typeWithFilenameExtension:(NSString *)filenameExtension;
@end
extern UTType *const UTTypePlainText;

#endif
