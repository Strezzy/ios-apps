#!/usr/bin/env python3
"""Validate and pin the editable release source; never reapply historical patches."""
import ast
import os
import re
import subprocess
from pathlib import Path

root = Path.cwd()
project = (root / 'Rift/project.yml').read_text()
build = re.search(r"CURRENT_PROJECT_VERSION: '([0-9]+)'", project).group(1)
assert re.search(r"CFBundleVersion: '" + build + r"'", project), 'Build numbers differ'
assert re.search(r"MARKETING_VERSION: '1.8'", project), 'Unexpected release version'
for path in (root / 'Rift/scripts').glob('*.py'):
    ast.parse(path.read_text(), filename=str(path))
source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
assert not subprocess.check_output(['git', 'status', '--porcelain'], text=True), 'Source must be clean'
with open(os.environ['GITHUB_OUTPUT'], 'a') as handle:
    handle.write(f'source={source}\nbuild={build}\n')
print('Exact source', source, 'build', build, flush=True)
