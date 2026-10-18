"""Restrict the requested no-test build to the reviewed voice refinements."""
import hashlib
import subprocess
from pathlib import Path

BASELINE = '597964a483e9625a11dab8ae9863161c706a3bcd'
APPROVED = {'Rift/Rift/ChatView.swift': '1baeb994b0cdc4990dfcbddda3a68518e24c9b02c9cae19af3de94b8d213f265', 'Rift/Rift/LiquidVoiceOrb.swift': '46ccefa7d84e56c52eb9ae9c5c4931e884b510d48fe57f30ed12389d6cf1fe6d', 'Rift/Rift/Theme.swift': '2d04572f21caf3d7f30d5c0ea469c221d4741ed9255d4e71e521c9519dfdfd25', 'Rift/Rift/VoiceConversationView.swift': '24d4a97bc2c576672a537643cfd36c268ada479efcc7d5b271e9431622596d13', 'Rift/Rift/VoiceParticles.swift': 'a95746efc3e8cbdfdd6f048bc223045558af31ece4f4b231da6c6bd988d6440d', 'Rift/Rift/VoiceParticles.metal': '172604913cfdd1f41331e8a2eff79456f468e5b0cdc55d84ead7389ba40c2dfb', 'Rift/Rift/VoiceReplyStream.swift': 'e61e3dd359ba316d97c9c1c354326271075c36c4ff2acc6017334fe6cbf11668', 'Rift/Rift/VoiceSupport.swift': 'c3aab388fb3017cc9fa6b21047c865790935ed5d0ea8551872f8a7514c42d408'}

def verify_source(root, source):
    root = Path(root)
    def git(*args): return subprocess.check_output(['git', *args], cwd=root)
    changed = set(git('diff', '--name-only', BASELINE, source, '--',
                      'Rift/Rift', 'Rift/RiftTests', 'Rift/RiftUITests').decode().splitlines())
    assert changed == set(APPROVED), 'Only the reviewed voice refinements are permitted'
    for path, digest in APPROVED.items():
        assert hashlib.sha256(git('show', source + ':' + path)).hexdigest() == digest
        assert hashlib.sha256((root / path).read_bytes()).hexdigest() == digest
    old = git('show', BASELINE + ':Rift/project.yml').decode()
    new = git('show', source + ':Rift/project.yml').decode()
    assert new.replace("'1.9.7'", "'1.9.6'").replace("'142'", "'141'") == old
