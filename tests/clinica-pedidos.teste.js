const {chromium,devices}=require('playwright');
const SEED=`(function(){var ch=function(){var o={};['select','eq','in','order','limit','update','delete','upsert','neq','gte','lte','is','or','match','insert'].forEach(function(k){o[k]=function(){return o;};});o.single=function(){return Promise.resolve({data:null});};o.maybeSingle=o.single;o.then=function(f,r){return Promise.resolve({data:[]}).then(f,r);};return o;};
 window.SB={from:ch,rpc:ch,storage:{from:function(){var o=ch();o.createSignedUrls=function(){return Promise.resolve({data:[]});};return o;}},channel:function(){return {on:function(){return this;},subscribe:function(){return this;}};}};
 RL.user={id:'u1'};RL.perfil={nome:'Fernando',prof:'Dentista'};S.role='dent';S.cad=Object.assign(S.cad||{},{nome:'Fernando',prof:'Dentista',ok:true});S.redeOn=false;document.body.classList.add('rl-in');
 labVMeus=function(){return [{id:'v1',status:'aceito',lab_id:'l1',lab_nome:'Ideali Lab'}];};
 var P=['Leonardo da Cunha Mello','Cristina Poça da Conceição','Cláudio Malibeu Bentes','Francisca Rafaela Rosa','Ronald Grey','Reginaldo de Miranda','Jennifer Duarte Marques','Rogério de Oliveira Coelho','Camila da Cunha Wanzeller','Michel Felipe Magalhães','Armando de Santana Alves','Josué Oliveira Carvalho'],T=['Zircônia','E-max','Coroa zircônia','Protocolo zircônia','Coroa e-max','Faceta E.max'];
 var s=11;function r(n){s=(s*9301+49297)%233280;return Math.floor(s/233280*n);}var u=contaId(),L=[],F=[];
 for(var i=0;i<190;i++){var d=new Date();d.setDate(d.getDate()-(i<29?(i<20?200+r(100):r(12)):r(320)));var t=T[r(T.length)],ds=[[11,12,14,16,21,24,26,27,35,36,37,46,47][r(13)]];
  var st=i<20?'aceito':i<25?'aceito':i<27?'aceito':i<29?'enviado':'aceito',et=i<20?'Enviado para fresagem':i<25?['Desenho CAD','Desenhado','Maquiagem','Enviado para fresagem','Desenho CAD'][i-20]:i<27?'Aguardando informação':i<29?null:'Entregue';
  var id=(i<150&&i!==25)?'lab-'+i:'e'+i;L.push({id:id,user_id:u,status:st,etapa:et,falta_info:et==='Aguardando informação'?'Escaneamento do antagonista cortado, mande de novo':null,paciente:P[r(P.length)],itens:[{trabalho:t,dentes:ds}],cor:['A2','A3','BL2','A3,5'][r(4)],lab_id:'l1',enviado_em:d.toISOString(),criado_em:d.toISOString(),etapa_em:d.toISOString(),arquivos:[]});
  F.push({id:(i<150&&i!==25)?String(i):'p'+i,envio:(i<150&&i!==25)?null:id,lab_id:'l1',lab:'Ideali Lab',paciente:L[i].paciente,trabalho:t,material:/max/i.test(t)?'E-max':'Zircônia',dentes:ds,qtd:1,valor:i%3?null:350,status:et==='Entregue'?'entregue':'producao',criado:d.toISOString()});}
 var meses=[];for(var k=0;k<12;k++){var dd=new Date();dd.setMonth(dd.getMonth()-k);meses.push({lab_id:'l1',ano:dd.getFullYear(),mes:dd.getMonth()+1,valor:3000+k*250,pago:k<2?0:3000+k*250});}
 PDG.L=L;PDG.carregado=true;DFL.d={pedidos:F,meses:meses};S.tab.dent='pedidos';S.labSub='ped';render();})();`;
