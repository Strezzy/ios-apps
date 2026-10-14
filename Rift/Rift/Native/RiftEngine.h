#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// All inference methods are called on one private serial queue. Cancellation is thread-safe.
@interface RiftEngine : NSObject
- (void)cancel;
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
@end
FOUNDATION_EXPORT uint64_t RiftAvailableMemory(void);
NS_ASSUME_NONNULL_END
