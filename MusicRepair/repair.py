#!/usr/bin/env python3
"""One-time, checked migration from the checksum-pinned Music 0.11 source.

The resulting Music directory is the complete, readable project. The original
CD geometry and optical shaders are retained, not replaced with a flat effect.
"""
from pathlib import Path
import plistlib
import sys

root = Path(sys.argv[1])

def replace(path, old, new):
    p = root / path
    source = p.read_text()
    if old not in source:
        raise RuntimeError(f'Migration anchor missing: {path}: {old[:70]}')
    p.write_text(source.replace(old, new))

p = 'Sources/MusicCDCase.m'
replace(p, '@(active && spin && !reduced)', '[NSNumber numberWithBool:(active && spin && !reduced)]')
replace(p, '@(animated && !GMCDReducedMotion())', '[NSNumber numberWithBool:(animated && !GMCDReducedMotion())]')
replace(p, 'if (grids >= 4) break;', 'if (grids >= 6) break;')
replace(p, 'self.bounds.size.height)*.88;', 'self.bounds.size.height)*.97;')
replace(p, '@property(nonatomic) BOOL bridgeReady;', '''@property(nonatomic) BOOL bridgeReady;
@property(nonatomic, strong) UILabel *rendererStatusLabel;
@property(nonatomic, copy) NSString *rendererFailureReason;
@property(nonatomic) NSUInteger automaticRetries;
- (void)showRendererStatus:(NSString *)message;
- (void)retryRenderer;
- (void)recordRendererFailure:(NSString *)reason;
- (void)checkBridgeAfterNavigation;''')
replace(p, '    [self addSubview:self.fallback];\n    [GMCDSharedHub().views addObject:self];', '''    [self addSubview:self.fallback];
    self.rendererStatusLabel = GMLabel(@"",11,.4,GMSecondaryTextColor());
    self.rendererStatusLabel.textAlignment = 1; self.rendererStatusLabel.numberOfLines = 2;
    self.rendererStatusLabel.userInteractionEnabled = NO; self.rendererStatusLabel.hidden = YES;
    [self addSubview:self.rendererStatusLabel];
    [GMCDSharedHub().views addObject:self];''')
replace(p, '- (void)setCaseOpen:(BOOL)open animated:(BOOL)animated {\n    if (self.caseOpen == open) return;', '''- (void)setCaseOpen:(BOOL)open animated:(BOOL)animated {
    if (self.failedThisActivation && animated) [self retryRenderer];
    if (self.caseOpen == open && self.rendered) return;''')
replace(p, '    self.webView.frame = self.bounds; self.fallback.frame = self.bounds; self.stillView.frame = self.bounds;', '''    self.webView.frame = self.bounds; self.fallback.frame = self.bounds; self.stillView.frame = self.bounds;
    self.rendererStatusLabel.frame = CGRectMake(4,GMMax(0,self.bounds.size.height-28),GMMax(0,self.bounds.size.width-8),28);''')
replace(p, '    self.failedThisActivation = NO;\n    [self.stillView removeFromSuperview]; self.stillView = nil;\n    [self.fallback setArtwork:nil];', '''    self.failedThisActivation = NO; self.automaticRetries = 0; self.rendererFailureReason = nil;
    [self showRendererStatus:nil];
    [self.stillView removeFromSuperview]; self.stillView = nil;
    [self.fallback setArtwork:nil];''')
