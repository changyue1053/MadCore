#!/usr/bin/env bash
# Owner authorized CLI 5.1.0.840 / SDK / Hvigor use for this build on 2026-11-18.
# This is not a grant of distribution rights; no tools or SDK files are published.
set -euo pipefail
umask 077
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${RUNNER_TEMP:-/tmp}/madcore-har.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
archive="$work/cli.zip"
curl --fail --silent --show-error --proto '=https' --connect-timeout 30 --max-time 900 \
  --max-filesize 3221225472 --output "$archive" \
  https://repo.huaweicloud.com/harmonyos/ohpm/5.1.0/commandline-tools-linux-x64-5.1.0.840.zip
printf '%s  %s\n' 1dcefa4741dc289277560b2802040e0c45b433898d8db453d711d5376e0478f1 "$archive" | sha256sum -c -
unzip -q "$archive" -d "$work/tools"
rm "$archive"
cli="$work/tools/command-line-tools"
# Isolate package-manager user configuration/cache; no user tokens or shared executable cache.
export HOME="$work/home"
mkdir -p "$HOME"
export NPM_CONFIG_USERCONFIG="$work/empty.npmrc"
: > "$NPM_CONFIG_USERCONFIG"
test -d "$cli/sdk/default"
export DEVECO_SDK_HOME="$cli/sdk"
nodebin=$(find "$cli" -path '*/bin/node' -type f -print -quit)
if [[ -n "$nodebin" ]]; then
  export NODE_HOME=$(dirname "$(dirname "$nodebin")")
  export PATH="$NODE_HOME/bin:$PATH"
fi
export PATH="$cli/hvigor/bin:$cli/ohpm/bin:$PATH"
test -x "$cli/hvigor/bin/hvigorw"
test -x "$cli/ohpm/bin/ohpm"
node --version
npm --version
hvigorw --version
project="$work/sdk-project"
mkdir -p "$project"
cp -R "$root/harmony/." "$project/"
mkdir -p "$project/madcore/libs/arm64-v8a"
cp "$root/madcore/build/bin/ohosArm64/releaseShared/"libmadcore{,_napi}.so "$project/madcore/libs/arm64-v8a/"
(cd "$project" && ohpm install --all && hvigorw assembleHar --mode module -p module=madcore@default -p product=default -p buildMode=release --no-daemon)
har=$(find "$project/madcore/build" -name '*.har' -type f -print -quit)
test -n "$har"
python3 - "$har" <<'PY'
import sys,tarfile,zipfile,json,posixpath
p=sys.argv[1]
if zipfile.is_zipfile(p):
    with zipfile.ZipFile(p) as a: data={n:a.read(n) for n in a.namelist() if not n.endswith('/')}
else:
    with tarfile.open(p) as a: data={m.name:a.extractfile(m).read() for m in a.getmembers() if m.isfile()}
names=list(data)
print('HAR inventory:', names)
for expected in ('libmadcore.so','libmadcore_napi.so'):
    assert any(n.endswith('/'+expected) or n==expected for n in names), expected+' missing from HAR'
manifests=[n for n in names if n.endswith('oh-package.json5') and 'src/main/cpp/' not in n]
assert manifests, 'HAR package manifest missing'
# The compiler may transform Index.ets to a declaration/compiled entry. Check the manifest,
# not a guessed source filename; the external consumer below verifies actual consumption.
manifest=min(manifests,key=lambda n:n.count('/'))
meta=json.loads(data[manifest]);print('HAR package metadata:',meta)
bytecode=meta.get('metadata',{}).get('byteCodeHar') is True
entry=meta.get('types') if bytecode else meta.get('main')
assert isinstance(entry,str) and entry, 'HAR declaration/main entry absent'
if bytecode:
    abc=posixpath.join(posixpath.dirname(manifest),'ets/modules.abc')
    assert data.get(abc), 'Bytecode HAR implementation is missing'
