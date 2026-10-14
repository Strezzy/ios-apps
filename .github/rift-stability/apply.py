#!/usr/bin/env python3
"""Apply the reviewed voice/effects patch, then preserve editable source before testing."""
import ast, base64, gzip, hashlib, os, re, subprocess, tempfile
from pathlib import Path
ROOT = Path.cwd()
HERE = ROOT / '.github/rift-stability'
DIGEST = '480356edbe63143b7af8293ed434be4a8778fabdf6813b7911f672cff40a0063'
def run(*args):
    return subprocess.check_output(list(map(str, args)), text=True).strip()
marker = HERE / 'voice-applied'
if marker.exists():
    assert marker.read_text().strip() == DIGEST, 'Unexpected voice patch marker'
else:
    encoded = ''.join((HERE / f'voice{i}.b64').read_text().strip() for i in range(3))
    # Normalize two verified transport transcription errors, then require the
    # exact original compressed checksum and byte length before applying.
    encoded = encoded.replace('sQTSkWCWqdXY', 'sQTSkWCqdXY').replace('fX55c3F5eXZ', 'fX55c3F4eXZ')
    compressed = base64.b64decode(encoded, validate=True)
    assert hashlib.sha256(compressed).hexdigest() == DIGEST, 'Voice patch transport checksum mismatch'
    patch = gzip.decompress(compressed)
    assert len(patch) == 81363, 'Unexpected voice patch length'
    with tempfile.NamedTemporaryFile(suffix='.diff') as handle:
        handle.write(patch)
        handle.flush()
        summary = run('git', 'apply', '--numstat', handle.name)
        assert summary and all(line.split('\t')[-1].startswith('Rift/') for line in summary.splitlines())
        run('git', 'apply', '--check', handle.name)
        run('git', 'apply', handle.name)
    marker.write_text(DIGEST + '\n')
# Existing pinned model identities and inference runtime are unchanged.
build = str(110 + int(os.environ['GITHUB_RUN_NUMBER']))
project = ROOT / 'Rift/project.yml'
text = project.read_text()
text = re.sub(r"CURRENT_PROJECT_VERSION: '[^']+'", f"CURRENT_PROJECT_VERSION: '{build}'", text)
text = re.sub(r"CFBundleVersion: '[^']+'", f"CFBundleVersion: '{build}'", text)
project.write_text(text)
for path in (ROOT / 'Rift/scripts').glob('*.py'):
    ast.parse(path.read_text(), filename=str(path))
run('git', 'config', 'user.name', 'github-actions[bot]')
run('git', 'config', 'user.email', '41898282+github-actions[bot]@users.noreply.github.com')
run('git', 'add', 'Rift', '.github/rift-stability/voice-applied')
if subprocess.run(['git', 'diff', '--cached', '--quiet']).returncode:
    run('git', 'commit', '-m', f'Apply Rift 1.3 local voice, expressive text effects and full-height background ({build}) [skip ci]')
    run('git', 'push', 'origin', 'HEAD:main')
source = run('git', 'rev-parse', 'HEAD')
with open(os.environ['GITHUB_OUTPUT'], 'a') as handle:
    handle.write(f'source={source}\nbuild={build}\n')
print('Exact source', source, 'build', build, flush=True)
