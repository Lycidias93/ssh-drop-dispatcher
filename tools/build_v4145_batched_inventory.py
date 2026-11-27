#!/usr/bin/env python3
"""Deterministic V4.14.5 overlay of the exact accepted V4.14.4 package.

Only the SDD failure inventory adapter and version metadata change.
No runtime installation, release publication or network access.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import tempfile
import zipfile
from copy import copy

BASE_SHA = "8107e07359cbb2d1513828a9ae2665bb700213bedd75223e071027882be0b575"
VERSION = "4.14.5-batched-inventory-v1"
VERSION_CODE = "4140500"
ADAPTER = "bin/module-control-base"
OLD = r'''inventory_failures() {
  lines=$(run_sdd --env failures 100 2>/dev/null | grep -v '^schema=' | grep -v '^host_run=' | grep -v '^RESULT:' || true)
  printf '{"ok":true,"name":"failures","columns":["evidence"],"items":['
  first=1
  printf '%s\n' "$lines" | while IFS= read -r line; do
    [ -n "$line" ] || continue
    [ "$first" = 1 ] || printf ','; first=0
    printf '{"evidence":'; json_string "$line"; printf '}'
  done
  printf ']}\n'
}'''
NEW = r'''inventory_failures() {
  lines=$(run_sdd --env failures 100 2>/dev/null) || {
    echo "failure inventory CLI unavailable" >&2
    return 69
  }
  printf '%s\n' "$lines" | LC_ALL=C awk '
BEGIN {
  for (i=1;i<32;i++) esc[sprintf("%c",i)]=sprintf("\\u%04x",i)
  esc[sprintf("%c",92)]="\\\\"
  esc[sprintf("%c",34)]="\\\""
  printf "{\"ok\":true,\"name\":\"failures\",\"columns\":[\"evidence\"],\"items\":["
  sep=""
}
/^schema=|^host_run=|^RESULT:/ || length($0)==0 {next}
{
  printf "%s{\"evidence\":\"",sep
  for(i=1;i<=length($0);i++) {
    c=substr($0,i,1)
    printf "%s",(c in esc ? esc[c] : c)
  }
  printf "\"}"
  sep=","
}
END {print "]}"}
'
}'''

def sha(data):
    return hashlib.sha256(data).hexdigest()

def require(ok, reason):
    if not ok:
        raise RuntimeError(reason)

def patch_adapter(data):
    text=data.decode("utf-8")
    require(text.count(OLD)==1,"exact_old_inventory_anchor")
    return text.replace(OLD,NEW,1).encode("utf-8")

def fixture(shell="sh"):
    # Exercise the exact replacement, including fail-closed CLI error.
    raw=("schema=SDD_FAILURES_V1\nhost_run=no\nfaildb_records=2\n"
         " leading and trailing  \nquote \" slash \\ tab\t ü 😀\n"
         +"controls "+''.join(chr(i) for i in range(1,32) if i!=10)
         +"\n\nRESULT: done\n").encode()
    env=dict(os.environ,LC_ALL="C")
    with tempfile.TemporaryDirectory() as td:
        d=Path(td)
        f=d/"fixture.txt"
        f.write_bytes(raw)
        program=d/"fixture.sh"
        program.write_text('run_sdd() { cat "$FIXTURE"; }\n'+NEW+'\ninventory_failures\n')
        env["FIXTURE"]=str(f)
        p=subprocess.run([shell,str(program)],env=env,capture_output=True,check=True)
        expected=[dict(evidence=l.decode()) for l in raw.split(b"\n") if l and not l.startswith((b"schema=",b"host_run=",b"RESULT:"))]
        require(json.loads(p.stdout)==dict(ok=True,name="failures",columns=["evidence"],items=expected),"fixture_content")
        f.write_bytes(b"schema=SDD_FAILURES_V1\nhost_run=no\nRESULT: done\n")
        p=subprocess.run([shell,str(program)],env=env,capture_output=True,check=True)
        require(json.loads(p.stdout)["items"]==[],"empty_inventory")
        program.write_text("run_sdd() { return 7; }\n"+NEW+"\ninventory_failures\n")
        p=subprocess.run([shell,str(program)],env=env,capture_output=True)
        require(p.returncode==69 and not p.stdout,"cli_failure_fail_closed")
    print("RESULT: SDD_V4145_INVENTORY_FIXTURE_PASS")

def build(base,output,shell="sh"):
    require(sha(base.read_bytes())==BASE_SHA,"base_sha")
    require(not output.exists(),"output_exists")
    output.parent.mkdir(parents=True,exist_ok=True)
    fixture(shell)
    with tempfile.TemporaryDirectory(dir=output.parent) as td, zipfile.ZipFile(base) as old:
        names=old.namelist()
        require(len(names)==len(set(names))==42 and old.testzip() is None,"base_integrity")
        adapter=patch_adapter(old.read(ADAPTER))
        prop=old.read("module.prop")
        require(prop.count(b"version=4.14.4-strict-scan-v1\n")==prop.count(b"versionCode=4140400\n")==1,"base_version")
        prop=prop.replace(b"version=4.14.4-strict-scan-v1\n",("version="+VERSION+"\n").encode()).replace(b"versionCode=4140400\n",("versionCode="+VERSION_CODE+"\n").encode())
        d=Path(td)
        (d/"adapter").write_bytes(adapter)
        subprocess.run([shell,"-n",str(d/"adapter")],check=True)
        files=[d/"first.zip",d/"second.zip"]
        changes={ADAPTER:adapter,"module.prop":prop}
        for path in files:
            with zipfile.ZipFile(path,"w") as z:
                z.comment=old.comment
                for info in old.infolist():
                    z.writestr(copy(info),changes.get(info.filename,old.read(info.filename)))
            with zipfile.ZipFile(path) as z:
                require(z.testzip() is None and z.namelist()==names,"zip_integrity")
                require({n for n in names if z.read(n)!=old.read(n)}==set(changes),"payload_delta")
                require(all(z.getinfo(n).external_attr==old.getinfo(n).external_attr for n in names),"mode_parity")
        require(files[0].read_bytes()==files[1].read_bytes(),"reproducibility")
        print("adapter_old_sha256="+sha(old.read(ADAPTER)))
        print("adapter_new_sha256="+sha(adapter))
        print("module_prop_sha256="+sha(prop))
        print("package_sha256="+sha(files[0].read_bytes()))
        print("package_bytes="+str(files[0].stat().st_size))
        files[0].replace(output)
    print("RESULT: SDD_V4145_BATCHED_INVENTORY_BUILD_PASS")

if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("--base",type=Path)
    p.add_argument("--output",type=Path)
    p.add_argument("--shell",default="sh")
    p.add_argument("--fixture",action="store_true")
    a=p.parse_args()
    if a.fixture:
        fixture(a.shell)
    else:
        if not a.base or not a.output: p.error("--base and --output required")
        build(a.base,a.output,a.shell)
