#!/usr/bin/env python3
"""Apply the reviewed 0.13 delta and extend the existing native test harnesses."""
from pathlib import Path
import hashlib, json, plistlib, subprocess
root = Path(__file__).resolve().parents[1]
subprocess.run(['git','apply','--check','MusicPolish13/renderer.patch','MusicPolish13/native.patch'],cwd=root,check=True)
protected = ['Music/Sources/main.m','Music/Sources/BrowseUI.m','Music/Sources/MusicCDInspector.m','Music/Sources/MusicAppearance.m','Music/Sources/MusicArtworkBackdrop.m']
before = {p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in protected}
subprocess.run(['git','apply','MusicPolish13/renderer.patch','MusicPolish13/native.patch'],cwd=root,check=True)
# Pending native covers must not announce a visible frame, even if the neutral
# placeholder texture has already rendered. This prevents an old/default cover
# from briefly appearing when an idle renderer is assigned to another album.
p = root/'Music/Sources/CDCaseJS/stage.js'
s = p.read_text(); needle='if (!artLoading && !failed && (firstFrame || announcedFrame !== frameKey))'
assert s.count(needle)==1
p.write_text(s.replace(needle,"if (!artLoading && control.artToken !== 'pending' && !failed && (firstFrame || announcedFrame !== frameKey))"))
after = {p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in protected}
assert before == after, 'An approved layout or native glass implementation changed'
(root/'Evidence').mkdir(exist_ok=True)
(root/'Evidence/UI-PRESERVATION.json').write_text(json.dumps({'unchanged':before,'albumTileLayoutUnchanged':True,'nativeGlassDockUnchanged':True},indent=2)+'\n')
info=plistlib.loads((root/'Music/Resources/Info.plist').read_bytes())
assert (info['CFBundleShortVersionString'],info['CFBundleVersion'],info['CFBundleIdentifier'])==('0.13','14','com.billy.glassmusic')

# Keep all original working Open/Close, spin, artwork, and playback assertions.
# Generate test-only copies; no fixture classes are shipped in Music.ipa.
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
    if(t==29){self.checks[@"closed_extreme_corners_fit"]=@([state[@"fittedExtent"] doubleValue]<.99);
        [self.caseView setActive:NO];
        self.checks[@"idle_cache_bounded"]=@(GMCDSharedHub().warmRenderers.count<=2);
        [GMCDSharedHub() memoryWarning:nil];
        self.checks[@"memory_warning_releases_cache"]=@(GMCDSharedHub().warmRenderers.count==0);
        [self finish];''')
(root/'MusicPolish13/RendererProbe.m').write_text(s)

s=(root/'MusicChecks/GridProbe.m').read_text()
s=s.replace('@property(nonatomic) NSInteger ticks;', '@property(nonatomic) NSInteger ticks;\n@property(nonatomic) BOOL testedScroll;')
s=s.replace('i<6;i++','i<18;i++').replace('imageNamed:covers[i]','imageNamed:covers[i%6]')
s=s.replace('@"webView":@(view.webView!=nil)', '@"firstFrameSeconds":@(view.firstFrameSeconds),@"usedWarmRenderer":@(view.usedWarmRenderer),@"webView":@(view.webView!=nil)')
s=s.replace('[state[@"ready"] boolValue] &&', '[state[@"ready"] boolValue] && [state[@"pixelRatio"] doubleValue]>=2 && [state[@"msaaSamples"] integerValue]>=2 && [state[@"fittedExtent"] doubleValue]<.99 &&')
s=s.replace('if(passed||self.ticks>=120){', '''if(passed && !self.testedScroll){
            self.testedScroll=YES;[self.initialSpins removeAllObjects];
            [self.shell.albumsController.table setContentOffset:CGPointMake(0,240) animated:NO];
            return;
        }
        if(passed||self.ticks>=120){''')
s=s.replace('NSDictionary *result=@{@"passed":@(passed),', '''passed=passed && self.testedScroll && GMCDSharedHub().rendererReuses>0;
            NSDictionary *result=@{@"passed":@(passed),@"rendererReuses":@(GMCDSharedHub().rendererReuses),@"rendererAllocations":@(GMCDSharedHub().rendererAllocations),''')
(root/'MusicPolish13/GridProbe.m').write_text(s)
print('Music 0.13 prepared; approved navigation and layout hashes preserved')
