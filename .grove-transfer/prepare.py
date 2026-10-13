"""Apply the exact, hash-checked visual upgrade to the staging branch."""
from pathlib import Path
import hashlib, json
root=Path(__file__).resolve().parents[1]
changes={}
for file in sorted((root/'.grove-transfer').glob('*.json')):
    changes.update(json.loads(file.read_text()))
pending={}
for name, change in changes.items():
    assert name.startswith('EnterTheThirdDimension/') or name=='.github/workflows/third-dimension.yml', name
    file=root/name
    raw=file.read_bytes()
    assert hashlib.sha256(raw).hexdigest()==change['base'], 'Base changed: '+name
    text=raw.decode('utf-8')
    if 'text' in change:
        text=change['text']
    else:
        for start,end,replacement in reversed(change['edits']):
            assert 0<=start<=end<=len(text)
            text=text[:start]+replacement+text[end:]
    assert hashlib.sha256(text.encode()).hexdigest()==change['after'], 'Transfer differs: '+name
    pending[file]=text
for name,expected in {
 'Resources/Game/grove.js':'d6e766f540799c36d4fcf190b800d65d2deba5f2251b403193551125f25b8bd5',
 'Resources/Game/grove.css':'4c551cf730d430487939f1d79e411b79e53a2cb0747214fd35644d56369d9123',
 'Support/qa_browser.py':'a83b7ef51dc38111e15ecf55a930b00358b0845e1e802a40a6cf86b5e7035dfc'
}.items():
    assert hashlib.sha256((root/'EnterTheThirdDimension'/name).read_bytes()).hexdigest()==expected, 'New file differs: '+name
for file,text in pending.items():
    file.write_text(text)
print('Verified and applied',len(pending),'source files.')
