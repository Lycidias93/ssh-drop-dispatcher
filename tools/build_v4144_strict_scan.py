#!/usr/bin/env python3
"""Build the exact source-only strict-scan overlay; no install or publication."""
import argparse, hashlib, tempfile, zipfile
from pathlib import Path
from copy import copy
SOURCE=Path(__file__).resolve().parents[1]/'source/vnext-issue2516/strict-scan-service.sh'
BASE_SHA='1567c65101d6c55c2fdcb26b3b2cfe30d6b12c767ab35c1c26352d1d1e32465a'
SOURCE_SHA='db5cddbed700d41b55245dbe282a08375e3c83e4e50fb4b08875d17459a1f563'
ASSET_SHA='8107e07359cbb2d1513828a9ae2665bb700213bedd75223e071027882be0b575'
def sha(b): return hashlib.sha256(b).hexdigest()
def require(ok,why):
    if not ok: raise RuntimeError(why)
def build(base,out):
    source=SOURCE.read_bytes()
    require(sha(base.read_bytes())==BASE_SHA,'base_hash')
    require(sha(source)==SOURCE_SHA,'source_hash')
    require(not out.exists(),'output_exists')
    out.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(dir=out.parent) as td, zipfile.ZipFile(base) as old:
        names=old.namelist()
        require(len(names)==len(set(names))==42 and old.testzip() is None,'base_integrity')
        require(sha(old.read('service.sh'))=='76fcdf95da041170f746b7d4c0bf690988538b6407017a0c649e8962e4e73e1c','base_service')
        prop=old.read('module.prop')
        require(prop.count(b'version=4.14.3-guarded-tools-v1\n')==prop.count(b'versionCode=4140300\n')==1,'base_version')
        prop=prop.replace(b'version=4.14.3-guarded-tools-v1\n',b'version=4.14.4-strict-scan-v1\n').replace(b'versionCode=4140300\n',b'versionCode=4140400\n')
        paths=[Path(td)/n for n in ('one.zip','two.zip')]
        for p in paths:
            with zipfile.ZipFile(p,'w') as z:
                z.comment=old.comment
                for i in old.infolist():
                    z.writestr(copy(i),source if i.filename=='service.sh' else prop if i.filename=='module.prop' else old.read(i.filename))
            with zipfile.ZipFile(p) as z:
                require(z.testzip() is None and z.namelist()==names,'integrity')
                require({n for n in names if z.read(n)!=old.read(n)}=={'service.sh','module.prop'},'delta')
                require(all(z.getinfo(n).external_attr==old.getinfo(n).external_attr for n in names),'modes')
        require(paths[0].read_bytes()==paths[1].read_bytes(),'rebuild')
        require(sha(paths[0].read_bytes())==ASSET_SHA,'asset_hash')
        paths[0].replace(out)
    print('RESULT: SDD_STRICT_SCAN_BUILD_PASS sha256='+ASSET_SHA)
if __name__=='__main__':
    p=argparse.ArgumentParser()
    p.add_argument('--base',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    build(a.base,a.output)
