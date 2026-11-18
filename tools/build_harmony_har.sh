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
import sys,tarfile,zipfile
p=sys.argv[1]
if zipfile.is_zipfile(p):
    with zipfile.ZipFile(p) as a: names=a.namelist()
else:
    with tarfile.open(p) as a: names=a.getnames()
for expected in ('libmadcore.so','libmadcore_napi.so','Index.ets'):
    assert any(n.endswith('/'+expected) or n==expected for n in names), expected+' missing from HAR'
print('HAR contains ArkTS entry and both independent native libraries')
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
(c/'consumer/Index.ets').write_text("import { MadCore } from 'madcore';\nexport function checkCoreAbi(): boolean { return MadCore.abiVersion() === 1 && MadCore.isJsonObject('{}'); }\n")
PY
(cd "$consumer" && ohpm install --all && hvigorw assembleHar --mode module -p module=consumer@default -p product=default -p buildMode=release --no-daemon)
find "$consumer/consumer/build" -name '*.har' -type f | grep .
mkdir -p "$root/build/harmony"
cp "$har" "$root/build/harmony/madcore.har"
echo 'HAR build and separate HAR consumer compilation passed; no Harmony device execution or redistribution clearance'
