// Prints antes/depois do "Valor" no modal do pedido (clínica/dentista).
// Roda o código real com banco falso; o pedido é o da Manuella (E-max, dente 24, sem preço salvo).
const {chromium}=require('playwright');
const SEED=`(function(){
  var ch=function(){var o={};['select','eq','in','order','limit','update','delete','upsert','neq','gte','lte','is','or','match','insert','ilike','like'].forEach(function(k){o[k]=function(){return o;};});o.single=function(){return Promise.resolve({data:null});};o.maybeSingle=o.single;o.then=function(f,r){return Promise.resolve({data:[]}).then(f,r);};return o;};
  window.SB={from:ch,rpc:ch,storage:{from:function(){var o=ch();o.createSignedUrls=function(){return Promise.resolve({data:[]});};return o;}},channel:function(){return {on:function(){return this;},subscribe:function(){return this;}};}};
  RL.user={id:'u1',email:'contato.021barra@gmail.com'};RL.perfil={nome:'Fernando',prof:'Dentista'};S.role='dent';S.cad=Object.assign(S.cad||{},{nome:'Fernando',prof:'Dentista',ok:true});S.redeOn=false;document.body.classList.add('rl-in');
  labVMeus=function(){return [{id:'v1',status:'aceito',lab_id:'l1',lab_nome:'Ideali Lab'}];};
  try{if(typeof UNI!=='undefined'){UNI.ok=true;UNI.dono=true;UNI.voando=null;}}catch(e){}
  try{PH.d=[];PH.carregando=false;PH.erro='';}catch(e){}
  var months=[{lab_id:'l1',lab:'Ideali Lab',ano:2026,mes:8,valor:6406,pago:6406,falta:0,credito:0,situacao:'pago',pagamentos:[],extrato:null}];
  var F=[];for(var i=0;i<70;i++){F.push({id:String(i),envio:null,lab_id:'l1',lab:'Ideali Lab',paciente:i===0?'Manuella Aben Athar Nobre':'Paciente '+i,trabalho:'E-max',material:'E-max',dentes:[24],qtd:1,valor:null,_est:false,status:'entregue',enviado_inove:true,cor:'A2',criado:(i===0?'2026-08-22T12:30:00.000Z':new Date(2026,7,1+(i%20)).toISOString()),etapa:'Entregue',aberto:false});}
  var E={id:'lab-0',user_id:'u1',lab_id:'l1',lab_nome:'Ideali Lab',numero:623,paciente:'Manuella Aben Athar Nobre',itens:[{trabalho:'E-max',dentes:[24],material:'E-max'}],cor:'A2',status:'aceito',etapa:'Entregue',etapa_em:'2026-08-22T12:30:00.000Z',criado_em:'2026-08-22T12:30:00.000Z',enviado_em:'2026-08-22T12:30:00.000Z',arquivos:[],_uni:true};
  PDG.L=[E];PDG.carregado=true;DFL.d={pedidos:F,meses:months};DFL.erro='';DFL.carregando=false;
  S.tab.dent='pedidos';S.labSub='ent';render();
  PDG.abre='lab-0';if(typeof kcModal==='function')kcModal();
})();`;
(async()=>{
  const b=await chromium.launch();const out=[];
  for(const [tag,url] of [['antes','index-antes.html'],['depois','index.html']]){
    const c=await b.newContext({viewport:{width:1200,height:900},colorScheme:'dark'});const p=await c.newPage();const errs=[];p.on('pageerror',e=>errs.push(e.message));
    await p.goto('http://localhost:8765/odonto/app/'+url);await p.waitForTimeout(1400);
    await p.evaluate(SEED);await p.waitForTimeout(600);
    const aberto=!!(await p.$('#kc-ov'));
    const ficha=aberto?await p.$eval('#kc-ov .kc-ficha',e=>e.innerText.replace(/\n/g,' | ')):'(modal não abriu)';
    out.push(tag+': modal='+aberto+' · erros JS: '+(errs.length?errs.join(' ; '):'nenhum'));
    out.push(tag+' ficha: '+ficha);
    const el=await p.$('#kc-ov .kc-modal');
    if(el)await el.screenshot({path:'tests/saida/valor-modal-'+tag+'.png'});
    else await p.screenshot({path:'tests/saida/valor-modal-'+tag+'.png'});
    await c.close();
  }
  console.log(out.join('\n'));await b.close();
})();
