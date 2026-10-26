from pathlib import Path

p = Path('Loop/Core/ProceduralEffects.swift')
s = p.read_text()
old = '(i % 2 == 0 ? .systemOrange : .systemPink).withAlphaComponent(0.26)'
assert s.count(old) == 1
p.write_text(s.replace(old, '(i % 2 == 0 ? UIColor.systemOrange : UIColor.systemPink).withAlphaComponent(0.26)'))

p = Path('Loop/Core/VideoFileExporter.swift')
s = p.read_text()
old = 'CMTimeRangeGetIntersection(trim, sourceRange)'
assert s.count(old) == 1
p.write_text(s.replace(old, 'CMTimeRangeGetIntersection(trim, otherRange: sourceRange)'))
