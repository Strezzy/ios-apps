from pathlib import Path
import sys
lines = Path(sys.argv[1]).read_text(errors='replace').splitlines()
for index, line in enumerate(lines):
    if any(token in line for token in (': error:', 'failed', 'Failure', 'Assertion')):
        print('\n'.join(value for value in lines[max(0, index - 2):index + 7] if len(value) < 1500))
print('\n'.join(line for line in lines[-50:] if len(line) < 1500))
