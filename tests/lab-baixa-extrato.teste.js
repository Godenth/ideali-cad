// Laboratório: ao anexar o extrato do mês, o sistema oferece dar baixa nos pedidos abertos daquele cliente;
// e mostra os pedidos que os clientes confirmaram como recebidos. Tudo com banco de mentira.
const {chromium}=require('playwright');let falhas=0;const R=[];const ok=(c,t)=>{R.push((c?'ok   ':'FALHOU ')+t);if(!c)falhas++;};
(async()=>{const b=await chromium.launch();const p=await b.newPage({viewport:{width:1366,height:850}});const errs=[];p.on('pageerror',e=>errs.push(e.message));
 await p.goto('http://localhost:8765/odonto/app/');await p.waitForTimeout(1300);
 await p.evaluate(()=>{window.UPD=[];
  var ch=function(t){var o={_t:t};['select','eq','order','limit','delete','upsert','neq','gte','lte','is','or','match','insert','range','not'].forEach(function(k){o[k]=function(){return o;};});
    o.update=function(pt){o._p=pt;return o;};o.in=function(c,ids){UPD.push({t:t,p:o._p,ids:ids});return o;};o.single=function(){return Promise.resolve({data:t==='odo_empresas'?Object.assign({},EMP.row,{dados:o._p&&o._p.dados}):null});};o.maybeSingle=o.single;
    o.then=function(f,r){if(o._p&&t==='odo_pedidos'&&!UPD.some(function(u){return u.p===o._p;}))UPD.push({t:t,p:o._p,ids:null});return Promise.resolve({data:[]}).then(f,r);};return o;};
  window.SB={from:function(t){return ch(t);},rpc:function(){return ch('rpc');},storage:{from:function(){return ch('st');}},channel:function(){return {on:function(){return this;},subscribe:function(){return this;}};}};
  RL.user={id:'u-lab'};RL.perfil={nome:'Lab',prof:'Protético'};S.role='prot';S.cad=Object.assign(S.cad||{},{nome:'Lab',ok:true});document.body.classList.add('rl-in');
  EMP.row={id:'emp1',dados:{}};EMP.cli=[{id:'cA',nome:'Clínica A',reg:1},{id:'cB',nome:'Clínica B',reg:2}];
  var P=function(id,n,cli,pac,st,criado,x){return Object.assign({id:id,numero:n,cliente_id:cli,paciente:pac,trabalho:'Coroa',status:st,arquivado:false,apagado:false,criado_em:criado,tipo:'cad'},x||{});};
  PED.L=[P('p1',1,'cA','Ana Antiga','producao','2026-09-10T12:00:00Z'),P('p2',2,'cA','Bia Outubro','finalizado','2026-10-20T12:00:00Z'),P('p3',3,'cA','Caio Fim do Mês','desenho','2026-10-30T12:00:00Z'),
         P('p4',4,'cA','Davi Novembro','producao','2026-11-05T12:00:00Z'),P('p5',5,'cB','Eva Outra Clínica','producao','2026-10-10T12:00:00Z'),
         P('p6',6,'cA','Fabi Já Entregue','entregue','2026-10-02T12:00:00Z',{arquivado:true}),P('p7',7,'cA','Gil Orçamento','orcamento','2026-10-03T12:00:00Z'),
         P('p8',8,'cB','Hugo Recebido','entregue','2026-11-01T12:00:00Z',{arquivado:true,recebido_em:new Date(Date.now()-3600e3).toISOString(),recebido_antes:'finalizado'})];
  PED.cad=[];PED.carregado=true;PED.erro='';
  FIN.M=[{id:'m1',cliente_id:'cA',ano:2026,mes:10,valor_mes:1000,valor_componente:0,extrato_path:null},{id:'m2',cliente_id:'cB',ano:2026,mes:10,valor_mes:500,valor_componente:0,extrato_path:null}];
  FIN.P=[];FIN.C=[];FIN.cfg={comissao_pct:10};FIN.ano=2026;FIN.mes=10;FIN.carregado=true;FIN.erro='';
  pedAtivo=function(){return true;};S.tab.prot='financeiro';render();});
 await p.waitForTimeout(300);
 ok(!(await p.$('#exb-ov'))&&!(await p.$('.exb-ban')),'sem extrato anexado, nada é oferecido');
 // anexa o extrato de outubro da Clínica A
 await p.evaluate(()=>{finAtual(Object.assign({},FIN.M[0],{extrato_path:'u-lab/extratos/2026-10/x.pdf'}));render();});await p.waitForTimeout(1200);
 ok(!!(await p.$('#exb-ov')),'anexou o extrato → abre a conferência sozinha');
 const nomes=await p.$$eval('#exb-ov .pfx-i b',x=>x.map(y=>y.textContent));
 ok(nomes.join('|')==='Ana Antiga|Bia Outubro|Caio Fim do Mês','lista só os pedidos abertos da Clínica A até o fim de outubro (não entra novembro, outro cliente, entregue nem orçamento) → '+nomes.join(', '));
 ok((await p.$$eval('#exb-ov input:checked',x=>x.length))===3,'todos já vêm marcados');
 await p.click('#exb-ov input[data-exbp=p3]');await p.waitForTimeout(150);
 ok(/Dar baixa em 2 pedidos/.test(await p.$eval('#exb-ov',x=>x.innerText)),'desmarcou o que ainda está sendo feito → botão diz 2 pedidos');
 await p.screenshot({path:'tests/saida/lab-baixa-extrato.png'});
 await p.click('#exb-ov [data-exb=vai]');await p.waitForTimeout(600);
 const u=await p.evaluate(()=>UPD.filter(x=>x.t==='odo_pedidos'));
 ok(u.length===1&&u[0].ids.join(',')==='p1,p2'&&u[0].p.status==='entregue'&&u[0].p.arquivado===true,'deu baixa só nos 2 marcados (entregue + arquivado)');
 ok((await p.evaluate(()=>PED.L.filter(x=>x.id==='p3')[0].status==='desenho'&&PED.L.filter(x=>x.id==='p5')[0].status==='producao')),'o desmarcado e o da outra clínica continuam como estavam');
 ok((await p.evaluate(()=>{var l=(EMP.row.dados||{}).lotes||[];return l.length===1&&l[0].n===2;})),'a baixa fica registrada para poder desfazer');
 ok(!(await p.$('#exb-ov')),'a conferência fecha');
 ok(/1 pedido/.test(await p.$eval('.exb-ban',x=>x.innerText).catch(()=>'')),'o que ficou aberto continua avisado no Financeiro (1 pedido)');
 // anexa o da Clínica B, fecha com "Agora não": nada muda
 await p.evaluate(()=>{finAtual(Object.assign({},FIN.M[1],{extrato_path:'u-lab/extratos/2026-10/y.pdf'}));render();});await p.waitForTimeout(1200);
 ok((await p.$$eval('#exb-ov .pfx-i b',x=>x.map(y=>y.textContent).join('|')))==='Eva Outra Clínica','extrato da Clínica B lista só o pedido da Clínica B');
 await p.click('#exb-ov [data-exb=fecha]');await p.waitForTimeout(500);
 ok((await p.evaluate(()=>UPD.filter(x=>x.t==='odo_pedidos').length))===1&&!(await p.$('#exb-ov')),'"Agora não" não altera nada');
 // pedidos confirmados pelo cliente
 await p.evaluate(()=>{pedAtivo=function(){return true;};S.tab.prot='producao';render();});await p.waitForTimeout(300);
 let bn=await p.$eval('.rcb-ban',x=>x.innerText).catch(()=>'');
 ok(/1 pedido/.test(bn)&&/recebido pelo cliente/.test(bn),'tela de Pedidos avisa que 1 pedido foi confirmado pelo cliente');
 await p.click('[data-act=rcbAbre]');await p.waitForTimeout(200);ok(/Hugo Recebido/.test(await p.$eval('.rcb-ban',x=>x.innerText)),'mostra qual pedido');
 await p.screenshot({path:'tests/saida/lab-recebidos.png'});
 p.once('dialog',d=>d.accept());await p.click('[data-act=rcbVolta]');await p.waitForTimeout(400);
 ok((await p.evaluate(()=>{var x=PED.L.filter(y=>y.id==='p8')[0];return x.status==='finalizado'&&!x.arquivado&&!x.recebido_em;})),'"voltar ao quadro" devolve o pedido como estava antes (Pronto)');
 ok(errs.length===0,'nenhum erro de JavaScript'+(errs.length?' → '+errs.join(' ; '):''));
 console.log(R.join('\n'));console.log(falhas?('\n'+falhas+' FALHA(S)'):'\nTUDO PASSOU ('+R.length+' conferências)');await b.close();process.exit(falhas?1:0);})();
