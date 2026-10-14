#import "RiftEngine.h"
#import <TargetConditionals.h>
#if TARGET_OS_IOS
#import <os/proc.h>
#endif
#include "llama.h"
#include "chat.h"
#include <atomic>
#include <algorithm>
#include <mutex>
#include <string>
#include <vector>
#include <stdexcept>

uint64_t RiftAvailableMemory(void) {
#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR
    return os_proc_available_memory();
#else
    return NSProcessInfo.processInfo.physicalMemory * 3 / 4;
#endif
}
static void quiet_log(enum ggml_log_level, const char *, void *) {}
static NSError *failure(const std::string &s) {
    NSString *text = [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding];
    return [NSError errorWithDomain:@"RiftInference" code:1 userInfo:@{NSLocalizedDescriptionKey:text ?: @"The model could not finish this reply."}];
}
@implementation RiftEngine {
    llama_model *_model;
    llama_context *_context;
    std::string _path;
    int _contextSize;
    std::atomic<bool> _cancelled;
}
- (instancetype)init {
    if ((self = [super init])) {
        _model=nullptr; _context=nullptr; _contextSize=0; _cancelled.store(false);
        static std::once_flag once;
        std::call_once(once, [] { llama_log_set(quiet_log, nullptr); llama_backend_init(); });
    }
    return self;
}
- (void)cancel { _cancelled.store(true); }
- (void)unload {
    if (_context) { llama_free(_context); _context=nullptr; }
    if (_model) { llama_model_free(_model); _model=nullptr; }
    _path.clear(); _contextSize=0;
}
- (void)dealloc { [self unload]; }
- (BOOL)generateAtPath:(NSString *)path messages:(NSArray<NSDictionary<NSString *,NSString *> *> *)messages context:(int)context maxTokens:(int)maxTokens temperature:(float)temperature thinking:(BOOL)thinking cpu:(BOOL)cpu token:(void (^)(NSString *))token status:(void (^)(NSString *))status error:(NSError **)error {
    _cancelled.store(false);
    llama_sampler *sampler=nullptr;
    try {
        if (context < 512 || context > 8192 || maxTokens < 1 || maxTokens > 2048) throw std::runtime_error("Unsupported conversation length.");
        const std::string wanted=path.fileSystemRepresentation;
        if (!_model || _path!=wanted || _contextSize!=context) {
            [self unload]; status(@"Loading model");
            auto mp=llama_model_default_params();
            mp.n_gpu_layers=cpu ? 0 : 99;
            mp.progress_callback=[](float, void *p)->bool { return !static_cast<std::atomic<bool> *>(p)->load(); };
            mp.progress_callback_user_data=&_cancelled;
            _model=llama_model_load_from_file(wanted.c_str(),mp);
            if (!_model) throw std::runtime_error(_cancelled.load() ? "Stopped." : "This model could not load. It may be incompatible, damaged, or too large for the available memory.");
            auto cp=llama_context_default_params();
            cp.n_ctx=(uint32_t)context; cp.n_batch=128; cp.n_ubatch=128; cp.n_seq_max=1;
            cp.n_threads=(int32_t)std::max<NSUInteger>(1,std::min<NSUInteger>(4,NSProcessInfo.processInfo.activeProcessorCount));
            cp.n_threads_batch=cp.n_threads; cp.offload_kqv=!cpu; cp.op_offload=!cpu;
            cp.abort_callback=[](void *p)->bool { return static_cast<std::atomic<bool> *>(p)->load(); };
            cp.abort_callback_data=&_cancelled;
            _context=llama_init_from_model(_model,cp);
            if (!_context) throw std::runtime_error("Not enough working memory for this model and context. Choose a smaller model or shorter context.");
            _path=wanted; _contextSize=context;
        }
        if (_cancelled.load()) throw std::runtime_error("Stopped.");
        llama_memory_clear(llama_get_memory(_context),true);
        auto templates=common_chat_templates_init(_model,"");
        if (!templates) throw std::runtime_error("This model does not contain a supported chat template.");
        common_chat_templates_inputs input;
        input.use_jinja=true; input.enable_thinking=thinking; input.add_generation_prompt=true;
        input.chat_template_kwargs["enable_thinking"]=thinking ? "true" : "false";
        for (NSDictionary *item in messages) {
            NSString *role=item[@"role"], *text=item[@"content"];
            if (!role || !text) continue;
            common_chat_msg message; message.role=role.UTF8String; message.content=text.UTF8String;
            input.messages.push_back(std::move(message));
        }
        if (input.messages.empty()) throw std::runtime_error("Write a message first.");
        const llama_vocab *vocab=llama_model_get_vocab(_model);
        std::vector<llama_token> prompt;
        common_chat_params formatted;
        bool trimmed=false;
        const int reserve=std::min(maxTokens,context/2);
        while (true) {
            formatted=common_chat_templates_apply(templates.get(),input);
            if (formatted.prompt.size()>1024*1024) throw std::runtime_error("This conversation is too large. Start a new chat or shorten the message.");
            int n=llama_tokenize(vocab,formatted.prompt.c_str(),(int)formatted.prompt.size(),nullptr,0,true,true);
            if (n==0 || n==INT32_MIN) throw std::runtime_error("The model could not tokenize this message.");
            n=std::abs(n); prompt.resize(n);
            n=llama_tokenize(vocab,formatted.prompt.c_str(),(int)formatted.prompt.size(),prompt.data(),n,true,true);
            if(n<0) throw std::runtime_error("Tokenizer size changed unexpectedly.");
            prompt.resize(n);
            if(n+reserve<context) break;
            const size_t start=input.messages.front().role=="system" ? 1 : 0;
            if (input.messages.size()<=start+1) throw std::runtime_error("Your latest message is longer than this model's conversation window. Shorten it or increase context in Settings.");
            input.messages.erase(input.messages.begin()+start);
            while (input.messages.size()>start+1 && input.messages[start].role!="user") input.messages.erase(input.messages.begin()+start);
            trimmed=true;
        }
        status(trimmed ? @"Reading recent messages · earlier turns outside context" : @"Reading conversation");
        for (size_t offset=0; offset<prompt.size(); offset+=128) {
            if(_cancelled.load()) throw std::runtime_error("Stopped.");
            const int count=(int)std::min<size_t>(128,prompt.size()-offset);
            auto batch=llama_batch_get_one(prompt.data()+offset,count);
            if(llama_decode(_context,batch)!=0) throw std::runtime_error(_cancelled.load() ? "Stopped." : "The model could not process this conversation. Try a shorter context.");
        }
        sampler=llama_sampler_chain_init(llama_sampler_chain_default_params());
        llama_sampler_chain_add(sampler,llama_sampler_init_top_k(40));
        llama_sampler_chain_add(sampler,llama_sampler_init_top_p(0.95f,1));
        llama_sampler_chain_add(sampler,llama_sampler_init_min_p(0.05f,1));
        llama_sampler_chain_add(sampler,llama_sampler_init_temp(temperature));
        llama_sampler_chain_add(sampler,llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
        status(@"Writing reply");
        std::string output;
        if (thinking && !formatted.thinking_start_tag.empty() && formatted.generation_prompt.find(formatted.thinking_start_tag)!=std::string::npos) output=formatted.thinking_start_tag;
        CFAbsoluteTime lastUpdate=0;
        for(int i=0; i<maxTokens && (int)prompt.size()+i<context-1; ++i) {
            if(_cancelled.load()) break;
            llama_token next=llama_sampler_sample(sampler,_context,-1);
            if(llama_vocab_is_eog(vocab,next)) break;
            std::vector<char> piece(256);
            int count=llama_token_to_piece(vocab,next,piece.data(),(int)piece.size(),0,true);
            if(count<0) { piece.resize((size_t)-count); count=llama_token_to_piece(vocab,next,piece.data(),(int)piece.size(),0,true); }
            if(count<0 || count>1024*1024) throw std::runtime_error("Invalid tokenizer output.");
            output.append(piece.data(),(size_t)count);
            bool stop=false;
            for(const auto &s:formatted.additional_stops) {
                if(!s.empty() && output.size()>=s.size() && output.compare(output.size()-s.size(),s.size(),s)==0) { output.resize(output.size()-s.size()); stop=true; break; }
            }
            CFAbsoluteTime now=CFAbsoluteTimeGetCurrent();
            if(now-lastUpdate>0.06 || stop) {
                NSString *text=[[NSString alloc] initWithBytes:output.data() length:output.size() encoding:NSUTF8StringEncoding];
                if(text) { token(text); lastUpdate=now; }
            }
            if(stop) break;
            auto batch=llama_batch_get_one(&next,1);
            if(llama_decode(_context,batch)!=0) throw std::runtime_error(_cancelled.load() ? "Stopped." : "Generation stopped because the model could not allocate working memory.");
        }
        NSString *finalText=[[NSString alloc] initWithBytes:output.data() length:output.size() encoding:NSUTF8StringEncoding];
        if(finalText) token(finalText);
        llama_sampler_free(sampler); sampler=nullptr;
        status(_cancelled.load() ? @"Stopped" : (trimmed ? @"Earlier turns outside context" : @"On device"));
        return YES;
    } catch(const std::exception &e) {
        if(sampler) llama_sampler_free(sampler);
        if(error) *error=failure(e.what());
        [self unload]; return NO;
    } catch(...) {
        if(sampler) llama_sampler_free(sampler);
        if(error) *error=failure("The model encountered an unsupported operation.");
        [self unload]; return NO;
    }
}
@end
