"""Limit the requested no-test release to the reviewed performance patch."""
import hashlib
import subprocess
from pathlib import Path

BASELINE = '2cbacfea7bd33d49031278d00cf0eb96a6169ca2'
APPROVED = {'Rift/Rift/AppModel.swift': '76123e32e611a51153f09b247531e83de45f2e5469bd4a089c8cb6f56a408d8a', 'Rift/Rift/ChatView.swift': 'c13e8b64c01d60634b89ab0401783dd9c051634b1c707b4f8947e375b5039055', 'Rift/Rift/Storage.swift': '4e6de3e4c2ced4f1fafa5dec1faf5fff152633afbee6243fa9832fd3427b4411', 'Rift/Rift/StreamingText.swift': 'a4a60a5894f619ad48beb06efba98e031658930ed370ba54c6be627e0195274c'}

def verify_source(root, source):
    root = Path(root)
    def git(*args): return subprocess.check_output(['git', *args], cwd=root)
    changed = set(git('diff', '--name-only', BASELINE, source, '--',
                      'Rift/Rift', 'Rift/RiftTests', 'Rift/RiftUITests').decode().splitlines())
    assert changed == set(APPROVED), 'Only the reviewed performance patch is permitted'
    for path, digest in APPROVED.items():
        assert hashlib.sha256(git('show', source + ':' + path)).hexdigest() == digest
        assert hashlib.sha256((root / path).read_bytes()).hexdigest() == digest
    old = git('show', BASELINE + ':Rift/project.yml').decode()
    new = git('show', source + ':Rift/project.yml').decode()
    assert new.replace("'1.9.4'", "'1.9.3'").replace("'139'", "'138'") == old
