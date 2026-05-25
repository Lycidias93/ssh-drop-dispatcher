const out=document.getElementById('output');
async function rootExec(cmd){
  try{
    if(window.ksu && typeof window.ksu.exec==='function') return await window.ksu.exec(cmd);
    if(window.apatch && typeof window.apatch.exec==='function') return await window.apatch.exec(cmd);
    if(window.Android && typeof window.Android.exec==='function') return {stdout: await window.Android.exec(cmd), stderr:'', errno:0};
  }catch(e){return {stdout:'', stderr:String(e), errno:1};}
  return {stdout:'Root WebUI exec API not available in this manager. Use Termux: dispatch-config', stderr:'', errno:127};
}
document.querySelectorAll('button[data-cmd]').forEach(btn=>{
  btn.addEventListener('click', async()=>{
    const cmd=btn.getAttribute('data-cmd');
    out.textContent='$ '+cmd+'
Running...';
    const res=await rootExec(cmd);
    out.textContent='$ '+cmd+'

'+(res.stdout||'')+(res.stderr?'
ERR:
'+res.stderr:'')+'
rc='+(res.errno??0);
  });
});
