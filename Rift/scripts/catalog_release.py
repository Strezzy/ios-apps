"""Restrict the requested no-test release to the approved catalog addition."""
import json
import subprocess
from pathlib import Path

BASELINE = '30de27661984ebf79440e31dca2a75df6a0ab38e'
CATALOG_SOURCE = 'c3cdc795a71a948363613eeb1e62b033e6c0ca47'
CATALOG = 'Rift/Rift/Resources/catalog.json'

def verify_source(root, source):
    root = Path(root)
    def git(*args): return subprocess.check_output(['git', *args], cwd=root, text=True).strip()
    changed = set(git('diff', '--name-only', BASELINE, source, '--',
                      'Rift/Rift', 'Rift/RiftTests', 'Rift/RiftUITests').splitlines())
    assert changed == {CATALOG}, 'The no-test path permits only this catalog change'
    expected = git('show', CATALOG_SOURCE + ':' + CATALOG)
    assert git('show', source + ':' + CATALOG) == expected
    assert (root / CATALOG).read_text().strip() == expected
    old = git('show', BASELINE + ':Rift/project.yml')
    new = git('show', source + ':Rift/project.yml')
    assert new.replace("'1.9.3'", "'1.9.2'").replace("'138'", "'137'") == old, 'Only release numbers may change'
    prior = json.loads((root / 'Rift/Verification/1.9.2-build137/BUILD-REPORT.json').read_text())
    assert prior['source'] == BASELINE and prior['build_result'] == 'passed'
