#!/usr/bin/env python3
"""Resolve only reviewed uncensored repositories, pin file identities, and prepare native sources."""
import base64, hashlib, json, os, re, shutil, subprocess, tarfile, time, urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'Build'; RES=ROOT/'Rift/Resources'
LLAMA='8345f333951c661d166b00e6f9362e553768f292'
SPECS=[
 dict(id='qwen35-2b',name='Qwen3.5 2B',family='Qwen',badge='Fast & light',detail='A lighter everyday assistant. Less depth, less memory.',repo='HauhauCS/Qwen3.5-2B-Uncensored-HauhauCS-Aggressive',minimumRAM=6,workingGB=2.3,rank=20,architecture='qwen35'),
 dict(id='qwen35-4b',name='Qwen3.5 4B',family='Qwen',badge='Balanced',detail='The middle ground for writing, questions, and code.',repo='HauhauCS/Qwen3.5-4B-Uncensored-HauhauCS-Aggressive',minimumRAM=8,workingGB=3.8,rank=40,architecture='qwen35'),
 dict(id='qwen35-9b',name='Qwen3.5 9B',family='Qwen',badge='Deeper answers',detail='The larger Qwen option. More memory and slower replies.',repo='HauhauCS/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive',minimumRAM=12,workingGB=7.0,rank=90,architecture='qwen35'),
 dict(id='gemma4-e2b',name='Gemma 4 E2B',family='Gemma',badge='Lighter Gemma',detail='A compact alternative for conversation and writing.',repo='HauhauCS/Gemma-4-E2B-Uncensored-HauhauCS-Aggressive',minimumRAM=8,workingGB=4.0,rank=20,architecture='gemma4'),
 dict(id='gemma4-e4b',name='Gemma 4 E4B',family='Gemma',badge='More depth',detail='The larger Gemma option. More room for nuanced replies.',repo='HauhauCS/Gemma-4-E4B-Uncensored-HauhauCS-Aggressive',minimumRAM=12,workingGB=7.0,rank=40,architecture='gemma4'),
 dict(id='lfm25-26b',name='LFM2.5 2.6B',family='Liquid',badge='Efficiency pick',detail='A small edge-focused model for lighter local conversations.',repo='noctrex/LFM2.5-2.6B-heretic-uncensored-GGUF',minimumRAM=6,workingGB=2.6,rank=26,architecture='lfm2'),
]
def get(url):
    for attempt in range(4):
        try:
            request=urllib.request.Request(url,headers={'User-Agent':'Rift-build/1.0'})
            with urllib.request.urlopen(request,timeout=120) as response: return response.read()
        except Exception:
            if attempt==3: raise
            time.sleep(2**attempt)
def download(url,path):
    path.parent.mkdir(parents=True,exist_ok=True)
    with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'Rift-build/1.0'}),timeout=180) as r, path.open('wb') as f: shutil.copyfileobj(r,f,1024*1024)
