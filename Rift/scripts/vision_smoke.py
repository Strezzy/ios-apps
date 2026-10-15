#!/usr/bin/env python3
"""Only the newly added Qwen 3.5 4B image path and connected text fallback."""
import hashlib,json,os,subprocess,urllib.request,urllib.parse
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]; BUILD=ROOT/'Build'; SOURCE=ROOT/'ThirdParty/llama'
model=next(m for m in json.loads((ROOT/'Rift/Resources/catalog.json').read_text()) if m['id']=='qwen35-4b')
projector={'filename':'mmproj-Qwen3.5-4B-Uncensored-HauhauCS-Aggressive-BF16.gguf','bytes':675568768,'sha256':'a1e32e86ea99aa7a56f3dcfe7e63c1d0be9439d31fd07087099f15bc0fda0f22'}
paths=[]
for item in [model,projector]:
 path=BUILD/item['filename']; paths.append(path)
 url='https://huggingface.co/'+model['repo']+'/resolve/'+model['revision']+'/'+urllib.parse.quote(item['filename'])
 digest=hashlib.sha256(); count=0
 print('Downloading selected Qwen 4B component:',item['filename'],flush=True)
 with urllib.request.urlopen(url,timeout=120) as response,path.open('wb') as out:
  while chunk:=response.read(1024*1024):
   count+=len(chunk); assert count<=item['bytes']; digest.update(chunk);out.write(chunk)
 assert count==item['bytes'] and digest.hexdigest()==item['sha256']
args=['xcrun','clang++','-std=c++17','-fobjc-arc','-fblocks','-O2','-I'+str(ROOT/'Rift/Native')]
for path in ['include','ggml/include','common','vendor','vendor/nlohmann','tools/mtmd']:args+=['-I'+str(SOURCE/path)]
args += [str(ROOT/'scripts/vision_smoke.mm'),str(ROOT/'Rift/Native/RiftEngine.mm'),str(BUILD/'Native/macosx/libruntime.a'),'-framework','Foundation','-framework','Accelerate','-framework','Security','-framework','Metal','-lc++','-lz','-o',str(BUILD/'vision-smoke')]
subprocess.run(args,check=True)
for index in range(2):
 image=Image.new('RGB',(448,448),'white');draw=ImageDraw.Draw(image)
 if index==0:draw.ellipse((80,80,368,368),fill=(230,0,0))
 else:draw.rectangle((80,80,368,368),fill=(0,35,235))
 image.save(BUILD/f'input-{index}.png')
process=subprocess.run([str(BUILD/'vision-smoke'),*[str(p) for p in paths],str(BUILD/'input-0.png'),str(BUILD/'input-1.png')],capture_output=True,text=True,timeout=600)
print(process.stdout,flush=True);print(process.stderr[-5000:],flush=True)
report=json.loads(process.stdout)
report.update(source=os.environ['RIFT_SOURCE'],model_id=model['id'],model_sha256=model['sha256'],projector_sha256=projector['sha256'],exit_code=process.returncode)
(BUILD/'VISION-SMOKE.json').write_text(json.dumps(report,indent=2)+'\n')
assert process.returncode==0 and report['passed'] and len(report['answers'])==3
for path in paths:path.unlink(missing_ok=True)
