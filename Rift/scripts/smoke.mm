#import <Foundation/Foundation.h>
#import "RiftEngine.h"
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        if(argc<2) return 2;
        RiftEngine *engine=[RiftEngine new];
        __block NSString *result=@"";
        NSError *error=nil;
        BOOL ok=[engine generateAtPath:[NSString stringWithUTF8String:argv[1]] messages:@[@{@"role":@"user",@"content":@"Reply with one short sentence introducing yourself."}] context:1024 maxTokens:48 temperature:0.5 thinking:NO cpu:YES token:^(NSString *text) { result=text; } status:^(NSString *status) { fprintf(stderr,"%s\n",status.UTF8String); } error:&error];
        NSDictionary *report=@{@"loaded":@(ok),@"output":result,@"error":error.localizedDescription ?: @"",@"backend":@"macOS CPU",@"physical_iPhone_test":@NO};
        NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
        fwrite(data.bytes,1,data.length,stdout); fprintf(stdout,"\n");
        [engine unload];
        return ok && result.length>2 ? 0 : 1;
    }
}
