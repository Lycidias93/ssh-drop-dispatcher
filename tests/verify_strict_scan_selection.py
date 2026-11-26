from pathlib import Path
import tempfile, subprocess, os, time, re
root=Path(__file__).resolve().parents[1]/'source/vnext-issue2516'
old=(root/'service.sh').read_text()
new=(root/'strict-scan-service.sh').read_text()
def func(s,name):
    m=re.search(r'^'+name+r'\(\)\{.*?^\}',s,re.M|re.S)
    assert m, name
    return m.group(0)
def line(name): return next(x for x in old.splitlines() if x.startswith(name+'(){'))
defs='\n'.join([line(x) for x in ('lower_name','has_token','is_partial','is_sidecar','is_supported','append_target')]+[func(old,x) for x in ('marker_targets_for','strict_target_prefix','targets_for')])
stubs='target_known(){ case "$1" in pi4|pi3) return 0;; *) return 1;; esac; }\nrecord(){ printf "%s" "$1"; }\nhandle_duplicate_alias(){ return 1; }\ncomplete_recorded(){ return 1; }\nfully_done_or_blocked(){ return 1; }\nnotify_already_present(){ :; }\n'
with tempfile.TemporaryDirectory() as d:
    p=Path(d); names=['target-pi4__a.txt','TARGET-PI4__b.txt','Targets-pi4-pi3__multi.zip','target-unknown__x.txt','target-pi4__partial.zip.part','target-pi4__side.sha256','legacy-pi4.txt','target-pi4__space name.txt','target-pi4__unsupported.jpg']
    for n in names+[f'ordinary-{i:04d}.txt' for i in range(1000)]: (p/n).touch()
    (p/'target-pi4__dir.txt').mkdir(); (p/'target-pi4__symlink.txt').symlink_to(p/names[0])
    def run(candidate,strict):
        env={**os.environ,'DROP_DISPATCH_SCAN_DIR':d,'DROP_DISPATCH_STRICT_TARGET_PREFIX':str(strict),'FIND_BIN':'find','TR_BIN':'tr','GREP_BIN':'grep','BASENAME_BIN':'basename','ACTIVE_TARGETS':'pi4 pi3','TMP_PENDING_LIST':'/dev/stdout'}
        listing=func(new,'list_target_candidates')+'\n'+func(new,'list_scan_candidates')+'\nlist_scan_candidates' if candidate else 'find "$DROP_DISPATCH_SCAN_DIR" -maxdepth 1 -type f'
        t=time.monotonic()
        queue=func(new if candidate else old,'queue_candidate')
        shell=defs+'\n'+stubs+queue+'\n'+listing+' | while IFS= read -r f; do queue_candidate "$f"; done'
        out=subprocess.check_output(['sh','-c',shell],env=env,text=True); return sorted(out.splitlines()),time.monotonic()-t
    for strict in (1,0):
        a,ta=run(False,strict); b,tb=run(True,strict)
        assert a==b,(strict,a,b)
        assert len(a)==(4 if strict else 5),(strict,a)
        print(f'FIXTURE PASS strict={strict} selected={len(a)} baseline_wall_s={ta:.3f} candidate_wall_s={tb:.3f}')
print('RESULT: STRICT_SCAN_SOURCE_FIXTURE_PASS')
