#!/usr/bin/env python3
"""Actual local CPU inference for every catalog entry, not simulated tokens."""
import hashlib,json,os,shutil,subprocess,urllib.parse,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; BUILD=ROOT/'Build'; SOURCE=ROOT/'ThirdParty/llama'
args=['xcrun','clang++','-std=c++17','-fobjc-arc','-fblocks','-O2','-I'+str(ROOT/'Rift/Native')]
for path in ['include','ggml/include','common','vendor','vendor/nlohmann']: args += ['-I'+str(SOURCE/path)]
args += [str(ROOT/'scripts/smoke.mm'),str(ROOT/'Rift/Native/RiftEngine.mm'),str(BUILD/'Native/macosx/libruntime.a'),'-framework','Foundation','-framework','Accelerate','-framework','Security','-lc++','-lz','-o',str(BUILD/'rift-smoke')]
subprocess.run(args,check=True)
models=json.loads((ROOT/'Rift/Resources/catalog.json').read_text()); reports=[]
for model in models:
    path=BUILD/(model['id']+'.gguf')
    url='https://huggingface.co/'+model['repo']+'/resolve/'+model['revision']+'/'+urllib.parse.quote(model['filename'],safe='/')
    try:
        print('Downloading smoke model:',model['id'],flush=True)
        request=urllib.request.Request(url,headers={'User-Agent':'Rift-build/1.0'})
        with urllib.request.urlopen(request,timeout=180) as response,path.open('wb') as f: shutil.copyfileobj(response,f,1024*1024)
        with path.open('rb') as f: digest=hashlib.file_digest(f,'sha256').hexdigest()
        assert digest==model['sha256'] and path.stat().st_size==model['bytes'],'Model identity mismatch'
        process=subprocess.run([str(BUILD/'rift-smoke'),str(path)],capture_output=True,text=True,timeout=480)
        print(process.stdout,flush=True); print(process.stderr[-3000:],flush=True)
        result={'id':model['id'],'exit_code':process.returncode,'stdout':process.stdout,'stderr':process.stderr[-3000:],'file_sha256':digest,'backend':'macOS CPU','physical_iPhone_test':False}
        reports.append(result)
        (BUILD/'MODEL-SMOKE.json').write_text(json.dumps(reports,indent=2))
        if process.returncode: raise RuntimeError('Native inference smoke failed for '+model['id'])
    finally:
        path.unlink(missing_ok=True)
print('All catalog models completed native CPU inference.',flush=True)