def catalog():
    target=RES/'catalog.json'
    if target.exists():
        models=json.loads(target.read_text())
        assert all(x['uncensored'] and re.fullmatch('[0-9a-f]{64}',x['sha256']) and re.fullmatch('[0-9a-f]{40}',x['revision']) for x in models)
        return
    models=[]; rejected=[]
    for spec in SPECS:
        try:
            info=json.loads(get('https://huggingface.co/api/models/'+spec['repo']+'?blobs=true'))
            revision=info['sha']; assert re.fullmatch('[0-9a-f]{40}',revision)
            files=info.get('siblings',[]); selected=None; quant=None
            for q in ['Q4_K_M','IQ4_XS','Q4_K_S','IQ3_M']:
                candidates=[f for f in files if re.search(r'[-_.]'+q+r'\.gguf$',f['rfilename'],re.I) and 'mmproj' not in f['rfilename'].lower()]
                if len(candidates)==1: selected=candidates[0]; quant=q; break
            if not selected: raise RuntimeError('No single reviewed 4-bit quantization found')
            lfs=selected.get('lfs',{}); sha=lfs.get('sha256'); size=lfs.get('size') or selected.get('size')
            if not sha or not size:
                tree=json.loads(get('https://huggingface.co/api/models/'+spec['repo']+'/tree/'+revision+'?recursive=true'))
                match=next(f for f in tree if f.get('path')==selected['rfilename'])
                lfs=match.get('lfs',{}); sha=lfs.get('oid') or lfs.get('sha256'); size=lfs.get('size') or match.get('size')
            assert re.fullmatch('[0-9a-f]{64}',sha or '') and 10_000_000 < int(size) < 10_000_000_000
            license=info.get('cardData',{}).get('license','See model source')
            if isinstance(license,list): license=', '.join(license)
            item=dict(spec,revision=revision,filename=selected['rfilename'],bytes=int(size),sha256=sha,variant=quant,license=license,licenseText='The model remains under its publisher\'s and base model\'s license. Review the source and license before downloading. Rift does not bundle model weights.',uncensored=True)
            models.append(item)
            print('PINNED',item['id'],revision,selected['rfilename'],size,sha,flush=True)
        except Exception as error:
            rejected.append({'repo':spec['repo'],'reason':str(error)})
            print('EXCLUDED',spec['repo'],error,flush=True)
    assert len(models)>=3 and any(m['family']=='Qwen' and m['minimumRAM']==6 for m in models), 'Insufficient verified catalog entries'
    target.write_text(json.dumps(models,indent=2)+'\n')
    (BUILD/'catalog-resolution.json').write_text(json.dumps({'researched':'2026-10-14','included':models,'excluded':rejected},indent=2))
def source():
    directory=ROOT/'ThirdParty/llama'
    if (directory/'include/llama.h').exists(): return
    archive=BUILD/'llama.tar.gz'; download('https://github.com/ggml-org/llama.cpp/archive/'+LLAMA+'.tar.gz',archive)
    parent=directory.parent; parent.mkdir(parents=True,exist_ok=True)
    with tarfile.open(archive) as t:
        for member in t.getmembers():
            if '..' in Path(member.name).parts or member.name.startswith('/'): raise RuntimeError('Unsafe source archive')
        t.extractall(parent,filter='data')
    (parent/('llama.cpp-'+LLAMA)).rename(directory)
    notices=['Rift 1.0\nllama.cpp source revision: '+LLAMA+'\nhttps://github.com/ggml-org/llama.cpp\n']
    for path in [directory/'LICENSE',directory/'ggml/LICENSE']:
        if path.exists(): notices.append(path.read_text())
    (RES/'ThirdPartyNotices.txt').write_text('\n\n'.join(notices))
def icon():
    from PIL import Image
    pieces=sorted((ROOT/'Branding').glob('icon-*.b64'))
    if not pieces: raise RuntimeError('Approved Rift icon has not been supplied')
    image=BUILD/'icon.webp'; image.write_bytes(base64.b64decode(''.join(p.read_text().strip() for p in pieces),validate=True))
    assets=ROOT/'Rift/Assets.xcassets'; app=assets/'AppIcon.appiconset'; app.mkdir(parents=True,exist_ok=True)
    Image.open(image).convert('RGB').resize((1024,1024),Image.Resampling.LANCZOS).save(app/'Rift.png')
    (assets/'Contents.json').write_text(json.dumps({'info':{'version':1,'author':'xcode'}}))
    (app/'Contents.json').write_text(json.dumps({'images':[{'idiom':'universal','platform':'ios','size':'1024x1024','filename':'Rift.png'}],'info':{'version':1,'author':'xcode'}},indent=2))
if __name__=='__main__':
    BUILD.mkdir(exist_ok=True); RES.mkdir(parents=True,exist_ok=True)
    catalog(); source(); icon()
