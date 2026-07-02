enum UsageExportScripts {
    static let interceptJS = """
    (function(){if(window.__gh)return;window.__gh=true;
    const post=(f,d)=>{window.webkit.messageHandlers.usageExport.postMessage({filename:f,dataURL:d})};
    const oc=URL.createObjectURL;URL.createObjectURL=function(b){const r=new FileReader();
    r.onload=()=>post('export.csv',r.result);r.readAsDataURL(b);return oc.call(URL,b)};
    const of=window.fetch;window.fetch=function(...a){return of.apply(this,a).then(r=>{
    const ct=(r.headers.get('content-type')||'').toLowerCase();
    const cd=(r.headers.get('content-disposition')||'').toLowerCase();
    if(ct.includes('zip')||ct.includes('csv')||ct.includes('octet')||ct.includes('excel')||
    cd.includes('attachment')||cd.includes('export')||cd.includes('usage')){
    r.clone().blob().then(b=>{const rr=new FileReader();rr.onload=()=>post('export.csv',rr.result);rr.readAsDataURL(b)})}return r})};
    const OX=window.XMLHttpRequest;window.XMLHttpRequest=function(){const x=new OX();let u='';
    const oo=x.open;x.open=function(m,url,...r){u=url;return oo.call(this,m,url,...r)};
    x.addEventListener('load',function(){const ct=(x.getResponseHeader('content-type')||'').toLowerCase();
    if(ct.includes('csv')||ct.includes('zip')||u.includes('export')||u.includes('download')){
    let b='';const by=new Uint8Array(x.response||x.responseText||'');
    for(let i=0;i<by.length;i++)b+=String.fromCharCode(by[i]);
    post('export.csv','data:text/csv;base64,'+btoa(b))}});return x};
    document.addEventListener('click',function(e){const a=e.target.closest('a');
    if(a&&(a.download||/\\.(csv|zip)/i.test(a.href||''))){e.preventDefault();
    fetch(a.href).then(r=>r.blob()).then(b=>{const rr=new FileReader();
    rr.onload=()=>post(a.download||'export.csv',rr.result);rr.readAsDataURL(b)})}},true)})();
    """

    static let clickJS = """
    (function(){const btns=document.querySelectorAll('div.ds-button[role="button"]');let t=null;
    btns.forEach(e=>{if((e.textContent||'').trim()==='导出')t=e});
    if(!t){const all=document.querySelectorAll('[role="button"],button,a');
    for(const e of all){if((e.textContent||'').trim().includes('导出')){t=e;break}}}
    if(!t)return'no_button';
    const rk=Object.keys(t).find(k=>k.startsWith('__reactFiber$')||k.startsWith('__reactInternalInstance$'));
    if(rk){const f=t[rk];let c=f;
    for(let i=0;i<15&&c;i++){if(c.memoizedProps&&typeof c.memoizedProps.onClick==='function'){
    c.memoizedProps.onClick({preventDefault:()=>{},stopPropagation:()=>{},nativeEvent:{}});return'react_'+i}
    if(c.pendingProps&&typeof c.pendingProps.onClick==='function'){
    c.pendingProps.onClick({preventDefault:()=>{},stopPropagation:()=>{},nativeEvent:{}});return'pending_'+i}
    c=c.return}}
    t.scrollIntoView({block:'center'});
    ['pointerover','mouseover','pointerenter','mouseenter','pointerdown','mousedown','pointerup','mouseup','click'].forEach(n=>t.dispatchEvent(new MouseEvent(n,{bubbles:true,cancelable:true})));
    if(t.click)t.click();return'dom_clicked'})();
    """
}
