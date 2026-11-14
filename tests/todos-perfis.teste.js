const {chromium}=require('playwright');(async()=>{const b=await chromium.launch();
const c=await b.newContext({viewport:{width:1366,height:850}});const p=await c.newPage();const errs=[];p.on('pageerror',e=>errs.push(e.message));
await p.goto('http://localhost:8765/odonto/app/');await p.waitForTimeout(1500);
const out=await p.evaluate(async()=>{var ch=function(){var o={};['select','eq','in','order','limit','update','delete','upsert','neq','gte','lte','is','or','match','insert','not','ilike','range','filter','contains'].forEach(function(k){o[k]=function(){return o;};});o.single=function(){return Promise.resolve({data:null});};o.maybeSingle=o.single;o.then=function(f,r){return Promise.resolve({data:[]}).then(f,r);};return o;};
 window.SB={from:ch,rpc:ch,storage:{from:function(){var o=ch();o.createSignedUrls=function(){return Promise.resolve({data:[]});};o.createSignedUrl=function(){return Promise.resolve({data:{}});};return o;}},channel:function(){return {on:function(){return this;},subscribe:function(){return this;}};},auth:{getSession:function(){return Promise.resolve({data:{}});},onAuthStateChange:function(){},signOut:function(){return Promise.resolve();}},removeChannel:function(){}};
 RL.user={id:'u1',email:'a@b.c'};document.body.classList.add('rl-in');var R={},tabs={};
 for(const role of ['dent','prot','asb','corp','ind','stu']){S.role=role;S.cad=Object.assign(S.cad||{},{nome:'Teste Silva',prof:role,ok:true});RL.perfil={nome:'Teste',prof:role};S.redeOn=false;S.negOn=false;
   var D;try{D=PN();}catch(e){R[role]='PN erro '+e.message;continue;}
   var MM={dent:'DMENU',prot:'PMENU',asb:'AMENU',stu:'SMENU'};var T=[];try{var arr=window[MM[role]];if(arr)T=arr.map(function(x){return x[0];});else if(role==='corp'||role==='ind'){T=(CTABS[D.setor]||[]).map(function(x){return x[0];});}}catch(e){}if(T.indexOf('inicio')<0)T.unshift('inicio');if(role==='dent'){['ped','feitos','labs','fin','pag'].forEach(function(s){T.push('pedidos/'+s);});}
   var res=[];var lista=T.length?T:['inicio'];
   for(const t of lista){var tt=t.split('/');S.tab[role]=tt[0];if(tt[1])S.labSub=tt[1];var t0=performance.now();try{render();}catch(e){res.push(t+':ERRO '+e.message);continue;}res.push(t+':'+Math.round(performance.now()-t0)+'ms');}
   R[role]=res.join(' ');}
 return R;});
console.log(JSON.stringify(out,null,1));console.log('ERROS:',[...new Set(errs)].slice(0,15).join('\n'));
await b.close();})();
