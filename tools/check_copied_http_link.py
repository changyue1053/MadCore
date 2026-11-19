#!/usr/bin/env python3
"""Check the opt-in component has one definition in the existing Core ELF, no new .so.
This proves symbols/link layout only, never runtime, RCP delivery or platform drain.
"""
import os
import subprocess
import sys

symbols = ['mc_http_open', 'mc_http_close', 'mc_http_begin', 'mc_http_next_request',
           'mc_http_state', 'mc_http_complete', 'mc_http_fail', 'mc_http_cancel',
           'mc_http_poll', 'madcore_copied_http_link_probe']
reader = os.environ.get('READELF', 'readelf')
text = subprocess.check_output([reader, '--dyn-syms', '--wide', sys.argv[1]], text=True)
for symbol in symbols:
    rows = [line.split() for line in text.splitlines() if len(line.split()) >= 8
            and line.split()[7].split('@')[0] == symbol]
    if len(rows) != 1 or rows[0][6] == 'UND':
        raise SystemExit('Expected one defined experimental symbol: ' + symbol)
dynamic = subprocess.check_output([reader, '-d', sys.argv[1]], text=True)
if 'libmadcore_napi' in dynamic or 'libmadcore_copied' in dynamic:
    raise SystemExit('Unexpected cyclic or second-registry shared-library dependency')
print('One Core ELF defines the experimental copied mailbox ABI; runtime/RCP not established')
