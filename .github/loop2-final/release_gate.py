from pathlib import Path

p=Path('Loop/scripts/check_native_selection.py');s=p.read_text()
s=s.replace("'-parse-as-library',str", "'-parse-as-library','-target','arm64-apple-macosx15.0',str")
p.write_text(s)

p=Path('Loop/scripts/verify_release.py');s=p.read_text()
if "\nif '--binary' not in sys.argv:" in s:
    s=s.split("\nif '--binary' not in sys.argv:")[0]
a=s.index('def verify_release():');b=s.index("if __name__=='__main__':",a)
s=s[:a]+'''def verify_release():
    r=verify_binary()
    t=json.loads((BUILD/'FOCUSED-CREATIVE-TESTS.json').read_text())
    ui=json.loads((BUILD/'FOCUSED-UI-TESTS.json').read_text())
    selection=json.loads((BUILD/'MAC-SELECTION-TESTS.json').read_text())
    for evidence in [t,ui,selection]:assert evidence['sourceCommit']==r['sourceCommit']
    expected=['testSubjectSelectionBoxSelectsWholeForeground','testSubjectSelectionSelectsTappedForeground','testNativeSelectionKeepsTappedPersonAndRejectsBackground','testNativeSelectionRejectsConflictingInstancePoints']
    assert t['passedTests']>=107 and t['failedTests']==0 and t.get('skippedTests',0)==4,t
    assert t['expectedSimulatorSkips']==expected
    assert ui['passedTests']>=1 and ui['failedTests']==0 and ui.get('skippedTests',0)==0,ui
    assert selection['passedTests']==6 and selection['failedTests']==0 and selection.get('skippedTests',0)==0,selection
    assert selection['upstreamSAMModelsUnmodified'] is True
    for name,digest in selection['sharedSourceSHA256'].items():
        assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,name
    report={'profile':'creative-platform-verified','version':r['version'],'build':r['build'],'sourceCommit':r['sourceCommit'],'ipaSHA256':r['sha256'],'nativeReleaseBuild':'passed','iOSSimulatorTests':{'passed':t['passedTests'],'failed':0,'skipped':4,'excludedSelectionTests':expected},'nativeMacSelectionTests':{'passed':6,'failed':0,'skipped':0},'focusedInterfaceTests':{'passed':ui['passedTests'],'failed':0,'skipped':0},'scope':t['scope'],'fullEditorUISuite':'not-run','physicalDeviceValidation':'not-run'}
    (BUILD/'VALIDATION-REPORT.json').write_text(json.dumps(report,indent=2)+'\\n')
    print(json.dumps(report,indent=2));return report
''' + s[b:]
p.write_text(s)
print('Release gate requires all three independent evidence reports and explicit simulator exclusions.')