source = (root / p).read_text()
start = source.index('- (void)startRenderer {')
end = source.index('- (void)stopRendererKeepingStill:', start)
bootstrap = r'''- (void)startRenderer {
    if (self.webView || ![self eligibleForRenderer]) return;
    // The guest app reads its own signed, bundled JavaScript. WebContent does
    // not need permission to traverse a LiveContainer guest's bundle path.
    NSURL *scriptURL = [[NSBundle mainBundle] URLForResource:@"music-cd" withExtension:@"js" subdirectory:@"CDCase"];
    NSData *scriptData = scriptURL ? [NSData dataWithContentsOfURL:scriptURL options:0 error:NULL] : nil;
    NSString *source = scriptData.length && scriptData.length < 4*1024*1024 ? [[NSString alloc] initWithData:scriptData encoding:4] : nil;
    if (!source.length) { [self recordRendererFailure:@"bundled-renderer-missing"]; [self failRenderer]; return; }
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    configuration.websiteDataStore = GMCDSharedHub().dataStore;
    WKUserContentController *controller = [WKUserContentController new];
    self.scriptProxy = [GMCDScriptProxy new]; self.scriptProxy.owner = self;
    [controller addScriptMessageHandler:self.scriptProxy name:@"musicCD"];
    [controller addUserScript:[[WKUserScript alloc] initWithSource:source injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES]];
    configuration.userContentController = controller;
    WKWebView *web = [[WKWebView alloc] initWithFrame:self.bounds configuration:configuration];
    web.userInteractionEnabled = NO; web.accessibilityElementsHidden = YES;
    web.opaque = NO; web.backgroundColor = [UIColor clearColor];
    web.underPageBackgroundColor = [UIColor clearColor];
    web.scrollView.backgroundColor = [UIColor clearColor]; web.scrollView.scrollEnabled = NO;
    web.scrollView.contentInsetAdjustmentBehavior = 2;
    web.scrollView.showsVerticalScrollIndicator = NO; web.scrollView.showsHorizontalScrollIndicator = NO;
    web.allowsBackForwardNavigationGestures = NO; web.allowsLinkPreview = NO; web.navigationDelegate = self;
    self.webView = web; self.rendererGeneration++; self.rendererArtworkRevision = self.artworkRevision;
    self.bridgeReady = NO; self.rendered = NO; self.evaluating = NO; self.rendererFailureReason = nil;
    // The real renderer must not be occluded by its own placeholder while
    // waiting for WebKit's first-frame acknowledgement.
    [self addSubview:web]; [self bringSubviewToFront:self.rendererStatusLabel];
    [self showRendererStatus:@"Loading 3D case…"];
    self.pending = [NSMutableDictionary dictionary];
    self.pending[@"quality"] = self.presentation == GMCDCasePresentationGrid ? @"grid" : @"hero";
    self.pending[@"background"] = self.backgroundComponents ?: @[@1,@1,@1];
    self.pending[@"open"] = @(self.caseOpen); self.pending[@"animateOpen"] = @NO;
    self.pending[@"art"] = self.encodedArtwork ?: (id)[NSNull null];
    [self queueMotionState]; [self ensureEncodedArtwork];
    NSString *html = @"<!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no'><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src data:; connect-src 'none'; font-src 'none'; media-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'\"><style>html,body,#case{position:absolute;inset:0;width:100%;height:100%;margin:0;padding:0;overflow:hidden;background:transparent;touch-action:none;-webkit-user-select:none}canvas{display:block;width:100%;height:100%;background:transparent}</style></head><body><div id='case'></div></body></html>";
    [web loadHTMLString:html baseURL:nil];
    NSUInteger generation = self.rendererGeneration;
    __weak GMCDCaseView *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(60*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        GMCDCaseView *view = weakSelf;
        if (!view || view.rendererGeneration != generation || view.rendered || !view.ownerActive) return;
        [view recordRendererFailure:@"first-frame-timeout"]; [view failRenderer];
    });
}
- (void)showRendererStatus:(NSString *)message {
    self.rendererStatusLabel.text = message; self.rendererStatusLabel.hidden = !message.length;
    [self setNeedsLayout];
}
- (void)recordRendererFailure:(NSString *)reason {
    self.rendererFailureReason = reason ?: @"unknown-renderer-error";
    NSLog(@"Music CD renderer: %@",self.rendererFailureReason);
}
- (void)retryRenderer {
    self.failedThisActivation = NO; self.automaticRetries = 0;
    [self stopRendererKeepingStill:NO]; [GMCDSharedHub() reconcile];
}
- (void)checkBridgeAfterNavigation {
    NSUInteger generation = self.rendererGeneration;
    __weak GMCDCaseView *weakSelf = self;
    [self.webView evaluateJavaScript:@"typeof window.MusicCD === 'object'" completionHandler:^(id result,NSError *error) {
        GMCDCaseView *view = weakSelf;
        if (!view || view.rendererGeneration != generation) return;
        if (!error && [result respondsToSelector:@selector(boolValue)] && [result boolValue]) {
            view.bridgeReady = YES; [view queueMotionState]; [view flushPending];
        } else { [view recordRendererFailure:@"bootstrap-not-installed"]; [view failRenderer]; }
    }];
}
'''
(root / p).write_text(source[:start] + bootstrap + source[end:])
replace(p, '    if (self.encodedRevision != self.artworkRevision) { [self ensureEncodedArtwork]; return; }', '''    // Commands and first-frame rendering must not wait for artwork decoding.
    // The separately queued data image replaces the initial disc when ready.''')
