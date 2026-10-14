#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "RiftEngine.h"
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        if(argc<2) return 2;
        const BOOL gpu=argc>2 && strcmp(argv[2],"metal")==0;
        if(gpu && !MTLCreateSystemDefaultDevice()) return 3;
        RiftEngine *engine=[RiftEngine new];
        NSMutableArray *messages=[@[@{@"role":@"system",@"content":@"You are Rift, a helpful local assistant. Answer clearly."},@{@"role":@"user",@"content":@"Say hello in one short sentence."}] mutableCopy];
        NSMutableArray *answers=[NSMutableArray new];
        NSError *error=nil;
        BOOL ok=YES;
        for(int turn=0;turn<2 && ok;++turn) {
            __block NSString *result=@"";
            [engine resetCancellation];
            ok=[engine generateAtPath:[NSString stringWithUTF8String:argv[1]] messages:messages context:1024 maxTokens:64 temperature:0.5 thinking:NO cpu:!gpu token:^(NSString *text) { result=text; } status:^(NSString *status) { fprintf(stderr,"%s\n",status.UTF8String); } error:&error];
            ok=ok && result.length>1;
            [answers addObject:result];
            [messages addObject:@{@"role":@"assistant",@"content":result}];
            [messages addObject:@{@"role":@"user",@"content":@"Now tell me one fact about the ocean, in one short sentence."}];
        }
        NSDictionary *report=@{@"loaded":@(ok),@"answers":answers,@"error":error.localizedDescription ?: @"",@"backend":gpu ? @"macOS Metal" : @"macOS CPU",@"physical_iPhone_test":@NO,@"peak_last_footprint":@(RiftMemoryFootprint())};
        NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
        fwrite(data.bytes,1,data.length,stdout); fprintf(stdout,"\n");
        [engine unload]; return ok ? 0 : 1;
    }
}
