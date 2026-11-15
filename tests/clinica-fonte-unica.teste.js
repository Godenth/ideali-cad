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
  rpc:function(n,arg){CHAMADAS.push(n);if(n==='odo_clinica_recebi'){(window.RECEBI=window.RECEBI||[]).push(arg&&arg.p_id);return ch({data:{ok:true,n:1}});}
   if(n==='odo_clinica_pedidos')return ch(modo==='sem074'?{data:null,error:{code:'PGRST202',message:'Could not find the function public.odo_clinica_pedidos without parameters in the schema cache'}}:{data:D});
   if(n==='odo_clinica_pedidos_lab')return ch({data:D.pedidos.map(function(p){return {id:p.id,lab_id:p.lab_id,lab_nome:p.lab_nome,numero:p.numero,paciente:p.paciente,trabalho:p.trabalho,dentes:p.dentes,material:p.material,cor:p.cor,sobre_implante:p.sobre_implante,urgente:p.urgente,criado_em:p.criado_em,etapa:p.etapa};})});
   if(n==='odo_clinica_fin')return ch({data:{pedidos:D.pedidos.map(function(p){return {id:p.id,envio:null,lab_id:p.lab_id,lab:p.lab_nome,paciente:p.paciente,trabalho:p.trabalho,dentes:p.dentes,qtd:p.qtd,valor:p.valor==null?null:p.valor,status:p.status,enviado_inove:p.enviado_inove,cor:p.cor,material:p.material,criado:p.criado_em};}),meses:D.meses}});
   return ch({data:[]});},
  storage:{from:function(){var o=ch();o.createSignedUrls=function(){return Promise.resolve({data:[]});};return o;}},channel:function(){return {on:function(){return this;},subscribe:function(){return this;}};}};
 RL.user={id:'10000000-0000-0000-0000-000000000002'};RL.perfil={nome:'Fernando',prof:'Dentista'};S.role='dent';S.cad=Object.assign(S.cad||{},{nome:'Fernando',prof:'Dentista',ok:true});S.redeOn=false;document.body.classList.add('rl-in');
 if(modo==='func'&&typeof MEM!=='undefined'){MEM.dono='10000000-0000-0000-0000-000000000002';}
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
   await p.evaluate(()=>{S.tab.dent='pedidos';ACT.labSub('fin');});await p.waitForTimeout(900);
   ok(/(em aberto com o laboratório|tudo em dia|você deve isto)/i.test(await p.$eval('body',x=>x.innerText))&&(await p.$$eval('.fic-m',x=>x.length))>0,nm+': Financeiro abre pelo caminho antigo');
 }else{
   ok(uni===true,nm+': leitura única ativa');
   ok((await p.evaluate(()=>CHAMADAS.indexOf('odo_clinica_pedidos_lab')<0&&CHAMADAS.indexOf('odo_clinica_fin')<0)),nm+': não precisou das leituras antigas (uma chamada só)');
   ok((await chip('and'))===7,nm+': 7 em andamento (5 lançados pelo laboratório + 2 enviados pelo sistema)');
   ok((await chip('atr'))===0,nm+': 0 atrasados → os 29 antigos arquivados NÃO aparecem mais como atrasados');
   ok((await chip('pend'))===1,nm+': 1 pendência');
   ok((await chip('rcb'))+(await chip('prd'))+(await chip('pto'))===7,nm+': Recebido + Produção + Pronto = 7 em andamento');
   ok((await p.$$eval('.kb-col header b',x=>x.map(y=>y.innerText.trim()).join('|')))==='Recebido|Produção|Pronto',nm+': quadro com as 3 etapas: Recebido · Produção · Pronto');
   ok((await p.$$eval('.kb-rcb .kc',x=>x.some(y=>/Aguardando o laboratório aceitar/.test(y.innerText)))),nm+': pedido esperando aprovação fica em Recebido');
   ok(+(await p.$eval('.lsub [data-v=ent] .lsub-n',x=>x.textContent))===179,nm+': aba Entregues com 179');
   ok((await chip('tudo'))===187,nm+': 187 no total (184 + 3 envios; o apagado ficou de fora)');
   await larg('Pedidos (quadro)');await p.screenshot({path:path.join(SAIDA,nm+'-1-quadro.png')});
   // botão Recebi: só em pedido que o laboratório já aceitou
   const rc=await p.evaluate(()=>({n:document.querySelectorAll('.kb .kc-rcb').length,prod:document.querySelectorAll('.kb .kc').length-[...document.querySelectorAll('.kb .kc')].filter(y=>/Aguardando o laboratório aceitar/.test(y.innerText)).length,apr:[...document.querySelectorAll('.kb .kc')].filter(y=>/Aguardando o laboratório aceitar/.test(y.innerText)&&y.querySelector('.kc-rcb')).length}));
   ok(rc.n===rc.prod&&rc.n>0&&rc.apr===0,nm+': "Recebi" aparece nos '+rc.prod+' em produção e não aparece no que o laboratório ainda não aceitou');
   p.once('dialog',d=>d.accept());const idR=await p.$eval('.kb .kc-rcb',x=>x.getAttribute('data-v'));await p.click('.kb .kc-rcb');await p.waitForTimeout(500);
   ok((await p.evaluate(i=>RECEBI.length===1&&RECEBI[0]===i,idR)),nm+': clicar em "Recebi" manda a confirmação desse pedido para o banco');
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
   ok(/Itens deste pedido/.test(det)&&/Fresagem e maquiagem/.test(det)&&/(No desenho|Aprovado)/.test(det)&&/Recebido/i.test(det)&&/Produção/i.test(det),nm+': pedido com 2 itens mostra a etapa de cada item'+(process.env.DBG?' >> '+det.replace(/\n/g,' / '):''));
   await p.screenshot({path:path.join(SAIDA,nm+'-3-itens.png')});await p.keyboard.press('Escape');await p.waitForTimeout(200);await p.fill('#plx-q','');
   // finalizados: os antigos estão aqui, como entregues
   await p.click('.lsub [data-v=ent]');await p.waitForTimeout(300);ok(!(await p.$('.plx-s')),nm+': Entregues é uma aba própria');await p.fill('#plx-q','leyliane');await p.waitForTimeout(300);
   const fin=await p.$eval('#plx-corpo',x=>x.innerText);ok(/Pronto \/ enviado/.test(fin)&&!/Atrasado/.test(fin),nm+': pedido antigo aparece em Entregues como Pronto / enviado, sem "Atrasado"');
   await p.fill('#plx-q','');await p.click('.lsub [data-v=ped]');await p.waitForTimeout(300);
   // Início
   await p.evaluate(()=>{S.tab.dent='inicio';render();});await p.waitForTimeout(600);
   const ini=await p.$eval('main, body',x=>x.innerText);
   if(cel){ok(!!(await p.$('.dhero.cel-hero'))&&!/Painel dos trabalhos/.test(ini),nm+': no celular o Início é só a previsão do tempo (limpo)');}
   else if(modo==='dona'){ok(/Painel dos trabalhos/.test(ini),nm+': painel aparece para a dona');ok(/R\$\s?4\.534/.test(ini)||/4,5 mil/.test(ini),nm+': painel usa o fechamento de outubro (R$ 4.534)');}
   if(modo==='func'){ok(!/Painel dos trabalhos/.test(ini),nm+': funcionária não vê o painel de gastos');}
   await larg('Início');await p.screenshot({path:path.join(SAIDA,nm+'-4-inicio.png')});
   if(!cel){ok(/Agenda de hoje/.test(ini)&&/Tarefas do Pedro/.test(ini)&&/No laboratório agora/.test(ini)&&/Novidades do laboratório/.test(ini),nm+': Início tem agenda, laboratório, tarefas do Pedro e novidades');
   ok((await p.$$eval('.ini-p',x=>x.length))===4,nm+': Início mostra os 4 pedidos de prazo mais apertado');}
   // Financeiro: um extrato por mês, com a conta que vem do banco
   await p.evaluate(()=>{S.tab.dent='pedidos';S.labSub='ped';render();});await p.waitForTimeout(300);
   const abas=await p.$$eval('.lsub button',x=>x.map(y=>y.getAttribute('data-v')).join(','));
   if(modo==='func'){ok(abas==='ped,ent,labs',nm+': funcionária não tem Financeiro nem Pagamentos');
     await p.evaluate(()=>{S.labSub='fin';render();});await p.waitForTimeout(300);ok(!/R\$/.test(await p.$eval('body',x=>x.innerText)),nm+': forçar o Financeiro não mostra nenhum valor');}
   else{ok(abas==='ped,ent,fin,pag,labs',nm+': abas Em andamento · Entregues · Financeiro · Pagamentos e comprovantes · Laboratórios');
     await p.evaluate(()=>ACT.labSub('pag'));await p.waitForTimeout(400);const pg=await p.$eval('.fic',x=>x.innerText);ok(/(você deve isto|em aberto com o laboratório|tudo em dia)/i.test(pg)&&(await p.$$eval('.pgc-chip[data-act=phArq]',x=>x.length))===3&&(await p.$$eval('.pgc-ex',x=>x.length))===2,nm+': Pagamentos e comprovantes lista os pagamentos com comprovante e os extratos'+(process.env.DBG?' >> '+pg.slice(0,300)+' chips='+(await p.$$eval('.pgc-chip',x=>x.length)):''));await p.screenshot({path:path.join(SAIDA,nm+'-7-pagamentos.png'),fullPage:true});
     await p.click('.lsub [data-v=fin]');await p.waitForTimeout(500);
     const F=await p.$eval('.fic',x=>x.innerText),br=v=>'R$ '+v.toLocaleString('pt-BR',{minimumFractionDigits:2}).replace(/\s/g,' ');
     const M=dados.meses,falta=M.reduce((s,m)=>s+m.falta,0),pago=M.filter(m=>m.ano===2026).reduce((s,m)=>s+m.pago,0);
     const nrm=t=>t.replace(/\u00a0/g,' ');
     ok(nrm(F).includes(br(falta)),nm+': Financeiro · em aberto = soma do que falta no banco ('+br(falta)+')');
     ok(nrm(F).includes(br(pago)),nm+': Financeiro · pago no ano = soma dos pagamentos ('+br(pago)+')');
     ok((await p.$$eval('.fic-m.ab',x=>x.length))===1&&/Outubro/.test(await p.$eval('.fic-m.ab',x=>x.innerText)),nm+': o mês em aberto (outubro) já vem aberto');
     ok((await p.$$eval('.fic-st.aberto',x=>x.length))===1&&(await p.$$eval('.fic-st.ok',x=>x.length))===3,nm+': situação de cada mês igual à do laboratório (1 em aberto, 3 pagos)');
     await larg('Financeiro');await p.screenshot({path:path.join(SAIDA,nm+'-5-financeiro.png'),fullPage:true});
     await p.click('.fic-h[data-v="2026-08"]');await p.waitForTimeout(300);const ago=nrm(await p.$eval('.fic-m.ab:last-of-type, .fic-m.ab',x=>x.parentElement.innerText));
     ok(/Crédito de R\$ 228,00/.test(ago)&&/Comprovante/.test(ago),nm+': agosto mostra o crédito abatido e os comprovantes');
     await p.click('.fic-m.ab '+linha);await p.waitForTimeout(300);ok(!!(await p.$('#kc-ov')),nm+': tocar num pedido do extrato abre o detalhe');await p.keyboard.press('Escape');
     await p.screenshot({path:path.join(SAIDA,nm+'-6-financeiro-agosto.png'),fullPage:true});}
 }
 ok(errs.length===0,nm+': nenhum erro de JavaScript'+(errs.length?' → '+errs.join(' ; '):''));
 await c.close();}
console.log(R.join('\n'));console.log(falhas?('\n'+falhas+' FALHA(S)'):'\nTUDO PASSOU ('+R.length+' conferências)');await b.close();process.exit(falhas?1:0);})();
