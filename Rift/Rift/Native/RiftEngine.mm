#import "RiftEngine.h"
#import <TargetConditionals.h>
#if TARGET_OS_IOS
#import <os/proc.h>
#endif
#include "llama.h"
#include "chat.h"
#include "mtmd.h"
#include "mtmd-helper.h"
#include <atomic>
#include <algorithm>
#include <mutex>
#include <string>
#include <vector>
#include <stdexcept>
#import <mach/mach.h>
static std::atomic<int> backendStarts{0};
int RiftBackendInitializationCount(void) { return backendStarts.load(); }
uint64_t RiftMemoryFootprint(void) {
    task_vm_info_data_t info{}; mach_msg_type_number_t count=TASK_VM_INFO_COUNT;
    return task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&info,&count)==KERN_SUCCESS ? info.phys_footprint : 0;
}

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
        // Runtime initialization is deliberately deferred to generateAtPath,
        // which is called only by the inference queue, never app launch.
    }
    return self;
}
- (void)resetCancellation { _cancelled.store(false); }
- (BOOL)cancelled { return _cancelled.load(); }
- (void)cancel { _cancelled.store(true); }
- (void)unload {
    if (_context) { llama_free(_context); _context=nullptr; }
    if (_model) { llama_model_free(_model); _model=nullptr; }
    _path.clear(); _contextSize=0;
}
- (void)dealloc { [self unload]; }
- (BOOL)generateAtPath:(NSString *)path messages:(NSArray<NSDictionary<NSString *,NSString *> *> *)messages context:(int)context maxTokens:(int)maxTokens temperature:(float)temperature thinking:(BOOL)thinking cpu:(BOOL)cpu token:(void (^)(NSString *))token status:(void (^)(NSString *))status error:(NSError **)error {
    return [self generateAtPath:path projector:nil messages:messages context:context maxTokens:maxTokens temperature:temperature thinking:thinking cpu:cpu token:token status:status error:error];
}
- (BOOL)generateAtPath:(NSString *)path projector:(NSString *)projector messages:(NSArray<NSDictionary<NSString *,NSString *> *> *)messages context:(int)context maxTokens:(int)maxTokens temperature:(float)temperature thinking:(BOOL)thinking cpu:(BOOL)cpu token:(void (^)(NSString *))token status:(void (^)(NSString *))status error:(NSError **)error {
    llama_sampler *sampler=nullptr;
    try {
        if (_cancelled.load()) throw std::runtime_error("Stopped.");
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) throw std::runtime_error("This model could not load because its file is missing. Download or import it again.");
        status(@"Preparing on-device runtime");
        static std::once_flag once;
        std::call_once(once, [] { llama_log_set(quiet_log, nullptr); mtmd_helper_log_set(quiet_log, nullptr); llama_backend_init(); backendStarts.fetch_add(1); });
        if (_cancelled.load()) throw std::runtime_error("Stopped.");
        if (context < 512 || context > 8192 || maxTokens < 1 || maxTokens > 2048) throw std::runtime_error("Unsupported conversation length.");
        const std::string wanted=path.fileSystemRepresentation;
        if (!_model || _path!=wanted || _contextSize!=context) {
            [self unload]; status(@"Loading model");
            auto mp=llama_model_default_params();
            mp.n_gpu_layers=cpu ? 0 : -1;
            mp.load_mode=LLAMA_LOAD_MODE_MMAP;
            mp.use_extra_bufts=false; // Avoid a second repacked copy of weights.
            mp.load_mtp=false; // Text chat does not load speculative draft tensors.
            mp.lazy_mode=LLAMA_LAZY_MODE_AUTO;
            mp.progress_callback=[](float, void *p)->bool { return !static_cast<std::atomic<bool> *>(p)->load(); };
            mp.progress_callback_user_data=&_cancelled;
            _model=llama_model_load_from_file(wanted.c_str(),mp);
            if (!_model) throw std::runtime_error(_cancelled.load() ? "Stopped." : "This model could not load. It may be incompatible, damaged, or too large for the available memory.");
            auto cp=llama_context_default_params();
            cp.n_ctx=(uint32_t)context; cp.n_batch=64; cp.n_ubatch=32; cp.n_seq_max=1;
            cp.flash_attn_type=LLAMA_FLASH_ATTN_TYPE_AUTO;
            cp.no_perf=true;
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
        mtmd::context_ptr vision;
        if (projector) {
            if (![[NSFileManager defaultManager] fileExistsAtPath:projector]) throw std::runtime_error("Download Qwen3.5 4B image support first.");
            if (RiftAvailableMemory() < 1100ULL * 1048576ULL) throw std::runtime_error("Not enough remaining app memory for image understanding. Free memory or use text only.");
            auto vp=mtmd_context_params_default();
            // The publisher encoder uses BF16 tensors, unsupported by some Apple Metal devices.
            // Encode images on CPU; the language model keeps its existing Metal path.
            vp.use_gpu=false; vp.n_threads=4; vp.warmup=false;
            vp.image_min_tokens=64; vp.image_max_tokens=256;
            vp.progress_callback=[](float, void *p)->bool { return !static_cast<std::atomic<bool> *>(p)->load(); };
            vp.progress_callback_user_data=&_cancelled;
            status(@"Reading image");
            vision.reset(mtmd_init_from_file(projector.fileSystemRepresentation,_model,vp));
            if (!vision || !mtmd_support_vision(vision.get())) throw std::runtime_error("The matching image encoder could not load. Try freeing memory or downloading image support again.");
        }
        std::vector<std::string> imagePaths;
        for (NSDictionary *item in messages) {
            NSString *role=item[@"role"], *text=item[@"content"], *image=item[@"imageFile"];
            if (!role || !text) continue;
            common_chat_msg message; message.role=role.UTF8String;
            // Literal media-marker text must not be mistaken for an attachment.
            if (vision) text=[text stringByReplacingOccurrencesOfString:@"<__media__>" withString:@"<media>"];
            message.content=text.UTF8String;
            if (image.length) {
                if (!vision) throw std::runtime_error("Select Qwen3.5 4B with image support to read this image.");
                message.content=std::string(mtmd_default_marker())+"\n"+message.content;
            }
            imagePaths.push_back(image.length ? image.fileSystemRepresentation : "");
            input.messages.push_back(std::move(message));
        }
        if (input.messages.empty()) throw std::runtime_error("Write a message first.");
        const llama_vocab *vocab=llama_model_get_vocab(_model);
        std::vector<llama_token> prompt;
        common_chat_params formatted;
        bool trimmed=false;
        mtmd::input_chunks_ptr imageChunks;
        int promptTokenCount=0;
        llama_pos nextPosition=0;
        auto trimOldest = [&]() {
            const size_t start=input.messages.front().role=="system" ? 1 : 0;
            if (input.messages.size()<=start+1) throw std::runtime_error("Your latest message and attachment exceed this model's conversation window. Use a shorter excerpt or increase context in Settings.");
            input.messages.erase(input.messages.begin()+start); imagePaths.erase(imagePaths.begin()+start);
            while (input.messages.size()>start+1 && input.messages[start].role!="user") {
                input.messages.erase(input.messages.begin()+start); imagePaths.erase(imagePaths.begin()+start);
            }
            trimmed=true;
        };
        const int reserve=std::min(maxTokens,context/2);
        while (true) {
            formatted=common_chat_templates_apply(templates.get(),input);
            if (formatted.prompt.size()>1024*1024) throw std::runtime_error("This conversation is too large. Start a new chat or shorten the message.");
            if (vision) {
                // Bound retained image memory before decoding; older turns use
                // the same context-trimming rule as ordinary text conversations.
                if (std::count_if(imagePaths.begin(),imagePaths.end(),[](const auto &p){return !p.empty();})>4) { trimOldest(); continue; }
                std::vector<mtmd::bitmap_ptr> owned;
                std::vector<const mtmd_bitmap *> images;
                for (const auto &path : imagePaths) {
                    if (path.empty()) continue;
                    if (_cancelled.load()) throw std::runtime_error("Stopped.");
                    auto bitmap=mtmd_helper_bitmap_init_from_file(vision.get(),path.c_str(),false,mtmd_helper_init_opt_default());
                    if (!bitmap.bitmap) throw std::runtime_error("A saved image could not be read. Attach it again.");
                    owned.emplace_back(bitmap.bitmap); images.push_back(bitmap.bitmap);
                }
                imageChunks.reset(mtmd_input_chunks_init());
                mtmd_input_text text{formatted.prompt.data(),formatted.prompt.size(),true,true};
                if (mtmd_tokenize(vision.get(),imageChunks.get(),&text,images.data(),images.size())!=0) throw std::runtime_error("The model could not prepare this image.");
                promptTokenCount=(int)mtmd_helper_get_n_tokens(imageChunks.get());
            } else {
                int n=llama_tokenize(vocab,formatted.prompt.c_str(),(int)formatted.prompt.size(),nullptr,0,true,true);
                if (n==0 || n==INT32_MIN) throw std::runtime_error("The model could not tokenize this message.");
                n=std::abs(n); prompt.resize(n);
                n=llama_tokenize(vocab,formatted.prompt.c_str(),(int)formatted.prompt.size(),prompt.data(),n,true,true);
                if(n<0) throw std::runtime_error("Tokenizer size changed unexpectedly.");
                prompt.resize(n); promptTokenCount=n;
            }
            if(promptTokenCount+reserve<context) break;
            trimOldest();
        }
        status(trimmed ? @"Reading recent messages · earlier turns outside context" : @"Reading conversation");
        if (vision) {
            for (size_t index=0; index<mtmd_input_chunks_size(imageChunks.get()); ++index) {
                if (_cancelled.load()) throw std::runtime_error("Stopped.");
                auto chunk=mtmd_input_chunks_get(imageChunks.get(),index);
                if (mtmd_helper_eval_chunk_single(vision.get(),_context,chunk,nextPosition,0,64,index+1==mtmd_input_chunks_size(imageChunks.get()),&nextPosition)!=0)
                    throw std::runtime_error(_cancelled.load() ? "Stopped." : "Image understanding could not finish. Try a smaller image or free more memory.");
            }
            // Release encoder weights/workspace before streaming the reply.
            imageChunks.reset(); vision.reset();
        } else {
            for (size_t offset=0; offset<prompt.size(); offset+=64) {
                if(_cancelled.load()) throw std::runtime_error("Stopped.");
                const int count=(int)std::min<size_t>(64,prompt.size()-offset);
                auto batch=llama_batch_get_one(prompt.data()+offset,count);
                if(llama_decode(_context,batch)!=0) throw std::runtime_error(_cancelled.load() ? "Stopped." : "The model could not process this conversation. Try a shorter context.");
            }
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
        for(int i=0; i<maxTokens && promptTokenCount+i<context-1; ++i) {
            if(_cancelled.load()) break;
            llama_token next=llama_sampler_sample(sampler,_context,-1);
            if(llama_vocab_is_eog(vocab,next)) break;
            std::vector<char> piece(256);
            int count=llama_token_to_piece(vocab,next,piece.data(),(int)piece.size(),0,true);
            if(count < -1048576) throw std::runtime_error("Invalid tokenizer piece length.");
            if(count<0) { piece.resize((size_t)-count); count=llama_token_to_piece(vocab,next,piece.data(),(int)piece.size(),0,true); }
            if(count<0 || count>1024*1024) throw std::runtime_error("Invalid tokenizer output.");
            output.append(piece.data(),(size_t)count);
            bool stop=false;
            for(const auto &s:formatted.additional_stops) {
                if(!s.empty() && output.size()>=s.size() && output.compare(output.size()-s.size(),s.size(),s)==0) { output.resize(output.size()-s.size()); stop=true; break; }
            }
            CFAbsoluteTime now=CFAbsoluteTimeGetCurrent();
            if(now-lastUpdate>0.06 || stop) {
                @autoreleasepool {
                    NSString *text=[[NSString alloc] initWithBytes:output.data() length:output.size() encoding:NSUTF8StringEncoding];
                    if(text) { token(text); lastUpdate=now; }
                }
            }
            if(stop) break;
            auto batch=llama_batch_get_one(&next,1);
            llama_pos position=nextPosition++;
            if (projector) batch.pos=&position;
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
