#!/usr/bin/env python3
"""Apply the reviewed interaction patch once, then build normal editable sources."""
import base64, gzip, hashlib, os, re, subprocess, tempfile
from pathlib import Path
ROOT=Path.cwd(); HERE=ROOT/'.github/rift-stability'
DIGEST='b5cf95fad34c99cb0227664c1255ce58abe02f5508674fc23a6097bf16872544'
def run(*args): return subprocess.check_output(list(map(str,args)),text=True).strip()
marker=HERE/'interaction-applied'
if marker.exists():
    assert marker.read_text().strip()==DIGEST, 'Unexpected interaction marker'
else:
    compressed=base64.b64decode(''.join((HERE/f'interaction{i}.b64').read_text().strip() for i in range(5)),validate=True)
    assert hashlib.sha256(compressed).hexdigest()==DIGEST, 'Patch transport was corrupted'
    patch=gzip.decompress(compressed)
    assert len(patch)==72735, 'Unexpected patch byte length'
    with tempfile.NamedTemporaryFile(suffix='.diff') as f:
        f.write(patch); f.flush()
        summary=run('git','apply','--numstat',f.name)
        assert summary and all(line.split('\t')[-1].startswith('Rift/') for line in summary.splitlines())
        run('git','apply','--check',f.name)
        run('git','apply',f.name)
    marker.write_text(DIGEST+'\n')
run('python3','Rift/scripts/resolve_catalog.py')
build=str(110+int(os.environ['GITHUB_RUN_NUMBER']))
project=ROOT/'Rift/project.yml'; text=project.read_text()
text=re.sub(r"CURRENT_PROJECT_VERSION: '[^']+'",f"CURRENT_PROJECT_VERSION: '{build}'",text)
text=re.sub(r"CFBundleVersion: '[^']+'",f"CFBundleVersion: '{build}'",text)
project.write_text(text)
run('python3','-m','compileall','-q','Rift/scripts')
run('git','config','user.name','github-actions[bot]')
run('git','config','user.email','41898282+github-actions[bot]@users.noreply.github.com')
run('git','add','Rift','.github/rift-stability/interaction-applied')
if subprocess.run(['git','diff','--cached','--quiet']).returncode:
    run('git','commit','-m',f'Apply Rift 1.2 animation, keyboard and private-by-default fixes ({build}) [skip ci]')
    run('git','push','origin','HEAD:main')
source=run('git','rev-parse','HEAD')
with open(os.environ['GITHUB_OUTPUT'],'a') as f: f.write(f'source={source}\nbuild={build}\n')
print('Exact source',source,'build',build,flush=True)
