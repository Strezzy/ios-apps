#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "RiftEngine.h"
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 5 || !MTLCreateSystemDefaultDevice()) return 2;
        RiftEngine *engine = [RiftEngine new];
        NSMutableArray *answers = [NSMutableArray new];
        BOOL ok = YES; NSError *error = nil;
        for (int index = 0; index < 3 && ok; ++index) {
            BOOL image = index < 2;
            NSMutableDictionary *message = [@{@"role": @"user", @"content": image ? @"What color and geometric shape are shown? Reply with only the color and shape." : @"Attached file: note.txt\nAccess code: RIFT42.\nWhat is the access code? Reply with only the code."} mutableCopy];
            if (image) message[@"imageFile"] = [NSString stringWithUTF8String:argv[index + 3]];
            __block NSString *answer = @"";
            [engine resetCancellation];
            ok = [engine generateAtPath:[NSString stringWithUTF8String:argv[1]]
                projector:image ? [NSString stringWithUTF8String:argv[2]] : nil
                messages:@[message] context:2048 maxTokens:64 temperature:0.1 thinking:NO cpu:NO
                token:^(NSString *text) { answer = text; }
                status:^(NSString *text) { fprintf(stderr, "%s\n", text.UTF8String); }
                error:&error];
            NSString *lower = answer.lowercaseString;
            BOOL content = index == 0 ? ([lower containsString:@"red"] && [lower containsString:@"circle"]) :
                index == 1 ? ([lower containsString:@"blue"] && [lower containsString:@"square"]) : [lower containsString:@"rift42"];
            ok = ok && content;
            [answers addObject:@{@"input": @(index), @"answer": answer, @"passed": @(content)}];
        }
        [engine unload];
        NSDictionary *report = @{@"passed": @(ok), @"answers": answers, @"error": error.localizedDescription ?: @"", @"backend": @"macOS Metal", @"vision_backend": @"CPU", @"physical_iPhone_test": @NO};
        NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
        fwrite(data.bytes, 1, data.length, stdout);
        return ok ? 0 : 1;
    }
}
