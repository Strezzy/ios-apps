#!/usr/bin/env python3
"""Apply reviewed, idempotent first-build corrections and integrate native reply reveal."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def edit(relative, replacements):
    path=ROOT/relative; text=path.read_text()
    for old,new in replacements:
        if new in text: continue
        if old not in text: raise RuntimeError('Expected source not found: '+relative+' '+old[:60])
        text=text.replace(old,new,1)
    path.write_text(text)
edit('scripts/prepare.py', [('source_corrections(); catalog(); source(); icon()', 'catalog(); source(); icon()')])
edit('Rift/AppModel.swift', [
 ('    let storage: LocalStorage?', '    private(set) var storage: LocalStorage?'),
 ('let store=try LocalStorage(root:storageOverride); storage=store', 'let store=try LocalStorage(root:storageOverride)\n            storage=store'),
 ('if (error as NSError).code == NSURLErrorCannotResume {', 'if resume != nil && (error as NSError).domain == NSURLErrorDomain && (error as NSError).code != NSURLErrorCancelled {'),
 ('        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in', '        engine.resetCancellation()\n        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in'),
 ('@AppStorage("rift.thinking") var thinking=false', '@AppStorage("rift.thinking") var thinking=false\n    @AppStorage("rift.animateReplies") var animateReplies=true'),
])
edit('Rift/Native/RiftEngine.h', [('- (void)cancel;', '- (void)cancel;\n- (void)resetCancellation;')])
edit('Rift/Native/RiftEngine.mm', [
 ('- (void)cancel {', '- (void)resetCancellation { _cancelled.store(false); }\n- (void)cancel {'),
 ('    _cancelled.store(false);\n    llama_sampler *sampler=nullptr;', '    // Cancellation is reset before enqueueing, never after a queued stop.\n    llama_sampler *sampler=nullptr;'),
])
edit('Rift/Models.swift', [
 ('var system = utsname(); uname(&system)', 'var system = utsname(); uname(&system)\n        let length=MemoryLayout.size(ofValue:system.machine)'),
 ('capacity: MemoryLayout.size(ofValue: system.machine)', 'capacity: length'),
])
edit('Rift/ChatView.swift', [
 ('import SwiftUI', 'import SwiftUI\nimport UIKit'),
 ('MarkdownMessage(text:parts.answer)', 'MarkdownMessage(text:parts.answer, live:isStreaming)'),
 ('struct MarkdownMessage: View {\n    let text: String', 'struct MarkdownMessage: View {\n    let text: String\n    var live = false'),
 ('Text(.init(chunk)).textSelection(.enabled)', 'BloomText(text:chunk, live:live)'),
 ('Text(chunk.components(separatedBy:"\\n").dropFirst().joined(separator:"\\n")).font', 'BloomText(text:chunk.components(separatedBy:"\\n").dropFirst().joined(separator:"\\n"), live:live, markdown:false).font'),
])
edit('Rift/SettingsView.swift', [
 ('                    Section("Conversation") {', '                    Section("Appearance") {\n                        Toggle("Animated replies",isOn:$model.animateReplies)\n                        ReplyAnimationPreview()\n                        Text("Respects Reduce Motion, VoiceOver, and Low Power Mode.").font(.caption).foregroundStyle(.secondary)\n                    }\n                    Section("Conversation") {'),
])
# Compile before waiting for the simulator to finish its first-boot migration.
edit('scripts/build.py', [
 ("if device['state']!='Booted': run(['xcrun','simctl','boot',uid],'simulator-boot')\n    run(['xcrun','simctl','bootstatus',uid,'-b'],'simulator-ready')", "if device['state']!='Booted': run(['xcrun','simctl','boot',uid],'simulator-boot')\n    # Build while the simulator completes its initial migration."),
 ("run(common+['build-for-testing'],'simulator-build')", "run(common+['build-for-testing'],'simulator-build')\n    run(['xcrun','simctl','bootstatus',uid,'-b'],'simulator-ready')"),
])
print('Rift source corrections and native reveal integration applied.')
