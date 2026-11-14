// Laboratório: a Ana lê o extrato do mês, dá baixa nos pedidos que estão nele (data do extrato = dia em que
// ficou pronto), cadastra o que não existe e monta o mapa de prazos. Também: pedidos confirmados pelo cliente.
// Tudo com banco de mentira (nada sai daqui).
const {chromium}=require('playwright');const fs=require('fs');let falhas=0;const R=[];const ok=(c,t)=>{R.push((c?'ok   ':'FALHOU ')+t);if(!c)falhas++;};
// texto como o leitor de PDF do sistema monta (mesmo formato do extrato real da Inove; nomes de teste)
const EXTRATO=`Inove 3D Laboratório Extrato Individual
01/07/2026 a 31/07/2026
Cliente: Clínica A [0001] CPF/CNPJ: 00.000.000/0001-00
Data Ficha Histórico Valor Saldo
Saldo Anterior: 0,00
02/07/2026 013502-1 Paciente: SILVIA -260,00 -260,00
1 Coroa Maquiada (ZRO) -260,00
03/07/2026 013503-1 Paciente: BEATRIZ TEIXEIRA -315,00 -575,00
1 Coroa Maquiada (ZRO) -260,00
1 link Base de Titânio Neodent -55,00
08/07/2026 013510-1 Paciente: DORA -200,00 -775,00
1 Coroa -200,00
10/07/2026 013520-1 Paciente: CARLOS LIMA -500,00 -1.275,00
2 Coroa Maquiada (ZRO) -500,00
15/07/2026 013530-1 Paciente: JOAO NOVO -600,00 -1.875,00
2 Coroa Maquiada (ZRO) -600,00
16/07/2026 013531-1 Paciente: GIL OLIVEIRA -100,00 -1.975,00
1 Provisório -100,00
24/07/2026 Pagamento Efetuado! 520,00 -1.455,00
Pix 24/07/2026 PAGAMENTO EM 07/07 520,00
Saldo Anterior: 0,00
Total de Pagamentos (C): 520,00
Total de Débitos (D): -1.975,00
1/1
24/07/2026 10:46:04`;
(async()=>{const b=await chromium.launch();const p=await b.newPage({viewport:{width:1366,height:900}});const errs=[];p.on('pageerror',e=>errs.push(e.message));
 await p.goto('http://localhost:8765/odonto/app/');await p.waitForTimeout(1300);
 // 1. leitura das linhas: extrato real (Anthony Borges, julho) e o de teste
 const real=process.argv[2]&&fs.existsSync(process.argv[2])?fs.readFileSync(process.argv[2],'utf8'):null;
 if(real){const L=await p.evaluate(t=>exbLinhasTx(t),real);
   ok(L.length===2&&L[0].paciente==='SILVIA'&&L[0].data==='2026-07-02'&&L[0].valor===260&&L[1].paciente==='BEATRIZ TEIXEIRA'&&L[1].itens.length===2&&L[1].itens[1].valor===55,'extrato real: lê as 2 linhas de serviço (data, paciente, itens, valor) e ignora os 3 pagamentos');}
 const LT=await p.evaluate(t=>exbLinhasTx(t),EXTRATO);
 ok(LT.length===6&&LT[4].itens[0].qtd===2&&LT.every(l=>l.paciente),'extrato de teste: 6 serviços, quantidade dos itens, pagamento fora');
 await p.evaluate((LT)=>{window.UPD=[];window.INS=[];
  var ch=function(t){var o={_t:t};['select','eq','order','limit','delete','upsert','neq','gte','lte','is','or','match','range','not'].forEach(function(k){o[k]=function(){return o;};});
    o.update=function(pt){o._p=pt;return o;};o.insert=function(rows){o._ins=rows;INS.push.apply(INS,rows);return o;};
    o.in=function(c,ids){if(o._p)UPD.push({t:t,p:o._p,ids:ids});return o;};o.single=function(){return Promise.resolve({data:t==='odo_empresas'?Object.assign({},EMP.row,{dados:o._p&&o._p.dados}):null});};o.maybeSingle=o.single;
    o.then=function(f,r){var d=o._ins?o._ins.map(function(x,i){return Object.assign({id:'novo'+i},x);}):[];if(o._p&&t==='odo_pedidos'&&!UPD.some(function(u){return u.p===o._p;}))UPD.push({t:t,p:o._p,ids:null});return Promise.resolve({data:d}).then(f,r);};return o;};
  window.SB={from:function(t){return ch(t);},rpc:function(){return ch('rpc');},storage:{from:function(){return {createSignedUrl:function(){return Promise.resolve({data:null,error:{message:'teste'}});}};}},channel:function(){return {on:function(){return this;},subscribe:function(){return this;}};}};
  RL.user={id:'u-lab'};RL.perfil={nome:'Lab',prof:'Protético'};S.role='prot';S.cad=Object.assign(S.cad||{},{nome:'Lab',ok:true});document.body.classList.add('rl-in');pedAtivo=function(){return true;};
  EMP.row={id:'emp1',dados:{}};EMP.cli=[{id:'cA',nome:'Clínica A',reg:1},{id:'cB',nome:'Clínica B',reg:2}];
  var P=function(id,n,cli,pac,st,criado,x){return Object.assign({id:id,numero:n,cliente_id:cli,paciente:pac,trabalho:'Coroa zircônia',status:st,arquivado:false,apagado:false,criado_em:criado,tipo:'cad'},x||{});};
  PED.L=[P('p1',1,'cA','Silvia Souza','producao','2026-06-29T10:00:00-03:00'),
         P('p2',2,'cA','Beatriz Teixeira','finalizado','2026-06-22T10:00:00-03:00'),
         P('p3',3,'cA','Carlos Lima','producao','2026-07-01T15:00:00-03:00',{envio_id:'e1'}),P('p4',4,'cA','Carlos Lima','desenho','2026-07-01T15:00:00-03:00',{envio_id:'e1',trabalho:'Coroa e.max'}),
         P('p5',5,'cA','Dora','entregue','2026-07-01T09:00:00-03:00',{arquivado:true}),
         P('p6',6,'cA','Eva Aberta','producao','2026-07-20T10:00:00-03:00'),
         P('p7',7,'cB','Silvia','producao','2026-06-29T10:00:00-03:00'),
         P('p9',9,'cA','Gil Santos','producao','2026-07-10T10:00:00-03:00'),
         P('p10',10,'cA','Hugo Agosto','producao','2026-08-03T10:00:00-03:00'),
         P('p11',11,'cB','Hugo Recebido','entregue','2026-11-01T12:00:00Z',{arquivado:true,recebido_em:new Date(Date.now()-3600e3).toISOString(),recebido_antes:'finalizado'})];
  PED.cad=[];PED.carregado=true;PED.erro='';
  FIN.M=[{id:'m1',cliente_id:'cA',ano:2026,mes:7,valor_mes:1975,valor_componente:0,extrato_path:null},{id:'m2',cliente_id:'cB',ano:2026,mes:7,valor_mes:500,valor_componente:0,extrato_path:null}];
  FIN.P=[];FIN.C=[];FIN.cfg={comissao_pct:10};FIN.ano=2026;FIN.mes=7;FIN.carregado=true;FIN.erro='';
  EXB.cache['cA|2026-7']=LT;S.tab.prot='financeiro';render();},LT);
 await p.waitForTimeout(300);
 ok(!(await p.$('#exb-ov')),'sem extrato anexado, nada é oferecido');
 // 2. anexa o extrato de julho da Clínica A
 await p.evaluate(()=>{finAtual(Object.assign({},FIN.M[0],{extrato_path:'u-lab/extratos/2026-07/x.pdf'}));render();});await p.waitForTimeout(1500);
 ok(!!(await p.$('#exb-ov')),'anexou o extrato → abre a conferência sozinha');
 const sec=await p.$$eval('#exb-ov .exb-sec',x=>x.map(s=>({t:s.querySelector('h4').innerText,n:[...s.querySelectorAll('.pfx-i')].map(i=>i.innerText.replace(/\s+/g,' ')),c:[...s.querySelectorAll('input')].map(i=>i.checked)})));
 const [sb,sn,sf]=sec;
 ok(sec.length===3,'3 grupos: abertos no extrato, não cadastrados, abertos fora do extrato');
 ok(sb.n.length===4&&/Silvia Souza/.test(sb.n[0])&&/Beatriz/.test(sb.n[1])&&/Carlos Lima/.test(sb.n[2])&&/Gil Santos/.test(sb.n[3]),'acha cada paciente nos pedidos da Clínica A (SILVIA → Silvia Souza; CARLOS LIMA → envio com 2 itens)');
 ok(/#3 \+1/.test(sb.n[2]),'os 2 itens do mesmo envio da clínica entram juntos');
 ok(/4 dias úteis/.test(sb.n[0])&&/Antes do prazo/.test(sb.n[0]),'Silvia: entrou 29/06 10h, pronto 02/07 → 4 dias úteis → antes do prazo');
 ok(/10 dias úteis/.test(sb.n[1])&&/Atrasado 3 dias/.test(sb.n[1]),'Beatriz: entrou 22/06, pronto 03/07 → 10 dias úteis → atrasado 3');
 ok(/7 dias úteis/.test(sb.n[2])&&/No prazo/.test(sb.n[2]),'Carlos: entrou 01/07 às 15h (conta a partir de 02/07), pronto 10/07 → 7 dias úteis → no prazo');
 ok(/nome parecido/.test(sb.n[3])&&sb.c.join()==='true,true,true,false','nome só parecido (GIL OLIVEIRA × Gil Santos) vem desmarcado, com aviso');
 ok(sn.n.length===1&&/JOAO NOVO/.test(sn.n[0])&&/R\$\s?600,00/.test(sn.n[0])&&sn.c[0],'paciente que não está no sistema: a Ana oferece cadastrar com o preço do extrato');
 ok(sf.n.length===1&&/Eva Aberta/.test(sf.n[0])&&!sf.c[0],'aberto que não está no extrato vem desmarcado (Hugo, de agosto, nem aparece)');
 ok(!sec.some(s=>s.n.some(t=>/#7/.test(t))),'pedido da Clínica B com o mesmo nome (Silvia) não entra');
 ok(/1 linha já tinha baixa/.test(await p.$eval('#exb-ov',x=>x.innerText)),'Dora já tinha baixa: só guarda a data de pronto');
 const bt=await p.$eval('#exb-ov [data-exb=vai]',x=>x.innerText);ok(bt==='Confirmar 4 baixas e 1 cadastro','botão: '+bt);
 await p.screenshot({path:'tests/saida/lab-baixa-extrato.png'});
 await p.click('#exb-ov [data-exb=vai]');await p.waitForTimeout(700);
 const u=await p.evaluate(()=>UPD.filter(x=>x.t==='odo_pedidos').map(x=>({ids:x.ids.join(','),p:x.p})));
 const de=id=>u.filter(x=>x.ids.split(',').includes(id)).map(x=>x.p);
 ok(de('p1').length===1&&de('p1')[0].status==='entregue'&&de('p1')[0].arquivado&&de('p1')[0].finalizado_em==='2026-07-02T12:00:00-03:00','Silvia: baixa com a data de pronto do extrato (02/07)');
 ok(de('p3').length===1&&de('p4').length===1&&de('p3')[0].finalizado_em.startsWith('2026-07-10'),'Carlos (2 itens): baixa com 10/07');
 ok(de('p5').length===1&&de('p5')[0].finalizado_em.startsWith('2026-07-08')&&!('status' in de('p5')[0]),'Dora: só ganhou a data de pronto (08/07)');
 ok(!de('p6').length&&!de('p9').length&&!de('p7').length&&!de('p10').length,'desmarcados, outra clínica e agosto: não mexe');
 const ins=await p.evaluate(()=>INS);
 ok(ins.length===1&&ins[0].paciente==='JOAO NOVO'&&ins[0].valor===600&&ins[0].qtd===2&&ins[0].cliente_id==='cA'&&ins[0].origem==='extrato'&&ins[0].status==='entregue'&&ins[0].arquivado&&/ficha 013530-1/.test(ins[0].obs)&&ins[0].numero===12,'JOAO NOVO cadastrado: Clínica A, 2 coroas, R$ 600, nº 12, entregue, marcado como vindo do extrato');
 ok((await p.evaluate(()=>{var l=(EMP.row.dados||{}).lotes||[];return l.length===1&&l[0].criados.length===1&&Object.keys(l[0].antes).some(k=>k.split('|').length===4);})),'fica registrado para desfazer (inclusive data de pronto e o cadastro)');
 // 3. ler o mesmo extrato de novo não duplica
 await p.evaluate(()=>{EXB.visto=null;});const R2=await p.evaluate(()=>{var R=exbCasa(FIN.M[0],EXB.cache['cA|2026-7']);return {b:R.baixa.length,n:R.novo.length,ja:R.ja.length};});
 ok(R2.n===0&&R2.ja===5&&R2.b===1,'ler o mesmo extrato de novo: ninguém é cadastrado duas vezes (só sobra o nome parecido)');
 // 4. mapa de prazos
 await p.evaluate(()=>{S.tab.prot='producao';PZM.per='tudo';render();});await p.waitForTimeout(300);
 await p.click('[data-pzm=abre]');await p.waitForTimeout(500);
 const k=await p.$$eval('.pzm-k .pdb-kc b',x=>x.map(y=>y.innerText));
 ok(k[0]==='1'&&k[1]==='3'&&k[2]==='1','mapa: 1 antes (Silvia), 3 no prazo (Carlos ×2, Dora), 1 atrasado (Beatriz) → '+k.join(' / '));
 const tx=await p.$eval('.dmain, main, body',x=>x.innerText);
 ok(!/JOAO NOVO/.test(tx),'cadastrado pelo extrato não entra no mapa (não se sabe o dia em que entrou)');
 ok(/Beatriz Teixeira[\s\S]*3 dias/.test(tx),'lista de atrasados mostra a Beatriz com 3 dias');
 await p.screenshot({path:'tests/saida/lab-mapa-prazos.png',fullPage:true});
 await p.click('[data-pzm=sai]');await p.waitForTimeout(200);
 // 5. desfazer
 p.once('dialog',d=>d.accept());await p.click('[data-act=pfxDesfaz]');await p.waitForTimeout(600);
 ok((await p.evaluate(()=>{var g=function(i){return PED.L.filter(function(x){return x.id===i;})[0];};return g('p1').status==='producao'&&!g('p1').arquivado&&!g('p1').finalizado_em&&g('p2').status==='finalizado'&&!g('p5').finalizado_em&&!PED.L.some(function(x){return x.paciente==='JOAO NOVO';});})),'desfazer volta tudo como era e apaga o cadastrado pela Ana');
 // 6. extrato que não dá para ler: cai na lista simples dos abertos
 await p.evaluate(()=>{S.tab.prot='financeiro';render();finAtual(Object.assign({},FIN.M[1],{extrato_path:'u-lab/extratos/2026-07/y.pdf'}));render();});await p.waitForTimeout(1800);
 ok(/Não consegui ler as linhas/.test(await p.$eval('#exb-ov',x=>x.innerText).catch(()=>''))&&(await p.$$eval('#exb-ov .pfx-i b',x=>x.map(y=>y.textContent).join('|')))==='Silvia','extrato sem leitura (Clínica B): mostra só os abertos da Clínica B');
 await p.click('#exb-ov [data-exb=fecha]');await p.waitForTimeout(400);
 // 6b. conferir todos os extratos já anexados, em fila
 await p.evaluate(()=>{FIN.M.push({id:'m0',cliente_id:'cA',ano:2026,mes:6,valor_mes:100,valor_componente:0,extrato_path:'u-lab/extratos/2026-06/z.pdf'});EXB.visto.m0=FIN.M[FIN.M.length-1].extrato_path;S.tab.prot='producao';render();});await p.waitForTimeout(300);
 const bt2=await p.$eval('[data-exb=todos]',x=>x.closest('.exb-ban').innerText).catch(()=>'');
 ok(/pedidos em aberto/.test(bt2)&&/2 clientes/.test(bt2),'tela de Pedidos avisa: pedidos abertos de clientes que já têm extrato → '+bt2.split('\n')[0]);
 await p.click('[data-exb=todos]');await p.waitForTimeout(1600);
 const cab=await p.$eval('#exb-ov .exb-s',x=>x.innerText).catch(()=>'');
 ok(/Clínica A/.test(cab)&&/Junho/.test(cab)&&/1 de 3/.test(cab),'fila começa pelo extrato mais antigo de cada cliente, com contador → '+cab);
 await p.click('#exb-ov [data-exb=para]');await p.waitForTimeout(500);ok(!(await p.$('#exb-ov')),'"Parar" fecha a fila');
 // 7. pedidos confirmados pelo cliente
 await p.evaluate(()=>{S.tab.prot='producao';render();});await p.waitForTimeout(300);
 let bn=await p.$eval('.rcb-ban',x=>x.innerText).catch(()=>'');
 ok(/1 pedido/.test(bn)&&/recebido pelo cliente/.test(bn),'tela de Pedidos avisa que 1 pedido foi confirmado pelo cliente');
 await p.click('[data-act=rcbAbre]');await p.waitForTimeout(200);ok(/Hugo Recebido/.test(await p.$eval('.rcb-ban',x=>x.innerText)),'mostra qual pedido');
 p.once('dialog',d=>d.accept());await p.click('[data-act=rcbVolta]');await p.waitForTimeout(400);
 ok((await p.evaluate(()=>{var x=PED.L.filter(y=>y.id==='p11')[0];return x.status==='finalizado'&&!x.arquivado&&!x.recebido_em;})),'"voltar ao quadro" devolve o pedido como estava antes (Pronto)');
 // celular
 await p.setViewportSize({width:390,height:844});await p.evaluate(()=>{PZM.on=true;render();});await p.waitForTimeout(300);
 ok((await p.evaluate(()=>document.documentElement.scrollWidth<=391)),'mapa no celular sem rolagem para o lado');
 await p.screenshot({path:'tests/saida/lab-mapa-prazos-cel.png',fullPage:true});
 ok(errs.length===0,'nenhum erro de JavaScript'+(errs.length?' → '+errs.join(' ; '):''));
 console.log(R.join('\n'));console.log(falhas?('\n'+falhas+' FALHA(S)'):'\nTUDO PASSOU ('+R.length+' conferências)');await b.close();process.exit(falhas?1:0);})();