replace(p, 'if (error) { [view failRenderer]; return; }', 'if (error) { [view recordRendererFailure:[NSString stringWithFormat:@"javascript-%ld",(long)error.code]]; [view failRenderer]; return; }')
replace(p, '        self.fallback.hidden = YES;\n        [GMCDSharedHub() updateMotionDemand];', '''        self.fallback.hidden = YES; self.automaticRetries = 0; [self showRendererStatus:nil];
        [GMCDSharedHub() updateMotionDemand];''')
replace(p, '    } else if ([type isEqualToString:@"failed"]) [self failRenderer];', '''    } else if ([type isEqualToString:@"failed"]) {
        id reason = ((NSDictionary *)message.body)[@"reason"];
        [self recordRendererFailure:[reason isKindOfClass:[NSString class]] ? reason : @"webgl-initialization"];
        [self failRenderer];
    }''')
replace(p, '''    [self stopRendererKeepingStill:NO];
    [GMCDSharedHub() reconcile];
}
- (void)webView:(WKWebView *)webView decidePolicy''', '''    [self stopRendererKeepingStill:NO];
    [self showRendererStatus:@"3D case unavailable"];
    [GMCDSharedHub() reconcile];
}
- (void)webView:(WKWebView *)webView decidePolicy''')
replace(p, '''    NSURL *url = action.request.URL.URLByStandardizingPath;
    NSString *prefix = [self.resourceDirectory.path stringByAppendingString:@"/"];
    BOOL local = webView == self.webView && url.fileURL && prefix.length > 1 && [url.path hasPrefix:prefix];''', '''    NSURL *url = action.request.URL;
    BOOL local = webView == self.webView && [url.absoluteString isEqualToString:@"about:blank"];''')
replace(p, '''    // The JS ready message, not load completion, establishes the bridge.
    if (webView == self.webView) [self flushPending];''', '''    if (webView == self.webView) [self checkBridgeAfterNavigation];''')
