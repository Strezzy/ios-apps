#!/usr/bin/env python3
"""Build-time downloads only. The shipped app never requests models or user data online."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import urllib.request
ROOT = Path(__file__).resolve().parents[1]
PIN = '1fef4869a44fca32848102b9f6a774a20eb50db6'
WEIGHTS = 'https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesr-general-x4v3.pth'
def download(url, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url, timeout=120) as response, path.open('wb') as output:
        shutil.copyfileobj(response, output)
    return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    import numpy as np
    import torch
    from torch import nn
    from torch.nn import functional as F
    import coremltools as ct
    from PIL import Image
    torch.set_num_threads(4)
    torch.manual_seed(41)
    vendor = ROOT / 'Vendor/rife-metal'
    if not (vendor / '.git').exists():
        vendor.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['git', 'clone', '--no-checkout', 'https://github.com/cinemore/rife-metal.git', str(vendor)], check=True)
    subprocess.run(['git', '-C', str(vendor), 'fetch', 'origin', PIN], check=True)
    subprocess.run(['git', '-C', str(vendor), 'checkout', '--detach', PIN], check=True)
    revision = subprocess.check_output(['git', '-C', str(vendor), 'rev-parse', 'HEAD'], text=True).strip()
    assert revision == PIN
    # Let Xcode compile Metal for the real build destination, rather than the
    # host-targeted upstream plugin. Inference mathematics and weights are unchanged.
    (vendor / 'Package.swift').write_text('''// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "RifeMetal", platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "RifeMetal", targets: ["RifeMetal", "RifeMetalCore"])],
    targets: [
        .target(name: "RifeMetal", dependencies: ["RifeMetalCore"],
                resources: [.copy("Resources/rife-v4.26.rmw")]),
        .target(name: "RifeMetalCore", resources: [.process("Shaders")])
    ])
''')
    resources = ROOT / 'Resources'
    resources.mkdir(exist_ok=True)
    license_file = ROOT / 'Vendor/Real-ESRGAN-LICENSE.txt'
    download('https://raw.githubusercontent.com/xinntao/Real-ESRGAN/v0.3.0/LICENSE', license_file)
    (resources / 'ThirdParty.txt').write_text(
        'Real-ESRGAN / SRVGGNetCompact / pretrained General x4v3 weights\n\n' + license_file.read_text()
        + '\n\nRifeMetal (pinned source; shader packaging adapted for iPhone)\n\n' + (vendor / 'LICENSE').read_text()
        + '\n\n' + (vendor / 'THIRD-PARTY.md').read_text())
    model_dir = ROOT / 'Models'
    model_dir.mkdir(exist_ok=True)
    weights_path = ROOT / 'Vendor/realesr-general-x4v3.pth'
    weights_hash = download(WEIGHTS, weights_path)
    # Published SRVGGNetCompact architecture (BSD 3-Clause). Strict loading
    # rejects missing or mismatched pretrained weights.
    class General(nn.Module):
        def __init__(self):
            super().__init__()
            layers = [nn.Conv2d(3, 64, 3, 1, 1), nn.PReLU(64)]
            for _ in range(32): layers += [nn.Conv2d(64, 64, 3, 1, 1), nn.PReLU(64)]
            layers += [nn.Conv2d(64, 48, 3, 1, 1)]
            self.body = nn.ModuleList(layers)
            self.upsampler = nn.PixelShuffle(4)
        def forward(self, x):
            result = x
            for layer in self.body: result = layer(result)
            return self.upsampler(result) + F.interpolate(x, scale_factor=4, mode='nearest')
    model = General().eval()
    checkpoint = torch.load(weights_path, map_location='cpu', weights_only=True)
    state = checkpoint.get('params_ema', checkpoint.get('params', checkpoint))
    model.load_state_dict(state, strict=True)
    class ImageOutput(nn.Module):
        def __init__(self, network):
            super().__init__()
            self.network = network
        def forward(self, image): return self.network(image).clamp(0, 1) * 255.0
    wrapped = ImageOutput(model).eval()
    with torch.no_grad(): traced = torch.jit.trace(wrapped, torch.rand(1, 3, 256, 256))
    converted = ct.convert(traced, convert_to='mlprogram', minimum_deployment_target=ct.target.iOS18,
        compute_precision=ct.precision.FLOAT16, compute_units=ct.ComputeUnit.CPU_ONLY,
        inputs=[ct.ImageType(name='image', shape=(1, 3, 256, 256), scale=1 / 255.0, color_layout=ct.colorlayout.RGB)],
        outputs=[ct.ImageType(name='enhanced', color_layout=ct.colorlayout.RGB)])
    converted.author = 'Xintao Wang et al.; iPhone packaging by Strezzy'
    converted.license = 'BSD-3-Clause'
    converted.short_description = 'Real-ESRGAN General x4v3, 256-pixel RGB tile input, 4x RGB output.'
    converted.user_defined_metadata['upstream_weights_sha256'] = weights_hash
    package = model_dir / 'LumaGeneral.mlpackage'
    if package.exists(): shutil.rmtree(package)
    converted.save(str(package))
    pixels = np.random.default_rng(37).integers(0, 256, (256, 256, 3), dtype=np.uint8)
    reference_input = torch.from_numpy(pixels.astype(np.float32).transpose(2, 0, 1)).unsqueeze(0) / 255.0
    with torch.no_grad(): reference = wrapped(reference_input)[0].permute(1, 2, 0).numpy()
    predicted_image = converted.predict({'image': Image.fromarray(pixels)})['enhanced']
    assert predicted_image.mode in ('RGB', 'RGBA'), predicted_image.mode
    # Core ML exposes an RGBA backing image for RGB model outputs on this SDK.
    # Compare only the three modeled channels, not the synthesized alpha channel.
    actual = np.asarray(predicted_image.convert('RGB')).astype(np.float32)
    assert actual.shape == (1024, 1024, 3), actual.shape
    mae = float(np.mean(np.abs(actual - reference)))
    assert mae < 2.0, f'Converted model does not match pretrained network: MAE={mae}'
    report = {
        'restoration': 'Real-ESRGAN General x4v3', 'weights_source': WEIGHTS,
        'weights_sha256': weights_hash, 'rife_revision': PIN,
        'rife_weights_sha256': hashlib.sha256((vendor / 'Sources/RifeMetal/Resources/rife-v4.26.rmw').read_bytes()).hexdigest(),
        'conversion_mae_8bit': mae, 'conversion_verified': True,
        'coremltools': ct.__version__, 'torch': torch.__version__,
        'tile_input': 256, 'tile_context_pixels': 40,
        'app_runtime_network_downloads': False,
        'model_package_sha256': {str(p.relative_to(package)): hashlib.sha256(p.read_bytes()).hexdigest() for p in package.rglob('*') if p.is_file()},
        'rife_patch': 'Replace host-targeted shader plugin with destination-aware SwiftPM process(Shaders); omit unused CLI.'
    }
    (resources / 'MODEL-PROVENANCE.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
if __name__ == '__main__': main()
