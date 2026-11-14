// Clínica lendo da FONTE ÚNICA (074). Usa a resposta REAL da função do banco (tests/dados/*.json),
// gerada por tests/sql/gera_exemplo_clinica.sql. Confere: dona, funcionária e banco ainda sem a 074.
const {chromium,devices}=require('playwright');const fs=require('fs');const path=require('path');
const DONA=JSON.parse(fs.readFileSync(path.join(__dirname,'dados/clinica_dona.json'),'utf8'));
const FUNC=JSON.parse(fs.readFileSync(path.join(__dirname,'dados/clinica_funcionaria.json'),'utf8'));
const SAIDA=path.join(__dirname,'saida');fs.mkdirSync(SAIDA,{recursive:true});
const R=[];let falhas=0;const ok=(c,m)=>{R.push((c?'ok   ':'FALHOU ')+m);if(!c)falhas++;};

// prepara a página: banco de mentira que responde igual ao Supabase
function seed(modo,dados){return `(function(){var D=${JSON.stringify(dados)},modo=${JSON.stringify(modo)};
 var ch=function(res){var o={};['select','eq','in','order','limit','update','delete','upsert','neq','gte','lte','is','or','match','insert','range','not'].forEach(function(k){o[k]=function(){return o;};});o.single=function(){return Promise.resolve({data:null});};o.maybeSingle=o.single;o.then=function(f,r){return Promise.resolve(res||{data:[]}).then(f,r);};return o;};
 var envSimples=D.envios.map(function(e){var o={};for(var k in e)if(['partes','aberto','parado','prazo_min','prazo_max','faixa','lab_nome'].indexOf(k)<0)o[k]=e[k];return o;});
 window.CHAMADAS=[];
 window.SB={from:function(t){return ch(t==='odo_ped_env'?{data:envSimples}:{data:[]});},
  rpc:function(n){CHAMADAS.push(n);
   if(n==='odo_clinica_pedidos')return ch(modo==='sem074'?{data:null,error:{code:'PGRST202',message:'Could not find the function public.odo_clinica_pedidos without parameters in the schema cache'}}:{data:D});
   if(n==='odo_clinica_pedidos_lab')return ch({data:D.pedidos.map(function(p){return {id:p.id,lab_id:p.lab_id,lab_nome:p.lab_nome,numero:p.numero,paciente:p.paciente,trabalho:p.trabalho,dentes:p.dentes,material:p.material,cor:p.cor,sobre_implante:p.sobre_implante,urgente:p.urgente,criado_em:p.criado_em,etapa:p.etapa};})});
   if(n==='odo_clinica_fin')return ch({data:{pedidos:D.pedidos.map(function(p){return {id:p.id,envio:null,lab_id:p.lab_id,lab:p.lab_nome,paciente:p.paciente,trabalho:p.trabalho,dentes:p.dentes,qtd:p.qtd,valor:p.valor==null?null:p.valor,status:p.status,enviado_inove:p.enviado_inove,cor:p.cor,material:p.material,criado:p.criado_em};}),meses:D.meses}});
   return ch({data:[]});},
  storage:{from:function(){var o=ch();o.createSignedUrls=function(){return Promise.resolve({data:[]});};return o;}},channel:function(){return {on:function(){return this;},subscribe:function(){return this;}};}};
 RL.user={id:'10000000-0000-0000-0000-000000000002'};RL.perfil={nome:'Fernando',prof:'Dentista'};S.role='dent';S.cad=Object.assign(S.cad||{},{nome:'Fernando',prof:'Dentista',ok:true});S.redeOn=false;document.body.classList.add('rl-in');
 if(modo==='func'&&typeof MEM!=='undefined'){MEM.ativo=true;MEM.dono='10000000-0000-0000-0000-000000000002';}
 labVMeus=function(){return [{id:'v1',status:'aceito',lab_id:'20000000-0000-0000-0000-000000000001',lab_nome:'Ideali Lab'}];};
 S.tab.dent='pedidos';S.labSub='ped';return Promise.resolve(pdgCarrega()).then(function(){render();});})()`;}

