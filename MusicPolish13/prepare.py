#!/usr/bin/env python3
"""Apply the 0.13 delta and extend the existing production-code native probes."""
from pathlib import Path
import hashlib, json, plistlib, subprocess
root = Path(__file__).resolve().parents[1]
subprocess.run(['git','apply','--check','MusicPolish13/renderer.patch','MusicPolish13/native.patch'],cwd=root,check=True)
protected = ['Music/Sources/main.m','Music/Sources/BrowseUI.m','Music/Sources/MusicCDInspector.m','Music/Sources/MusicAppearance.m','Music/Sources/MusicArtworkBackdrop.m']
before = {p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in protected}
subprocess.run(['git','apply','MusicPolish13/renderer.patch','MusicPolish13/native.patch'],cwd=root,check=True)
# Do not reveal a neutral or previous cover while the requested cover decodes.
p = root/'Music/Sources/CDCaseJS/stage.js'
s = p.read_text(); needle='if (!artLoading && !failed && (firstFrame || announcedFrame !== frameKey))'
assert s.count(needle)==1
s=s.replace(needle,"if (!artLoading && control.artToken !== 'pending' && !failed && (firstFrame || announcedFrame !== frameKey))")
# Actual case geometry fits within +/-74.10 horizontally, +/-73.45 vertically,
# and -5.2..6.1 in depth. Keep a conservative margin without over-zooming out.
start=s.index('  function fitPoseInsideArtwork()');end=s.index('  const _c =',start)
fit=s[start:end].replace('HALF + 3','HALF + 1.25').replace('-HALF - 3','-HALF - 1.25')
s=s[:start]+fit+s[end:];p.write_text(s)
# Four rows can be partially visible during a scroll. The six-renderer budget
# left two visible albums permanently static. Keep eight grid slots and one
# hero in total, with inactive slots paused and eligible for bounded reuse.
p=root/'Music/Sources/MusicCDCase.m';s=p.read_text()
assert s.count('if (grids >= 6) break;')==1
s=s.replace('if (grids >= 6) break;','if (grids >= 8) break;')
s=s.replace('while (self.warmRenderers.count > 2)','while (self.warmRenderers.count > 9)')
s=s.replace('// At most two already-rendered, paused WebViews can wait for reuse. They','// Recently rendered, paused WebViews can wait for reuse. The total budget is\n// eight grid contexts and one hero, including idle entries. They')
s=s.replace('// Two recent slots may survive navigation or row reuse; extra pooled\n    // views are evicted oldest-first. No unbounded WebGL cache.','// Retain the previous screen within the same context budget. Taking a\n    // matching idle slot precedes allocating another context. Extra idle\n    // entries are evicted oldest-first; every entry also expires after 20s.')
s=s.replace('self.presentation == GMCDCasePresentationGrid ? 0 : 8','self.presentation == GMCDCasePresentationGrid ? 4 : 8')
s=s.replace('CGFloat halo = grid ? 0 : 8;','CGFloat halo = grid ? 4 : 8;')
s=s.replace('self.pending[@"padding"] = @(halo);','self.pending[@"padding"] = @(grid ? 0 : halo);')
p.write_text(s)
after = {p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in protected}
assert before == after, 'An approved layout or native glass implementation changed'
(root/'Evidence').mkdir(exist_ok=True)
(root/'Evidence/UI-PRESERVATION.json').write_text(json.dumps({'unchanged':before,'albumTileLayoutUnchanged':True,'nativeGlassDockUnchanged':True,'gridTransparentMarginPoints':4,'heroTransparentMarginPoints':8},indent=2)+'\n')
info=plistlib.loads((root/'Music/Resources/Info.plist').read_bytes())
assert (info['CFBundleShortVersionString'],info['CFBundleVersion'],info['CFBundleIdentifier'])==('0.13','14','com.billy.glassmusic')

# Preserve all original Open/Close, spin, artwork and playback assertions.
s=(root/'MusicRepair/RendererProbe.m').read_text()
s=s.replace('@property(nonatomic) double pausedSpin;', '@property(nonatomic) double pausedSpin;\n@property(nonatomic) double coldSeconds;')
s=s.replace('@"nativeReady":@(self.caseView.bridgeReady),', '@"nativeReady":@(self.caseView.bridgeReady),@"nativeFirstFrameSeconds":@(self.caseView.firstFrameSeconds),@"warmRenderer":@(self.caseView.usedWarmRenderer),')
s=s.replace('self.initialSpin=spin;self.checks[@"native_first_frame"]=@YES;', '''self.initialSpin=spin;self.checks[@"native_first_frame"]=@YES;
            self.coldSeconds=self.caseView.firstFrameSeconds;
            self.checks[@"retina_rendering"]=@([state[@"pixelRatio"] doubleValue]>=2);
            self.checks[@"geometry_msaa"]=@([state[@"msaaSamples"] integerValue]>=2);
            self.checks[@"closed_corners_fit"]=@([state[@"fittedExtent"] doubleValue]<.99);''')
