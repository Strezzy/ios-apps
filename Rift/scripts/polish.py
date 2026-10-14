#!/usr/bin/env python3
"""Migrate the initial source exactly once; repeated runs leave identical bytes."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def replace_once(path, old, new):
    text=path.read_text()
    if new in text: return
    if old not in text: raise RuntimeError('Unexpected source in '+str(path)+': '+old[:70])
    path.write_text(text.replace(old,new,1))
path=ROOT/'scripts/prepare.py'; text=path.read_text()
if 'def source_corrections():' in text:
    begin=text.index('def source_corrections():'); end=text.index("if __name__=='__main__':",begin)
    text=text[:begin]+text[end:]
text=text.replace('source_corrections(); catalog(); source(); icon()', 'catalog(); source(); icon()')
assert 'source_corrections' not in text
path.write_text(text)
for relative,line in [('Rift/Models.swift','        let length=MemoryLayout.size(ofValue:system.machine)'),('Rift/AppModel.swift','        engine.resetCancellation()')]:
    path=ROOT/relative; text=path.read_text()
    while line+'\n'+line in text: text=text.replace(line+'\n'+line,line)
    path.write_text(text); assert text.count(line)==1
path=ROOT/'Rift/AppModel.swift'; text=path.read_text()
text=text.replace('            activeChatID=conversations.sorted { $0.updatedAt > $1.updatedAt }.first?.id\n            storage=store','            activeChatID=conversations.sorted { $0.updatedAt > $1.updatedAt }.first?.id')
path.write_text(text)
replace_once(path,'status: @escaping @Sendable (String)->Void) async throws {','status: @escaping @Sendable (String)->Void) async throws -> String {')
replace_once(path,'CheckedContinuation<Void,Error>','CheckedContinuation<String,Error>')
replace_once(path,'        try await withCheckedThrowingContinuation {','        return try await withCheckedThrowingContinuation {')
replace_once(path,'                    _ = try self.engine.generate(atPath:url.path,messages:messages,context:Int32(context),maxTokens:Int32(maxTokens),temperature:temperature,thinking:thinking,cpu:cpu,token:text,status:status)','                    var finalText = ""\n                    _ = try self.engine.generate(atPath:url.path,messages:messages,context:Int32(context),maxTokens:Int32(maxTokens),temperature:temperature,thinking:thinking,cpu:cpu,token:{ value in finalText=value; text(value) },status:status)')
replace_once(path,'                    continuation.resume()','                    continuation.resume(returning:finalText)')
replace_once(path,'                try await inference.run(model:model,','                let finalText = try await inference.run(model:model,')
replace_once(path,'            } catch { if !stopping { self.error=error.localizedDescription } }','                if let c=conversations.firstIndex(where:{$0.id==chatID}), let m=conversations[c].messages.firstIndex(where:{$0.id==replyID}) { conversations[c].messages[m].content=finalText }\n            } catch { if !stopping { self.error=error.localizedDescription } }\n            generationID=nil')
path=ROOT/'Rift/BloomText.swift'; text=path.read_text().replace('accept(animated: live && canAnimate)','accept(animated: (live || active) && canAnimate)'); path.write_text(text)
assert (ROOT/'Rift/Models.swift').read_text().count('let length=MemoryLayout.size(ofValue:system.machine)')==1
assert 'NSURLErrorCannotResume' not in (ROOT/'Rift/AppModel.swift').read_text()
print('Rift preparation is repeat-safe; final reply delivery is ordered.')
