#!/usr/bin/env python3
"""Patch isolated SDK/consumer copies for opt-in verification, never default source."""
import json
import shutil
import sys
from pathlib import Path
root = Path(__file__).resolve().parents[1]
mode, path = sys.argv[1], Path(sys.argv[2]).resolve()
if path == root / 'harmony' or path == root / 'examples/harmony-consumer':
    raise SystemExit('Use an isolated copy, not repository source')
experimental = root / 'harmony/experimental/copied-http'
if mode == 'sdk':
    target = path / 'madcore/src/main/cpp/types/libmadcore_copied_bridge'
    target.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(experimental/'bridge.d.ts', target/'Index.d.ts')
    (target/'oh-package.json5').write_text(json.dumps({'name':'libmadcore_copied_bridge.so','version':'0.1.0','types':'./Index.d.ts'}))
    manifest = path/'madcore/oh-package.json5'
    data = json.loads(manifest.read_text())
    data.setdefault('dependencies', {})['libmadcore_copied_bridge.so'] = 'file:./src/main/cpp/types/libmadcore_copied_bridge'
    manifest.write_text(json.dumps(data))
    shutil.copyfile(experimental/'CopiedHttpDriver.ets', path/'madcore/CopiedHttpDriver.ets')
    shutil.copyfile(experimental/'CopiedEnvironment.ets', path/'madcore/CopiedEnvironment.ets')
    entry = path/'madcore/Index.ets'
    entry.write_text(entry.read_text()+"\nexport { CopiedHttpDriver, runCopiedHttpDeviceVerification } from './CopiedHttpDriver';\nexport { prepareCopiedEnvironment, verifyCopiedEnvironment, CopiedEnvironmentIds } from './CopiedEnvironment';\n")
elif mode == 'app':
    page = path/'entry/src/main/ets/pages/Index.ets'
    source = page.read_text()
    def replace(old, new):
        global source
        if source.count(old) != 1: raise SystemExit('Consumer template changed: ' + old)
        source = source.replace(old,new)
    source = "import { runCopiedHttpDeviceVerification, verifyCopiedEnvironment } from 'madcore';\n" + source
    replace("if (kind === 'network')", "if (kind === 'environment') await verifyCopiedEnvironment('entry/ets/workers/CopiedEnvironmentWorker.ets');\n      else if (kind === 'bridge') await runCopiedHttpDeviceVerification(this.httpOrigin, this.tlsOrigin);\n      else if (kind === 'network')")
    replace("(kind === 'network' ? 'NETWORK_DEVICE_PASS' : 'STORAGE_RESTART_DEVICE_PASS')", "(kind === 'environment' ? 'COPIED_ENVIRONMENT_DETACH_PASS' : (kind === 'bridge' ? 'COPIED_RCP_KOTLIN_PASS' : (kind === 'network' ? 'NETWORK_DEVICE_PASS' : 'STORAGE_RESTART_DEVICE_PASS')))")
    replace("Button('Run controlled network tests')", "Button('Run network-free environment cleanup').enabled(!this.busy).onClick(() => this.deviceCheck('environment'))\n      Button('Run experimental Kotlin RCP bridge').enabled(!this.busy).onClick(() => this.deviceCheck('bridge'))\n      Button('Run controlled network tests')")
    page.write_text(source)
    worker = path/'entry/src/main/ets/workers/CopiedEnvironmentWorker.ets'
    worker.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(experimental/'CopiedEnvironmentWorker.ets', worker)
    profile = path/'entry/build-profile.json5'
    data = json.loads(profile.read_text())
    data.setdefault('buildOption', {}).setdefault('sourceOption', {})['workers'] = ['./src/main/ets/workers/CopiedEnvironmentWorker.ets']
    profile.write_text(json.dumps(data))
else: raise SystemExit('Expected sdk or app')