s=s.replace('if(t==1)self.initialSpin=spin;', '''if(t==1){self.initialSpin=spin;
        self.checks[@"hero_reuses_compiled_renderer"]=@(self.caseView.usedWarmRenderer && GMCDSharedHub().rendererAllocations==1);
        self.checks[@"correct_artwork_ticket"]=@([state[@"epoch"] isEqual:self.caseView.renderTicket] && ![state[@"artToken"] isEqual:@"pending"]);
        GMProbeJSON(@"loading-times.json",@{@"coldHeroSeconds":@(self.coldSeconds),@"warmHeroSeconds":@(self.caseView.firstFrameSeconds),@"rendererAllocations":@(GMCDSharedHub().rendererAllocations),@"rendererReuses":@(GMCDSharedHub().rendererReuses),@"environment":@"iOS simulator; not physical iPhone timing"});
    }''')
s=s.replace('[self capture:@"Native-Player.png"];[self finish];','''[self capture:@"Native-Player.png"];
    }
    if(t==20){[self.caseView setCaseOpen:YES animated:NO];[self.caseView setInspectionTiltX:1 y:1];}
    if(t==23){self.checks[@"open_extreme_corners_fit"]=@([state[@"fittedExtent"] doubleValue]<.99);[self capture:@"Native-Open-Extreme.png"];[self.caseView setInspectionTiltX:-1 y:-1];}
    if(t==26){self.checks[@"opposite_extreme_corners_fit"]=@([state[@"fittedExtent"] doubleValue]<.99);[self.caseView setCaseOpen:NO animated:NO];}
    if(t>=29 && self.pendingCaptures==0){self.checks[@"closed_extreme_corners_fit"]=@([state[@"fittedExtent"] doubleValue]<.99);
        [self.caseView setActive:NO];
        self.checks[@"idle_cache_bounded"]=@(GMCDSharedHub().warmRenderers.count<=9);
        [GMCDSharedHub() memoryWarning:nil];
        self.checks[@"memory_warning_releases_cache"]=@(GMCDSharedHub().warmRenderers.count==0);
        [self finish];''')
(root/'MusicPolish13/RendererProbe.m').write_text(s)

s=(root/'MusicChecks/GridProbe.m').read_text()
s=s.replace('@property(nonatomic) NSInteger ticks;', '@property(nonatomic) NSInteger ticks;\n@property(nonatomic) NSInteger scrollStage;\n@property(nonatomic) CGPoint firstOffset;')
s=s.replace('i<6;i++','i<18;i++').replace('imageNamed:covers[i]','imageNamed:covers[i%6]')
s=s.replace('@"webView":@(view.webView!=nil)', '@"firstFrameSeconds":@(view.firstFrameSeconds),@"usedWarmRenderer":@(view.usedWarmRenderer),@"webView":@(view.webView!=nil)')
s=s.replace('[state[@"ready"] boolValue] &&', '[state[@"ready"] boolValue] && [state[@"pixelRatio"] doubleValue]>=2 && [state[@"msaaSamples"] integerValue]>=2 && [state[@"fittedExtent"] doubleValue]<.99 &&')
s=s.replace('if(passed||self.ticks>=120){', '''if(passed && self.scrollStage==0){
            self.firstOffset=self.shell.albumsController.table.contentOffset;
            self.scrollStage=1;[self.initialSpins removeAllObjects];
            [self.shell.albumsController.table setContentOffset:CGPointMake(0,240) animated:NO];
            return;
        }
        if(passed && self.scrollStage==1){
            self.scrollStage=2;[self.initialSpins removeAllObjects];
            [self.shell.albumsController.table setContentOffset:self.firstOffset animated:NO];
            return;
        }
        if(passed||self.ticks>=120){''')
s=s.replace('NSDictionary *result=@{@"passed":@(passed),', '''NSUInteger totalContexts=GMCDSharedHub().warmRenderers.count;
            for(GMCDCaseView *v in GMCDSharedHub().views.allObjects)if(v.webView)totalContexts++;
            passed=passed && self.scrollStage==2 && GMCDSharedHub().rendererReuses>=4 && totalContexts<=9;
            NSDictionary *result=@{@"passed":@(passed),@"scrollAndReturnVerified":@(self.scrollStage==2),@"totalLiveAndIdleContexts":@(totalContexts),@"rendererReuses":@(GMCDSharedHub().rendererReuses),@"rendererAllocations":@(GMCDSharedHub().rendererAllocations),''')
(root/'MusicPolish13/GridProbe.m').write_text(s)
print('Music 0.13 prepared; approved navigation and layout hashes preserved')