(async()=>{const b=await chromium.launch();
for(const [nm,opt,modo,dados] of [
  ['dona-pc',{viewport:{width:1440,height:900},colorScheme:'dark'},'dona',DONA],
  ['dona-cel',Object.assign({},devices['Pixel 7'],{colorScheme:'light'}),'dona',DONA],
  ['funcionaria-pc',{viewport:{width:1440,height:900},colorScheme:'light'},'func',FUNC],
  ['sem074-pc',{viewport:{width:1440,height:900},colorScheme:'dark'},'sem074',DONA]]){
 const c=await b.newContext(opt);const p=await c.newPage();const errs=[];p.on('pageerror',e=>errs.push(e.message));
 await p.goto('http://localhost:8765/odonto/app/');await p.waitForTimeout(1300);await p.evaluate(seed(modo,dados));await p.waitForTimeout(700);
 const cel=nm.endsWith('cel'),linha=cel?'.plx-c':'.plx-r';
 const chip=async v=>+(await p.$eval('.plx-s[data-v='+v+'] b',x=>x.textContent));
 const larg=async t=>{const o=await p.evaluate(()=>document.documentElement.scrollWidth-document.documentElement.clientWidth);ok(o<=2,nm+': '+t+' cabe na largura da tela');};
 const uni=await p.evaluate(()=>UNI.ok);
 if(modo==='sem074'){
   ok(uni===false,nm+': banco sem a 074 → usa o caminho antigo sem quebrar');
   ok((await chip('tudo'))===187,nm+': continua mostrando os 187 pedidos pelo caminho antigo');
   ok((await p.evaluate(()=>CHAMADAS.indexOf('odo_clinica_pedidos_lab')>=0)),nm+': chamou a leitura antiga');
   await p.evaluate(()=>{S.tab.dent='inicio';render();});await p.waitForTimeout(900);
   ok(/Painel dos trabalhos/.test(await p.$eval('body',x=>x.innerText))&&(await p.evaluate(()=>CHAMADAS.indexOf('odo_clinica_fin')>=0&&!!DFL.d)),nm+': painel carrega pelo financeiro antigo');
 }else{
   ok(uni===true,nm+': leitura única ativa');
   ok((await p.evaluate(()=>CHAMADAS.indexOf('odo_clinica_pedidos_lab')<0&&CHAMADAS.indexOf('odo_clinica_fin')<0)),nm+': não precisou das leituras antigas (uma chamada só)');
   ok((await chip('and'))===7,nm+': 7 em andamento (5 lançados pelo laboratório + 2 enviados pelo sistema)');
   ok((await chip('atr'))===0,nm+': 0 atrasados → os 29 antigos arquivados NÃO aparecem mais como atrasados');
   ok((await chip('pend'))===1,nm+': 1 pendência');
   ok((await chip('apr'))===1,nm+': 1 aguardando aprovação');
   ok((await chip('fin'))===180,nm+': 180 finalizados (179 entregues + 1 recusado)');
   ok((await chip('tudo'))===187,nm+': 187 no total (184 + 3 envios; o apagado ficou de fora)');
   await larg('Pedidos (quadro)');await p.screenshot({path:path.join(SAIDA,nm+'-1-quadro.png')});
   // lista: prazo vem do banco
   await p.click('[data-plx=vis][data-v=lista]');await p.waitForTimeout(300);
   const txt=await p.$eval('#plx-corpo',x=>x.innerText);
   const ros=dados.pedidos.find(x=>x.paciente==='Rosanna Pozza');const dm=ros.prazo_max.slice(8,10)+'/'+ros.prazo_max.slice(5,7);
   ok(txt.includes('até '+dm),nm+': prazo da Rosanna é o do banco (até '+dm+')');
   ok(/Prazo parado/.test(txt),nm+': pendência aparece com prazo parado');
   if(modo==='dona')ok(/R\$/.test(txt),nm+': dona vê valores na lista');
   if(modo==='func')ok(!/R\$/.test(txt),nm+': funcionária NÃO vê nenhum valor na lista');
   await larg('Pedidos (lista)');await p.screenshot({path:path.join(SAIDA,nm+'-2-lista.png')});
   // pedido com 2 itens
   await p.fill('#plx-q','maria souza');await p.waitForTimeout(300);await p.click(linha);await p.waitForTimeout(400);
   const det=await p.$eval('#kc-ov',x=>x.innerText).catch(()=> '');
   ok(/Itens deste pedido/.test(det)&&/Na fresagem/.test(det)&&/No desenho/.test(det),nm+': pedido com 2 itens mostra a etapa de cada item');
   await p.screenshot({path:path.join(SAIDA,nm+'-3-itens.png')});await p.keyboard.press('Escape');await p.waitForTimeout(200);await p.fill('#plx-q','');
   // finalizados: os antigos estão aqui, como entregues
   await p.click('.plx-s[data-v=fin]');await p.waitForTimeout(300);await p.fill('#plx-q','leyliane');await p.waitForTimeout(300);
   const fin=await p.$eval('#plx-corpo',x=>x.innerText);ok(/Entregue/.test(fin)&&!/Atrasado/.test(fin),nm+': pedido antigo aparece em Finalizados como Entregue, sem "Atrasado"');
   await p.fill('#plx-q','');
   // Início
   await p.evaluate(()=>{S.tab.dent='inicio';render();});await p.waitForTimeout(600);
   const ini=await p.$eval('main, body',x=>x.innerText);
   if(modo==='dona'){ok(/Painel dos trabalhos/.test(ini),nm+': painel aparece para a dona');ok(/R\$\s?4\.534/.test(ini)||/4,5 mil/.test(ini),nm+': painel usa o fechamento de outubro (R$ 4.534)');}
   if(modo==='func'){ok(!/Painel dos trabalhos/.test(ini),nm+': funcionária não vê o painel de gastos');}
   await larg('Início');await p.screenshot({path:path.join(SAIDA,nm+'-4-inicio.png')});
 }
 ok(errs.length===0,nm+': nenhum erro de JavaScript'+(errs.length?' → '+errs.join(' ; '):''));
 await c.close();}
console.log(R.join('\n'));console.log(falhas?('\n'+falhas+' FALHA(S)'):'\nTUDO PASSOU ('+R.length+' conferências)');await b.close();process.exit(falhas?1:0);})();
