#!/usr/bin/env python3
"""Production Swift downloads + bounded hashing + real two-turn native inference."""
import hashlib,json,os,subprocess,sys,urllib.parse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; BUILD=ROOT/'Build'; SOURCE=ROOT/'ThirdParty/llama'
BUILD.mkdir(exist_ok=True)
metal=os.getenv('RIFT_PROBE_BACKEND')=='metal'
args=['xcrun','clang++','-std=c++17','-fobjc-arc','-fblocks','-O2','-I'+str(ROOT/'Rift/Native')]
for path in ['include','ggml/include','common','vendor','vendor/nlohmann']: args+=['-I'+str(SOURCE/path)]
args += [str(ROOT/'scripts/smoke.mm'),str(ROOT/'Rift/Native/RiftEngine.mm'),str(BUILD/'Native/macosx/libruntime.a'),'-framework','Foundation','-framework','Accelerate','-framework','Security','-framework','Metal','-lc++','-lz','-o',str(BUILD/'rift-smoke')]
subprocess.run(args,check=True)
subprocess.run(['xcrun','swiftc','-O','-swift-version','5',str(ROOT/'Rift/GGUF.swift'),str(ROOT/'Rift/DownloadJob.swift'),str(ROOT/'scripts/TransferProbe.swift'),'-o',str(BUILD/'transfer-probe')],check=True)
models=json.loads((ROOT/'Rift/Resources/catalog.json').read_text())
ids=set(filter(None,os.getenv('RIFT_MODEL_IDS','').split(',')))
if ids:
 assert ids<=set(m['id'] for m in models)
 models=[m for m in models if m['id'] in ids]
reports=[]
output=BUILD/('METAL-SMOKE.json' if metal else 'MODEL-SMOKE.json')
for model in models:
 path=BUILD/(model['id']+'.gguf')
 url='https://huggingface.co/'+model['repo']+'/resolve/'+model['revision']+'/'+urllib.parse.quote(model['filename'],safe='/')
 try:
  print('PRODUCTION SWIFT DOWNLOAD',model['id'],model['bytes'],flush=True)
  transfer=subprocess.run([str(BUILD/'transfer-probe'),url,str(path),str(model['bytes']),model['sha256']],capture_output=True,text=True,timeout=1200)
  print(transfer.stdout,flush=True);print(transfer.stderr[-4000:],flush=True)
  assert transfer.returncode==0,'Production transfer/verification failed: '+model['id']
  evidence=json.loads(transfer.stdout)
  assert evidence['sha256']==model['sha256'] and evidence['architecture']==model['architecture']
  process=subprocess.run([str(BUILD/'rift-smoke'),str(path),'metal' if metal else 'cpu'],capture_output=True,text=True,timeout=600)
  print(process.stdout,flush=True);print(process.stderr[-3000:],flush=True)
  result={'id':model['id'],'exit_code':process.returncode,'stdout':process.stdout,'stderr':process.stderr[-3000:],'file_sha256':model['sha256'],'backend':'macOS Metal' if metal else 'macOS CPU','physical_iPhone_test':False,'transfer':evidence,'source':os.getenv('RIFT_SOURCE',os.getenv('GITHUB_SHA','local'))}
  reports.append(result);output.write_text(json.dumps(reports,indent=2))
  assert process.returncode==0,'Native inference failed: '+model['id']
  assert len(json.loads(process.stdout)['answers'])==2
 finally:path.unlink(missing_ok=True)
print('All selected models passed production downloads and actual two-turn inference.',flush=True)