replace(p, '''- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    if (webView == self.webView) [self failRenderer];
}''', '''- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    if (webView != self.webView) return;
    [self recordRendererFailure:@"web-content-process-terminated"]; [self failRenderer];
    if (self.automaticRetries >= 1) return;
    self.automaticRetries++;
    NSUInteger generation = self.rendererGeneration;
    __weak GMCDCaseView *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.8*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        GMCDCaseView *view = weakSelf;
        if (!view || view.rendererGeneration != generation || !view.ownerActive) return;
        view.failedThisActivation = NO; [GMCDSharedHub() reconcile];
    });
}''')
p = 'Sources/UIKitCDCaseAdditions.h'
replace(p, '@interface NSURLRequest : NSObject <NSCopying>', '''typedef unsigned long long dispatch_time_t;
typedef long long int64_t;
#define DISPATCH_TIME_NOW 0
#define NSEC_PER_SEC 1000000000ull
extern dispatch_time_t dispatch_time(dispatch_time_t when, int64_t delta);
extern void dispatch_after(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t block);
extern void NSLog(NSString *format, ...);
@interface NSError (GMCDDiagnosticCode)
@property(readonly) NSInteger code;
@end
@interface NSURLRequest : NSObject <NSCopying>''')
replace(p, '@interface WKUserContentController : NSObject', '''typedef NSInteger WKUserScriptInjectionTime;
enum { WKUserScriptInjectionTimeAtDocumentStart = 0, WKUserScriptInjectionTimeAtDocumentEnd = 1 };
@interface WKUserScript : NSObject
- (instancetype)initWithSource:(NSString *)source injectionTime:(WKUserScriptInjectionTime)injectionTime forMainFrameOnly:(BOOL)forMainFrameOnly;
@end
@interface WKUserContentController : NSObject
- (void)addUserScript:(WKUserScript *)userScript;''')
replace(p, '- (WKNavigation *)loadFileURL:(NSURL *)URL allowingReadAccessToURL:(NSURL *)readAccessURL;', '- (WKNavigation *)loadFileURL:(NSURL *)URL allowingReadAccessToURL:(NSURL *)readAccessURL;\n- (WKNavigation *)loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL;')
p = 'Sources/BrowseUI.m'
replace(p, 'self.caseView.frame = CGRectMake(0,0,w,w); self.nameLabel.frame = CGRectMake(0,w+8,w,20); self.artistLabel.frame = CGRectMake(0,w+30,w,18);', 'self.caseView.frame = CGRectMake(0,0,w,w); self.nameLabel.frame = CGRectMake(2,w+3,w-4,20); self.artistLabel.frame = CGRectMake(2,w+24,w-4,18);')
replace(p, '(self.contentView.bounds.size.width-56)/2', '(self.contentView.bounds.size.width-32)/2')
replace(p, 'self.leftTile.frame = CGRectMake(20,0,w,w+52); self.rightTile.frame = CGRectMake(36+w,0,w,w+52);', 'self.leftTile.frame = CGRectMake(12,0,w,w+45); self.rightTile.frame = CGRectMake(20+w,0,w,w+45);')
replace(p, '(table.bounds.size.width-56)/2)+65', '(table.bounds.size.width-32)/2)+54')
p = 'Sources/CDCaseJS/stage.js'
replace(p, 'const FIT = 0.86;', 'const FIT = 0.94;')
replace(p, '(CASE * 1.16)', '(CASE * 1.065)')
replace(p, "  renderer.debug.onShaderError = () => fatal('shader-compile');", """  renderer.debug.onShaderError = (gl, program, vertex, fragment) => {
    const details = [gl.getProgramInfoLog(program),gl.getShaderInfoLog(vertex),gl.getShaderInfoLog(fragment)].filter(Boolean).join(' | ');
    fatal('shader-compile: ' + details.slice(0,1800));
  };""")
replace(p, '  let firstFrame = true;', '  let firstFrame = true;\n  let frameCount = 0;')
replace(p, '  function draw() {', '  function draw() {\n    frameCount++;')
replace(p, 'fpsLimit: targetFPS, active: !!control.active,', 'fpsLimit: targetFPS, playing: !!control.playing, reducedMotion: !!control.reducedMotion, frameCount, active: !!control.active,')
replace(p, 'open: st.open, phase: st.phase, spin: st.spin, artMix,', 'open: st.open, phase: st.phase, spin: st.spin, tiltX:lean.x, tiltY:lean.y, artMix,')
replace('Sources/CDCaseJS/bridge.js', "reportFailure(error?.name || 'initialization');", "reportFailure((error?.name || 'initialization') + ': ' + (error?.message || '').slice(0,1000));")
p = root / 'Resources/Info.plist'
d = plistlib.loads(p.read_bytes()); d['CFBundleShortVersionString'] = '0.12'; d['CFBundleVersion'] = '13'
p.write_bytes(plistlib.dumps(d,sort_keys=False))
print('Applied Music 0.12 (13) repair; regenerate the bundled renderer before building.')