(async()=>{const b=await chromium.launch();const R=[];
for(const [nm,opt] of [['pc-escuro',{viewport:{width:1440,height:900},colorScheme:'dark'}],['cel-claro',Object.assign({},devices['Pixel 7'],{colorScheme:'light'})]]){
 const c=await b.newContext(opt);const p=await c.newPage();const errs=[];p.on('pageerror',e=>errs.push(e.message));
 await p.goto('http://localhost:8765/odonto/app/');await p.waitForTimeout(1300);await p.evaluate(SEED);await p.waitForTimeout(500);
 const ov=async(tag)=>{const o=await p.evaluate(()=>document.documentElement.scrollWidth-document.documentElement.clientWidth);if(o>2)R.push(nm+' '+tag+': ESTOURA LARGURA '+o+'px');};
 const shot=async(n)=>{await ov(n);await p.screenshot({path:'tests/saida/'+nm+'-'+n+'.png'});};
 await shot('1-inicial');
 const chips=await p.$$eval('.plx-s',a=>a.map(x=>x.innerText.replace(/\n/g,' ')));R.push(nm+' chips: '+chips.join(' | '));
 await p.click('.plx-s[data-v=fin]');await p.waitForTimeout(300);await shot('2-finalizados');
 R.push(nm+' finalizados linhas visiveis: '+await p.$$eval(nm.startsWith('cel')?'.plx-c':'.plx-r',a=>a.length));
 await p.fill('#plx-q','cristina');await p.waitForTimeout(300);R.push(nm+' busca cristina: '+await p.$$eval(nm.startsWith('cel')?'.plx-c':'.plx-r',a=>a.length)+' (chip Finalizados='+await p.$eval('.plx-s[data-v=fin] b',x=>x.textContent)+')');
 await shot('3-busca');
 await p.click('[data-plx=vis][data-v=mes]');await p.waitForTimeout(300);await shot('4-por-mes');
 await p.fill('#plx-q','');await p.waitForTimeout(200);
 await p.click('.plx-s[data-v=atr]');await p.waitForTimeout(300);R.push(nm+' atrasados: '+await p.$eval('.plx-s[data-v=atr] b',x=>x.textContent));await shot('5-atrasados');
 await p.click(nm.startsWith('cel')?'.plx-c':'.plx-r');await p.waitForTimeout(400);R.push(nm+' modal abriu: '+!!(await p.$('#kc-ov')));await shot('6-detalhe');
 await p.keyboard.press('Escape');await p.waitForTimeout(200);R.push(nm+' modal fechou com Esc: '+!(await p.$('#kc-ov')));
 await p.click('.plx-s[data-v=and]');await p.waitForTimeout(300);await p.click('[data-plx=vis][data-v=quadro]');await p.waitForTimeout(300);await shot('7-quadro');
 await p.click('.btn.pri[data-kc=e25]');await p.waitForTimeout(400);R.push(nm+' responder pendencia: campo='+!!(await p.$('#kc-ov #pend-t')));await shot('8-responder');
 await p.keyboard.press('Escape');await p.waitForTimeout(200);R.push(nm+' fechou depois de responder: '+!(await p.$('#kc-ov'))+' foco='+await p.evaluate(()=>document.activeElement&&document.activeElement.id));
 await p.click('[data-act=dTab][data-v=inicio]').catch(()=>{});await p.waitForTimeout(500);await p.evaluate(()=>window.scrollTo(0,500));await p.waitForTimeout(1500);R.push(nm+' overlays: '+await p.evaluate(()=>[].map.call(document.querySelectorAll('body > div'),function(d){var cs=getComputedStyle(d);return cs.position==='fixed'&&d.offsetWidth>300?(d.id||d.className):'';}).filter(Boolean).join(',')));await shot('9-inicio');
 R.push(nm+' erros JS: '+(errs.length?errs.join(' ; '):'nenhum'));await c.close();}
console.log(R.join('\n'));await b.close();})();
