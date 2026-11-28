// Prints da dashboard/Financeiro e do modal com os DADOS REAIS da 021 Barra (exportados do banco).
// (NÃ£o Ã© a sessÃ£o logada; Ã© o cÃ³digo real rodando com os mesmos dados da conta.)
const {chromium,devices}=require('playwright');const fs=require('fs');
const D=JSON.parse(fs.readFileSync('tests/saida/real-021barra.json','utf8'));
const man=D.manuella;
const SEED=`(function(){
  var ch=function(){var o={};['select','eq','in','order','limit','update','delete','upsert','neq','gte','lte','is','or','match','insert','ilike','like'].forEach(function(k){o[k]=function(){return o;};});o.single=function(){return Promise.resolve({data:null});};o.maybeSingle=o.single;o.then=function(f,r){return Promise.resolve({data:[]}).then(f,r);};return o;};
  window.SB={from:ch,rpc:ch,storage:{from:function(){var o=ch();o.createSignedUrls=function(){return Promise.resolve({data:[]});};return o;}},channel:function(){return {on:function(){return this;},subscribe:function(){return this;}};}};
  RL.user={id:'u1',email:'contato.021barra@gmail.com'};RL.perfil={nome:'Fernando',prof:'Dentista'};S.role='dent';S.cad=Object.assign(S.cad||{},{nome:'Fernando',prof:'Dentista',ok:true});S.redeOn=false;document.body.classList.add('rl-in');
  labVMeus=function(){return [{id:'v1',status:'aceito',lab_id:'l1',lab_nome:'Ideali Lab'}];};
  try{if(typeof UNI!=='undefined'){UNI.ok=true;UNI.dono=true;UNI.voando=null;}}catch(e){}
  try{PH.d=[];PH.carregando=false;PH.erro='';}catch(e){}
  var R=${JSON.stringify({pedidos:D.pedidos,meses:D.meses,man:man})};
  var E={id:'lab-'+R.man.id,user_id:'u1',lab_id:R.man.lab_id,lab_nome:'Ideali Lab',numero:R.man.numero,paciente:R.man.paciente,itens:[{trabalho:R.man.trabalho,dentes:R.man.dentes,material:R.man.material}],cor:R.man.cor,status:'aceito',etapa:'Entregue',etapa_em:R.man.criado_em,enviado_em:R.man.criado_em,criado_em:R.man.criado_em,arquivos:[],_uni:true};
  PDG.L=[E];PDG.carregado=true;DFL.d={pedidos:R.pedidos,meses:R.meses};DFL.erro='';DFL.carregando=false;
  S.tab.dent='pedidos';S.labSub='fin';render();
  window.__ABRE_MODAL=function(){PDG.abre=E.id;if(typeof kcModal==='function')kcModal();};
})();`;
(async()=>{const b=await chromium.launch();const out=[];
  for(const [nm,opt] of [['pc',{viewport:{width:1440,height:900},colorScheme:'dark'}],['cel',Object.assign({},devices['Pixel 7'],{colorScheme:'light'})]]){
    const c=await b.newContext(opt);const p=await c.newPage();const errs=[];p.on('pageerror',e=>errs.push(e.message));
    await p.goto('http://localhost:8765/odonto/app/index.html');await p.waitForTimeout(1400);await p.evaluate(SEED);await p.waitForTimeout(800);
    const cards=await p.$$eval('.pdb-kc b',a=>a.map(x=>x.textContent.trim())).catch(()=>[]);
    const ov=await p.evaluate(()=>document.documentElement.scrollWidth-document.documentElement.clientWidth);
    out.push(nm+' cards: '+cards.join(' | '));
    out.push(nm+' overflow '+ov+'px Â· erros: '+(errs.length?errs.join(' ; '):'nenhum'));
    await p.screenshot({path:'tests/saida/dash-real-'+nm+'.png',fullPage:true});
    await p.evaluate(()=>window.__ABRE_MODAL());await p.waitForTimeout(500);
    const ficha=await p.$eval('#kc-ov .kc-ficha',e=>e.innerText.replace(/\n/g,' | ')).catch(()=>'(sem modal)');
    out.push(nm+' manuella: '+ficha);
    const el=await p.$('#kc-ov .kc-modal');if(el)await el.screenshot({path:'tests/saida/valor-real-manuella-'+nm+'.png'});
    await c.close();}
  console.log(out.join('\n'));await b.close();})();

