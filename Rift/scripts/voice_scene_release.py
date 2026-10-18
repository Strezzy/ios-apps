"""Restrict the requested no-test build to the reviewed voice scene changes."""
import hashlib
import subprocess
from pathlib import Path

BASELINE = 'a1124bdc8b6135b530d16e3afa7c885fbdf408ab'
APPROVED = {'Rift/Rift/ChatView.swift': 'c965aca1ab710831bb90b7576a6c554cd2a2cf3e0afb97ed295081ad4c09c472', 'Rift/Rift/Theme.swift': '3b8f3efee30842df547108f0aed1ffe62399185cac41155c735c12f4fad4ed54', 'Rift/Rift/VoiceConversationView.swift': 'f29fbe055463e5ceecc42ba0eb1385d8752361c0e70de7451f844c3cf0e5ee68', 'Rift/Rift/LiquidVoiceOrb.swift': 'b72409b5123eac3e5885bd0c5acdce5a6d0d9af9a25ca184196326a9bdf874bf', 'Rift/Rift/VoiceParticles.swift': 'de2e04493b08c51c7857a7324234aad61e6ea79cd4fcd1962efb0f602bf92069', 'Rift/Rift/VoiceParticles.metal': '710585d8e6769db8534e559d7a8ce0bf1dd5b648589500375b5f1d0cf80ba619'}

def verify_source(root, source):
    root = Path(root)
    def git(*args): return subprocess.check_output(['git', *args], cwd=root)
    changed = set(git('diff', '--name-only', BASELINE, source, '--',
                      'Rift/Rift', 'Rift/RiftTests', 'Rift/RiftUITests').decode().splitlines())
    assert changed == set(APPROVED), 'Only the reviewed voice scene changes are permitted'
    for path, digest in APPROVED.items():
        assert hashlib.sha256(git('show', source + ':' + path)).hexdigest() == digest
        assert hashlib.sha256((root / path).read_bytes()).hexdigest() == digest
    old = git('show', BASELINE + ':Rift/project.yml').decode()
    new = git('show', source + ':Rift/project.yml').decode()
    assert new.replace("'1.9.5'", "'1.9.4'").replace("'140'", "'139'") == old
