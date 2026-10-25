#!/usr/bin/env python3
"""Combine disjoint, honestly sourced unit and freshly executed UI evidence."""
import json
from pathlib import Path

BUILD = Path(__file__).resolve().parents[1] / 'Build'
units = json.loads((BUILD / 'UNIT-TEST-RESULTS.json').read_text())
ui = json.loads((BUILD / 'UI-TEST-RESULTS.json').read_text())
build = json.loads((BUILD / 'BUILD-REPORT.json').read_text())
assert (units['passedTests'], units['failedTests'], units['skippedTests']) == (6, 0, 1)
assert (ui['passedTests'], ui['failedTests'], ui.get('skippedTests', 0)) == (1, 0, 0)
assert '** TEST SUCCEEDED **' in (BUILD / 'test.log').read_text()
summary = {
    'reportKind': 'Combined unchanged-runtime unit evidence and freshly executed UI evidence; not a single xcresult summary',
    'passedTests': 7, 'failedTests': 0, 'skippedTests': 1, 'result': 'Passed',
    'unitResults': {'file': 'UNIT-TEST-RESULTS.json', 'sourceCommit': units['sourceCommit'],
                    'passedTests': 6, 'failedTests': 0, 'skippedTests': 1},
    'uiResults': {'file': 'UI-TEST-RESULTS.json', 'sourceCommit': build['sourceCommit'],
                  'passedTests': 1, 'failedTests': 0, 'skippedTests': 0},
    'note': 'The original UI test result is excluded from these totals. Screenshots come only from the fresh UI run.',
}
(BUILD / 'TEST-RESULTS.json').write_text(json.dumps(summary, indent=2) + '\n')
print('Combined 6 verified unit passes + 1 fresh UI pass; 1 original hardware skip. No test is counted twice.')
