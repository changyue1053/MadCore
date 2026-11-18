#!/usr/bin/env bash
# Read-only SDK inspection. Never executes extracted tools or accepts licenses.
set -euo pipefail
umask 077
export LC_ALL=C
BASE='https://repo.huaweicloud.com/harmonyos/ohpm/5.0.3'
NAME='commandline-tools-linux-x64-5.0.3.906.zip'
WORK="$(mktemp -d "${RUNNER_TEMP:-/tmp}/harmony-inspect.XXXXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
export WORK NAME
# 6 GiB free required; do not perform full SDK extraction.
FREE_KIB=$(df -Pk "$WORK" | awk 'NR==2 {print $4}')
[[ "$FREE_KIB" =~ ^[0-9]+$ ]] && (( FREE_KIB >= 6291456 )) || { echo 'Insufficient disk'; exit 1; }
# No credentials, redirects, HTTP downgrade, retries, or insecure TLS.
curl --fail --silent --show-error --proto '=https' --connect-timeout 30 \
  --max-time 60 --max-filesize 4096 --output "$WORK/checksum" "$BASE/$NAME.sha256"
python3 - <<'PY'
import os,re,pathlib
p=pathlib.Path(os.environ['WORK'])
s=(p/'checksum').read_text('ascii').strip()
n=os.environ['NAME']
m=re.fullmatch(r'([0-9a-fA-F]{64})(?:[ \t]+\*?'+re.escape(n)+r')?',s)
if not m: raise SystemExit('Checksum response is not a single expected SHA256 record')
(p/'expected').write_text(m[1].lower())
PY
# Absolute 4 GiB response cap and 20 minute download ceiling.
# ulimit bounds output even if server omits Content-Length; curl adds its own cap.
( ulimit -f 4194304
  curl --fail --silent --show-error --proto '=https' --connect-timeout 30 \
    --max-time 1200 --speed-limit 65536 --speed-time 60 \
    --max-filesize 4294967296 --output "$WORK/$NAME" "$BASE/$NAME"
)
timeout 180 python3 - <<'PY'
import os,pathlib,hashlib,zipfile,json,re,stat
p=pathlib.Path(os.environ['WORK']); z=p/os.environ['NAME']
size=z.stat().st_size
if not 1024**3 <= size <= 4*1024**3: raise SystemExit('Unexpected archive size')
h=hashlib.sha256()
with z.open('rb') as f:
    for b in iter(lambda:f.read(8*1024*1024),b''): h.update(b)
if h.hexdigest() != (p/'expected').read_text(): raise SystemExit('SHA256 mismatch')
if not zipfile.is_zipfile(z): raise SystemExit('Not a ZIP archive')
print(json.dumps({'archive':z.name,'bytes':size,'sha256':h.hexdigest()}))
# Listing does not decompress files. Only bounded selected metadata is read,
# in-memory. No path extraction, executable invocation, or license acceptance.
with zipfile.ZipFile(z) as a:
    entries=a.infolist()
    if len(entries)>200000: raise SystemExit('Excessive entry count')
    selected=[]; names=set(); total=0
    for i in entries:
        name=i.filename
        if name in names: raise SystemExit('Duplicate ZIP entry')
        names.add(name)
        if name.startswith('/') or '\\' in name or '..' in pathlib.PurePosixPath(name).parts:
            raise SystemExit('Unsafe archive path')
        if i.flag_bits&1: raise SystemExit('Encrypted ZIP entry')
        total+=i.file_size
        if total>30*1024**3: raise SystemExit('Excessive total expanded size')
        base=pathlib.PurePosixPath(name).name.lower()
        license_file=bool(re.search(r'(^|[-_.])(licen[sc]e|notice|eula|agreement)([-_.]|$)',base))
        metadata=base in ('oh-uni-package.json','sdk-pkg.json','sdk-info.json','ohos-sdk.json','version.txt')
        # Include Hvigor/plugin/node manifests and bundle root manifests, not all dependencies.
        manifest=base=='package.json' and ('/hvigor/' in name.lower() or 'hvigor-ohos-plugin/' in name.lower() or len(pathlib.PurePosixPath(name).parts)<=3)
        if (license_file or metadata or manifest) and '/node_modules/' not in name:
            print('INVENTORY '+json.dumps({'path':name,'bytes':i.file_size,'compressed':i.compress_size,'kind':'license' if license_file else 'metadata'}))
            if not i.is_dir(): selected.append(i)
    # Abort rather than silently truncate or skip oversized selected material.
    if sum(i.file_size for i in selected)>32*1024**2 or any(i.file_size>2*1024**2 for i in selected):
        raise SystemExit('Selected metadata/license text exceeds bounded inspection budget')
    versions=[]; undecoded=[]
    selected.sort(key=lambda i: (not i.filename.endswith('.json'), i.filename))
    for i in selected:
        if stat.S_ISLNK(i.external_attr>>16):
            print('SYMLINK_METADATA_NOT_FOLLOWED '+json.dumps(i.filename)); continue
        b=a.read(i) # checks selected entry CRC; <=2 MiB each
        try: s=b.decode('utf-8-sig')
        except UnicodeDecodeError:
            if b.startswith((b'\xff\xfe', b'\xfe\xff')):
                s=b.decode('utf-16')
            else:
                undecoded.append(i.filename)
                print('UNDECODED '+json.dumps({'path':i.filename,'first_64_bytes_hex':b[:64].hex(),'sha256':hashlib.sha256(b).hexdigest()}))
                continue
        # JSON escaping prevents terminal escapes and GitHub workflow-command injection.
        print('CONTENT '+json.dumps({'path':i.filename,'text':s},ensure_ascii=True))
        if i.filename.endswith('.json'):
            try: obj=json.loads(s)
            except ValueError: continue
            if isinstance(obj,dict):
                record={k:obj[k] for k in ('name','version','apiVersion','releaseType','component','displayName','dependencies','devDependencies','engines') if k in obj}
                if record: versions.append({'path':i.filename,'fields':record})
    print('VERSION_EVIDENCE '+json.dumps(versions,ensure_ascii=True))
    print('UNDECODED_FILES '+json.dumps(undecoded))
    print('INSPECTION_ONLY: No SDK tools run, no licenses accepted. Embedded version metadata is evidence, not verified project compatibility. Only selected entry CRCs checked, not full archive integrity beyond published SHA256.')
PY
