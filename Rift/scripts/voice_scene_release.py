"""Restrict the requested no-test build to the reviewed chat visibility fix."""
import hashlib
import subprocess
from pathlib import Path

BASELINE = '3c9126e917ca2bbb95f8f2721194cbddbe696463'
APPROVED = {'Rift/Rift/ChatView.swift': '8402b91dc7ac9fcf0616f1c311424fecda29967aa410fb844a36d27969cc3a40', 'Rift/Rift/VoiceParticles.swift': '5e34ee521874fa657cb66094fb83d3942182849219bd6df5511098747b0cb8e8'}

def verify_source(root, source):
    root = Path(root)
    def git(*args): return subprocess.check_output(['git', *args], cwd=root)
    changed = set(git('diff', '--name-only', BASELINE, source, '--',
                      'Rift/Rift', 'Rift/RiftTests', 'Rift/RiftUITests').decode().splitlines())
    assert changed == set(APPROVED), 'Only the reviewed chat visibility fix are permitted'
    for path, digest in APPROVED.items():
        assert hashlib.sha256(git('show', source + ':' + path)).hexdigest() == digest
        assert hashlib.sha256((root / path).read_bytes()).hexdigest() == digest
    old = git('show', BASELINE + ':Rift/project.yml').decode()
    new = git('show', source + ':Rift/project.yml').decode()
    assert new.replace("'1.9.6'", "'1.9.5'").replace("'141'", "'140'") == old
