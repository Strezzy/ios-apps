#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// All inference methods are called on one private serial queue. Cancellation is thread-safe.
@interface RiftEngine : NSObject
- (void)cancel;
@property(nonatomic, readonly) BOOL cancelled;
- (void)resetCancellation;
- (void)unload;
- (BOOL)generateAtPath:(NSString *)path
             messages:(NSArray<NSDictionary<NSString *, NSString *> *> *)messages
              context:(int)context
            maxTokens:(int)maxTokens
          temperature:(float)temperature
             thinking:(BOOL)thinking
                  cpu:(BOOL)cpu
                token:(void (^)(NSString *text))token
               status:(void (^)(NSString *status))status
                error:(NSError * _Nullable * _Nullable)error;
- (BOOL)generateAtPath:(NSString *)path
            projector:(nullable NSString *)projector
             messages:(NSArray<NSDictionary<NSString *, NSString *> *> *)messages
              context:(int)context
            maxTokens:(int)maxTokens
          temperature:(float)temperature
             thinking:(BOOL)thinking
                  cpu:(BOOL)cpu
                token:(void (^)(NSString *text))token
               status:(void (^)(NSString *status))status
                error:(NSError * _Nullable * _Nullable)error;
@end
FOUNDATION_EXPORT uint64_t RiftAvailableMemory(void);
FOUNDATION_EXPORT uint64_t RiftMemoryFootprint(void);
FOUNDATION_EXPORT int RiftBackendInitializationCount(void);
NS_ASSUME_NONNULL_END
