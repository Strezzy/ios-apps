#!/usr/bin/env python3
"""Add specifically reviewed Heretic quantizations, preserving all existing pins."""
import json,re,time,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
PATH=ROOT/'Rift/Resources/catalog.json'
ADDITIONS=[
 dict(id='heretic-qwen3-8b', name='Qwen3 8B', family='Qwen', group='Heretic', badge='8B · balanced', detail='Heretic-modified Qwen. More capability than tiny models, with a larger memory footprint.',repo='mradermacher/Qwen3-8B-heretic-GGUF', quant='Q4_K_M', minimumRAM=8,workingGB=5.4,rank=80,architecture='qwen3'),
 dict(id='heretic-qwen35-9b',name='Qwen3.5 9B',family='Qwen',group='Heretic',badge='9B · deeper answers',detail='A larger Heretic option. More memory and longer replies than the compact models.',repo='mradermacher/Qwen3.5-9B-heretic-GGUF',quant='Q4_K_M',minimumRAM=12,workingGB=6.2,rank=90,architecture='qwen35'),
 dict(id='heretic-qwen3-14b-compact',name='Qwen3 14B · Compact',family='Qwen',group='Heretic',badge='14B · smaller file',detail='Importance-calibrated 3-bit weights. Lower memory than the precision option, with a quality tradeoff.',repo='mradermacher/Qwen3-14B-heretic-i1-GGUF',quant='IQ3_XS',minimumRAM=12,workingGB=7.0,rank=140,architecture='qwen3',experimental=True),
 dict(id='heretic-qwen3-14b-quality',name='Qwen3 14B · Precision',family='Qwen',group='Heretic',badge='14B · higher precision',detail='Importance-calibrated 4-bit weights. A larger download and memory requirement; not a phone-speed guarantee.',repo='mradermacher/Qwen3-14B-heretic-i1-GGUF',quant='IQ4_XS',minimumRAM=12,workingGB=8.6,rank=141,architecture='qwen3',experimental=True),
]
def get(url):
 for attempt in range(4):
  try:
   with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'Rift-catalog/1.1'}),timeout=90) as r:return json.load(r)
  except Exception:
   if attempt==3:raise
   time.sleep(2**attempt)
def main():
 models=json.loads(PATH.read_text()); ids={m['id'] for m in models}
 for spec in ADDITIONS:
  if spec['id'] in ids:continue
  info=get('https://huggingface.co/api/models/'+spec['repo']+'?blobs=true')
  revision=info['sha'];assert re.fullmatch('[0-9a-f]{40}',revision)
  matches=[f for f in info['siblings'] if re.search(r'[-_.]'+spec['quant']+r'\.gguf$',f['rfilename'],re.I) and not any(x in f['rfilename'].lower() for x in ['mmproj','imatrix.gguf','mtp-'])]
  assert len(matches)==1,(spec['repo'],matches)
  file=matches[0];lfs=file.get('lfs',{});digest=lfs.get('sha256');size=lfs.get('size') or file.get('size')
  if not digest or not size:
   tree=get('https://huggingface.co/api/models/'+spec['repo']+'/tree/'+revision+'?recursive=true')
   entry=next(f for f in tree if f.get('path')==file['rfilename']); lfs=entry.get('lfs',{})
   digest=lfs.get('oid') or lfs.get('sha256');size=lfs.get('size') or entry.get('size')
  assert re.fullmatch('[0-9a-f]{64}',digest or '') and 1e9<int(size)<9e9
  item=dict(spec);item.pop('quant')
  item.update(variant=spec['quant'],filename=file['rfilename'],revision=revision,bytes=int(size),sha256=digest,license='apache-2.0',licenseText='Uncensored Heretic community derivative of Qwen, in GGUF format. The model and its modification remain under their authors\' licenses. See the linked source before downloading.',uncensored=True)
  models.append(item);print('PINNED',item['id'],item['filename'],size,digest,flush=True)
 assert len(models)==10
 PATH.write_text(json.dumps(models,indent=2)+'\n')
if __name__=='__main__':main()
