"""Build-time only downloads. The shipped app never downloads models or media."""
from pathlib import Path
import hashlib, importlib.util, json, os, shutil, subprocess, sys, tempfile
import numpy as np
import requests
import torch
import coremltools as ct
from PIL import Image

ROOT = Path.cwd()
OUT = ROOT / 'Loop/Resources'
MODELS = OUT / 'RealismModels'
PHOTOS = OUT / 'RealismBackdrops'
NOTICES = OUT / 'RealismLicenses'
for p in (MODELS, PHOTOS, NOTICES): p.mkdir(parents=True, exist_ok=True)
work = Path(tempfile.mkdtemp(prefix='loop-models-'))
report = {'models': [], 'backgrounds': [], 'runtimeNetworkAccess': False}
torch.set_num_threads(2)

def get(url, path):
    response = requests.get(url, timeout=180, headers={'User-Agent': 'Loop-asset-build/1.3 (offline redistribution; Poly Haven credit retained)'})
    response.raise_for_status(); path.write_bytes(response.content)
    return hashlib.sha256(response.content).hexdigest()

def checkout(repo, sha, name):
    path = work / name
    subprocess.run(['git','clone','--quiet','https://github.com/'+repo+'.git',str(path)], check=True)
    subprocess.run(['git','-C',str(path),'checkout','--quiet',sha],check=True)
    return path

def convert(model, name, license_name, source, checkpoint, output_color):
    model.eval()
    x = torch.linspace(-1, 1, 3*512*512).reshape(1,3,512,512)
    with torch.no_grad():
        reference = model(x).numpy()
        traced = torch.jit.trace(model, x)
    converted = ct.convert(traced, convert_to='mlprogram',
        inputs=[ct.ImageType(name='image', shape=x.shape, scale=1/127.5, bias=[-1,-1,-1],color_layout=ct.colorlayout.RGB)],
        outputs=[ct.ImageType(name='output',color_layout=output_color)],
        minimum_deployment_target=ct.target.iOS16, compute_precision=ct.precision.FLOAT16)
    converted.author = source
    converted.license = license_name
    converted.short_description = name+'; local inference; 512px analysis, composited into native-resolution footage'
    target = MODELS / (name+'.mlpackage'); converted.save(str(target))
    # Real Core ML inference on macOS, compared with the PyTorch conversion source.
    array = np.linspace(0,255,3*512*512).reshape(3,512,512).transpose(1,2,0).astype(np.uint8)
    image = Image.fromarray(array)
    native = np.asarray(converted.predict({'image':image})['output']).astype(np.float32)
    tensor = torch.from_numpy(array.copy()).permute(2,0,1)[None].float()/127.5-1
    with torch.no_grad(): expected = model(tensor).numpy()[0]
    if expected.shape[0] == 1: expected = expected[0]
    else: expected = expected.transpose(1,2,0)
    if native.ndim == 3 and native.shape[-1] == 4: native = native[:, :, :3]
    if expected.ndim == 2 and native.ndim == 3: native = native[:, :, 0]
    mae = float(np.abs(native-expected).mean())
    assert np.isfinite(native).all() and mae < 4.0, (name,mae)
    report['models'].append({'name':name,'source':source,'license':license_name,
        'checkpointSHA256':hashlib.sha256(checkpoint.read_bytes()).hexdigest(),
        'inputSize':512,'coreMLPredictionMAE_0_255':mae,'conversionValidation':'passed'})

