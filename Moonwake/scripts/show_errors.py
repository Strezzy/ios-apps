from pathlib import Path
import sys
lines=Path(sys.argv[1]).read_text(errors='replace').splitlines()
for i,line in enumerate(lines):
    if ': error:' in line or 'failed' in line.lower() or 'fatal error' in line.lower():
        print('\n'.join(lines[max(0,i-1):i+6]))
print('\n'.join(lines[-25:]))
