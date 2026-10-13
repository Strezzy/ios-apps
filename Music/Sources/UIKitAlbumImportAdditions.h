// Narrow public Foundation/UTType declarations for the Linux arm64 build.
// Apple's SDK supplies these declarations in the Xcode build.
#ifndef MUSIC_UIKIT_ALBUM_IMPORT_ADDITIONS
#define MUSIC_UIKIT_ALBUM_IMPORT_ADDITIONS

extern UTType *const UTTypeFolder;
extern NSString *const NSURLIsDirectoryKey;
extern NSString *const NSURLIsRegularFileKey;
extern NSString *const NSURLIsSymbolicLinkKey;
extern NSString *const NSURLFileSizeKey;

@interface NSURL (GMAlbumImportResources)
- (NSDictionary<NSString *, id> *)resourceValuesForKeys:(NSArray<NSString *> *)keys error:(NSError **)error;
@end
@interface NSString (GMAlbumImportNames)
- (NSInteger)localizedStandardCompare:(NSString *)string;
- (NSArray<NSString *> *)componentsSeparatedByCharactersInSet:(NSCharacterSet *)separator;
@end

@interface NSEnumerator<ObjectType> : NSObject <NSFastEnumeration>
- (ObjectType)nextObject;
@end
@interface NSDirectoryEnumerator<ObjectType> : NSEnumerator<ObjectType>
@property(nonatomic, readonly) NSUInteger level;
- (void)skipDescendants;
@end
@interface NSFileManager (GMAlbumImportFiles)
- (NSDirectoryEnumerator<NSURL *> *)enumeratorAtURL:(NSURL *)url
                       includingPropertiesForKeys:(NSArray<NSString *> *)keys
                                          options:(NSUInteger)options
                                     errorHandler:(BOOL (^)(NSURL *url, NSError *error))handler;
- (BOOL)moveItemAtURL:(NSURL *)source toURL:(NSURL *)destination error:(NSError **)error;
@end

@protocol NSFilePresenter;
@interface NSFileCoordinator : NSObject
- (instancetype)initWithFilePresenter:(id<NSFilePresenter>)filePresenter;
- (void)coordinateReadingItemAtURL:(NSURL *)url options:(NSUInteger)options
                            error:(NSError **)error byAccessor:(void (^)(NSURL *newURL))reader;
@end

#endif