aging_sha='f452c3afe63ccc65ac86b52f2338f8173f023925'
aging=checkout('HasnainRaz/Fast-AgingGAN',aging_sha,'aging')
spec=importlib.util.spec_from_file_location('fast_age_models',aging/'models.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
base=module.Generator(ngf=32,n_residual_blocks=9)
checkpoint=aging/'pretrained_model/state_dict.pth'
blob=checkpoint.read_bytes()
assert hashlib.sha1(b'blob '+str(len(blob)).encode()+b'\0'+blob).hexdigest()=='ab373fbf57d61a230b169a1f6705b2dac2bdf769'
base.load_state_dict(torch.load(checkpoint,map_location='cpu',weights_only=True))
class Aging(torch.nn.Module):
    def __init__(self,m): super().__init__();self.m=m
    def forward(self,x): return (self.m(x)+1)*127.5
convert(Aging(base),'LoopAging','MIT','https://github.com/HasnainRaz/Fast-AgingGAN/tree/'+aging_sha,checkpoint,ct.colorlayout.RGB)
shutil.copy(aging/'LICENSE',NOTICES/'Fast-AgingGAN.txt')

modnet_sha='28165a451e4610c9d77cfdf925a94610bb2810fb'
modnet=checkout('ZHKKKe/MODNet',modnet_sha,'modnet')
sys.path.insert(0,str(modnet))
from src.models.modnet import MODNet
base=MODNet(backbone_pretrained=False)
import gdown
checkpoint=work/'modnet_webcam_portrait_matting.ckpt'
# Official video model URL documented in demo/video_matting/custom/README.md.
gdown.download(id='1Nf1ZxeJZJL8Qx9KadcYYyEmmlKhTADxX',output=str(checkpoint),quiet=False)
weights=torch.load(checkpoint,map_location='cpu',weights_only=True)
base.load_state_dict({k.removeprefix('module.'):v for k,v in weights.items()})
class Matte(torch.nn.Module):
    def __init__(self,m): super().__init__();self.m=m
    def forward(self,x): return self.m(x,True)[2]*255.0
convert(Matte(base),'LoopMatte','Apache-2.0','https://github.com/ZHKKKe/MODNet/tree/'+modnet_sha,checkpoint,ct.colorlayout.GRAYSCALE)
shutil.copy(modnet/'LICENSE',NOTICES/'MODNet.txt')

# Photograph-based, perspective-correct backdrops derived from CC0 HDRIs.
# Not website thumbnails or user-submitted example renders.
import cv2
assets=[('venice_sunset','Venice Sunset',0),('kiara_1_dawn','Savanna Dawn',90),
        ('forest_slope','Forest Light',0),('modern_buildings_2','City Courtyard',120),
        ('studio_small_03','Photo Studio',180),('moonless_golf','Moonlit Landscape',0)]
for aid,title,yaw in assets:
    meta=requests.get('https://api.polyhaven.com/files/'+aid,timeout=60).json()
    file=meta['hdri']['4k']['hdr']
    path=work/(aid+'.hdr'); digest=get(file['url'],path)
    hdr=cv2.imread(str(path),cv2.IMREAD_UNCHANGED)
    assert hdr is not None and hdr.shape[1]>=4096, aid
    hdr=hdr[:,:,::-1]
    h,w=1440,2560
    xx,yy=np.meshgrid((np.arange(w)+.5)/w*2-1,1-(np.arange(h)+.5)/h*2)
    xx*=np.tan(np.deg2rad(74)/2); yy*=np.tan(np.deg2rad(74)/2)*h/w
    zz=np.ones_like(xx)
    theta=np.arctan2(xx,zz)+np.deg2rad(yaw)
    phi=np.arctan2(yy,np.sqrt(xx*xx+zz*zz))
    u=((theta/(2*np.pi)+.5)%1*hdr.shape[1]).astype('float32')
    v=((.5-phi/np.pi)*hdr.shape[0]).astype('float32')
    rgb=cv2.remap(hdr,u,v,cv2.INTER_LINEAR,borderMode=cv2.BORDER_WRAP)
    lum=np.maximum(1e-5,.2126*rgb[:,:,0]+.7152*rgb[:,:,1]+.0722*rgb[:,:,2])
    rgb*=.22/np.exp(np.mean(np.log(lum)))
    rgb=np.clip((rgb*(2.51*rgb+.03))/(rgb*(2.43*rgb+.59)+.14),0,1)
    rgb=np.where(rgb<=.0031308,rgb*12.92,1.055*np.power(rgb,1/2.4)-.055)
    filename='ph_'+aid+'.jpg'
    Image.fromarray(np.uint8(np.clip(rgb,0,1)*255)).save(PHOTOS/filename,quality=95,subsampling=0)
    report['backgrounds'].append({'id':'ph_'+aid,'name':title,'license':'CC0-1.0',
        'author':'Poly Haven contributors','source':'https://polyhaven.com/a/'+aid,
        'download':file['url'],'sourceSHA256':digest,'outputSize':[w,h],
        'outputSHA256':hashlib.sha256((PHOTOS/filename).read_bytes()).hexdigest()})
    print('Prepared photographic background:',title,flush=True)
NOTICES.joinpath('Poly-Haven.txt').write_text('Powered by Poly Haven\nCC0 environments from https://polyhaven.com/\nLicense: https://polyhaven.com/license\nAll six photographs were derived from the original CC0 HDRI assets, not website previews. Asset URLs and checksums are in RealismAssets.json.\n')
OUT.joinpath('RealismAssets.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