resolved=posixpath.normpath(posixpath.join(posixpath.dirname(manifest),entry))
assert resolved in data, 'HAR declared main entry missing: '+resolved
print('HAR manifest entry and both independent native libraries verified')
PY
# Consume only the built HAR in a second project outside the repository/source tree.
consumer="$work/consumer"
mkdir -p "$consumer/consumer/libs"
cp -R "$project/AppScope" "$project/hvigor" "$consumer/"
cp "$project/hvigorfile.ts" "$project/oh-package.json5" "$consumer/"
cp "$har" "$consumer/consumer/libs/madcore.har"
mkdir -p "$consumer/consumer/src/main"
cp "$project/madcore/hvigorfile.ts" "$project/madcore/build-profile.json5" "$consumer/consumer/"
python3 - "$project" "$consumer" <<'PY'
import sys,pathlib,json
p,c=map(pathlib.Path,sys.argv[1:])
b=json.loads((p/'build-profile.json5').read_text());b['modules'][0]['name']='consumer';b['modules'][0]['srcPath']='./consumer';(c/'build-profile.json5').write_text(json.dumps(b))
(c/'consumer/src/main/module.json5').write_text(json.dumps({'module':{'name':'consumer','type':'har','deviceTypes':['phone']}}))
(c/'consumer/oh-package.json5').write_text(json.dumps({'name':'madcore-consumer','version':'0.1.0','main':'Index.ets','dependencies':{'madcore':'file:./libs/madcore.har'}}))
(c/'consumer/Index.ets').write_text("import { MadCore, PreferencesStringStore, NamespacedStringStore, RcpHttpClient, RcpRequest, ResourceScope, CloseableResource } from 'madcore';\nimport { preferences } from '@kit.ArkData';\nexport function checkCoreAbi(): boolean { return MadCore.abiVersion() === 1 && MadCore.isJsonObject('{}'); }\nexport async function consumeStorage(backend: preferences.Preferences): Promise<void> { const storage = new PreferencesStringStore(backend); const store = new NamespacedStringStore(storage, 'consumer'); store.put('test', 'value'); const value: string | null = store.get('test'); store.remove('test'); await storage.flush(); }\nexport async function consumeHttp(url: string): Promise<number> { const client = new RcpHttpClient(); const result = await client.execute(new RcpRequest(url)); return result.status; }\nclass OwnedResource implements CloseableResource { calls: number = 0; close(): void { this.calls++; } }\nexport function consumeLifecycle(): boolean { const owned = new OwnedResource(); const scope = new ResourceScope(); scope.register(owned); const report = scope.close(); return report.attempted === 1 && report.failed === 0 && owned.calls === 1; }\n")
PY
(cd "$consumer" && ohpm install --all && hvigorw assembleHar --mode module -p module=consumer@default -p product=default -p buildMode=release --no-daemon)
find "$consumer/consumer/build" -name '*.har' -type f | grep .
# Also assemble an independent unsigned application, still using only the HAR.
app="$work/app-consumer"
cp -R "$root/examples/harmony-consumer" "$app"
mkdir -p "$app/libs"
cp "$har" "$app/libs/madcore.har"
# Test app supplies its SDK C++ runtime. This is ephemeral validation, not a published package.
cxx=$(find "$cli/sdk/default/openharmony/native" -path '*/aarch64-linux-ohos/*' -name libc++_shared.so -type f -print -quit)
test -n "$cxx"
mkdir -p "$app/entry/libs/arm64-v8a"
cp "$cxx" "$app/entry/libs/arm64-v8a/"
(cd "$app" && ohpm install --all && hvigorw assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon)
find "$app/entry/build" -name '*.hap' -type f | grep .
mkdir -p "$root/build/harmony"
cp "$har" "$root/build/harmony/madcore.har"
echo 'HAR build, separate HAR consumer and unsigned app assembly passed; no Harmony device execution or redistribution clearance'

# Fail rather than silently restoring the vulnerable wrapper-managed pnpm dependency.
if [[ -d "$HOME/.hvigor" ]] && find "$HOME/.hvigor" -path '*/node_modules/pnpm/package.json' -print -quit | grep -q .; then
  echo 'Unexpected pnpm installed despite explicit useNpm configuration' >&2
  exit 1
fi
echo 'Hvigor npm mode compatibility passed with isolated HOME and no wrapper pnpm installed'
