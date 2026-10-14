#!/usr/bin/env python3
"""Publish the explicitly labeled beta without replacing unrelated app releases."""
import json
import os
from pathlib import Path
import shutil
import subprocess
from datetime import datetime, timezone
ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
TAG = os.environ['RELEASE_TAG']
def run(args, cwd=REPO, check=True):
    return subprocess.run([str(x) for x in args], cwd=cwd, check=check)
def main():
    report = json.loads((ROOT / 'Build/BUILD-REPORT.json').read_text())
    assert report['status'] == 'passed'
    assert report['native_tests']['status'] == 'passed'
    assert report['release_channel'] == 'beta'
    assert report['native_tests']['skipped_count'] == 2
    work = ROOT / 'Build/CatalogWorktree'
    for attempt in range(4):
        run(['git', 'fetch', 'origin', 'main'])
        if work.exists(): run(['git', 'worktree', 'remove', '--force', work])
        run(['git', 'worktree', 'add', '--detach', work, 'origin/main'])
        registry_path = work / 'app-registry.json'
        registry = json.loads(registry_path.read_text())
        registry['com.billy.lumalift'] = json.loads((ROOT / 'catalog-entry.json').read_text())
        registry_path.write_text(json.dumps(registry, indent=2, ensure_ascii=False) + '\n')
        (work / 'assets').mkdir(exist_ok=True)
        shutil.copyfile(ROOT / 'Build/LumaLift-Icon.png', work / 'assets/LumaLift.png')
        before = json.loads((work / 'apps.json').read_text())
        notes = ('First beta: native pink-purple Liquid Glass, bundled Real-ESRGAN detail restoration, original-size/2x/4x output, previews, audio preservation and a local library. '
                 'RIFE 30/60 FPS interpolation is implemented in the device build but NOT device-validated: its two GPU tests cannot run on the hosted simulator and are explicitly skipped. '
                 'The other 11 simulator tests pass. SDR only; 4K output cap and 1080p input cap for AI motion. Try a short preview. Physical iPhone speed, heat and long-export reliability remain unverified.')
        run(['python3', 'scripts/update_catalog.py', '--tag', TAG, '--local', ROOT / 'Build/LumaLift.ipa',
             '--date', datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'), '--notes', notes], cwd=work)
        after = json.loads((work / 'apps.json').read_text())
        old_versions = {a['bundleIdentifier']: a.get('versions') for a in before['apps'] if a['bundleIdentifier'] != 'com.billy.lumalift'}
        new_versions = {a['bundleIdentifier']: a.get('versions') for a in after['apps'] if a['bundleIdentifier'] != 'com.billy.lumalift'}
        assert old_versions == new_versions, 'An unrelated app release changed.'
        # Publish the actual build report alongside the app source for clear evidence.
        shutil.copyfile(ROOT / 'Build/BUILD-REPORT.json', work / 'assets/LumaLift-Build-Report.json')
        run(['git', 'config', 'user.name', 'github-actions[bot]'], cwd=work)
        run(['git', 'config', 'user.email', '41898282+github-actions[bot]@users.noreply.github.com'], cwd=work)
        run(['git', 'add', 'app-registry.json', 'apps.json', 'README.md', 'assets/LumaLift.png', 'assets/LumaLift-Build-Report.json'], cwd=work)
        changed = subprocess.run(['git', 'diff', '--cached', '--quiet'], cwd=work)
        if changed.returncode == 0:
            run(['git', 'worktree', 'remove', '--force', work]); return
        run(['git', 'commit', '-m', 'Publish LumaLift beta ' + report['version'] + ' (' + report['build'] + ') with test evidence'], cwd=work)
        pushed = run(['git', 'push', 'origin', 'HEAD:main'], cwd=work, check=False)
        if pushed.returncode == 0:
            run(['git', 'worktree', 'remove', '--force', work]); return
    raise RuntimeError('Catalog changed concurrently four times; release is published, catalog update needs retry.')
if __name__ == '__main__': main()
