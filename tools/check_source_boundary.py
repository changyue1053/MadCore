#!/usr/bin/env python3
"""Static extraction checks only: this is NOT a Kotlin compiler or platform test."""
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / 'SOURCE-PROVENANCE.json').read_text())
errors = []
for entry in manifest['files']:
    data = (ROOT / entry['destination']).read_bytes()
    digest = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
    if digest != entry['git_blob']:
        errors.append('source changed: ' + entry['destination'])
allowed = ('kotlin.', 'com.mad.core.extension.', 'com.mad.core.time.', 'com.mad.core.json.', 'com.mad.core.testkit.', 'com.mad.core.logging.', 'com.mad.core.config.', 'com.mad.core.net.', 'com.mad.core.storage.', 'com.mad.core.lifecycle.')
for path in list(ROOT.glob('core-*/src/**/*.kt')) + list(ROOT.glob('madcore/src/**/*.kt')):
    for dependency in re.findall(r'^import\s+([^\s;]+)', path.read_text(), re.M):
        platform_allowed = ()
        if ('madcore/src/ohosArm64Main/' in str(path.relative_to(ROOT)) or
                'core-net/src/ohosCopiedHttp/' in str(path.relative_to(ROOT))):
            platform_allowed = ('kotlinx.cinterop.',)
        if 'core-storage/src/androidMain/' in str(path.relative_to(ROOT)):
            platform_allowed = ('android.content.',)
        if 'core-storage/src/iosMain/' in str(path.relative_to(ROOT)) or 'core-storage/src/iosTest/' in str(path.relative_to(ROOT)):
            platform_allowed = ('platform.Foundation.',)
        if 'core-net/src/jvmAndAndroidMain/' in str(path.relative_to(ROOT)):
            platform_allowed = ('java.io.', 'java.net.')
        if 'core-net/src/jvmTest/' in str(path.relative_to(ROOT)):
            platform_allowed = ('java.net.', 'java.util.concurrent.', 'com.sun.net.httpserver.')
        if 'core-net/src/iosMain/' in str(path.relative_to(ROOT)) or 'core-net/src/iosTest/' in str(path.relative_to(ROOT)):
            platform_allowed = ('platform.Foundation.', 'platform.darwin.', 'kotlinx.cinterop.')
        if not dependency.startswith(allowed + platform_allowed):
            errors.append(f'unexpected import: {path.relative_to(ROOT)}: {dependency}')
for path in list(ROOT.glob('*.gradle')) + list(ROOT.glob('*/build.gradle')):
    if not path.is_file():
        continue  # Gradle creates a .gradle directory after local builds.
    if re.search(r'includeBuild\s*\(|projectDir\s*=|mad-repo|capability-|imcore|compose', path.read_text()):
        errors.append('unexpected repository/framework coupling: ' + str(path.relative_to(ROOT)))
print(f'Static source boundary: {len(manifest["files"])} pinned files, {len(errors)} errors')
for error in errors:
    print(error)
sys.exit(bool(errors))
