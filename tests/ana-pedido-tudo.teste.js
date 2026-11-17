// Ana entende o pedido escrito de uma vez (cliente, paciente, trabalho, dentes, cor).
// Rodar: (python3 -m http.server 8765 &) ; NODE_PATH=... node tests/ana-pedido-tudo.teste.js
const {chromium}=require('playwright');(async()=>{const b=await chromium.launch();const p=await b.newPage();let falhas=0;
await p.goto('http://localhost:8765/odonto/app/');await p.waitForTimeout(600);
const casos=[
 ["Paciente Daniel Freire Paulo Pagano Portese parcial Fixa, dentes 31 e 41, côr A4 em resina com carga ceramica",{cli:'Paulo Pagano',pac:'Daniel Freire',trab:'Prótese parcial fixa de Resina com carga cerâmica',d:[31,41],cor:'A4'}],
 ["Paulo Pagano, paciente Daniel Freire, PPF 31 e 41, A4",{cli:'Paulo Pagano',pac:'Daniel Freire',trab:'Prótese parcial fixa',d:[31,41],cor:'A4'}],
 ["Dr. Paulo Pagano paciente Maria Lima coroa do 11 A2",{cli:'Paulo Pagano',pac:'Maria Lima',trab:'Coroa',d:[11],cor:'A2'}],
 ["Orallis, paciente Maria, coroa do 11, A2",{cli:'Orallis',pac:'Maria',trab:'Coroa',d:[11],cor:'A2'}]];
// sem cliente na frase: guarda tudo e pergunta só o cliente (o paciente "Mario" não pode virar o cliente "Mario Andrade")
{const r=await p.evaluate(()=>{RL.user={id:'u'};EMP.cli=[{id:'c1',nome:'JOSE RICARDO',ativo:true},{id:'c2',nome:'Mario Andrade',ativo:true}];pclAbre();var E=PC.ed;PC.digitando=false;PC.fila=[];
  pcResposta('Paciente: Mario, coroa sobre dente unidade 12, em zirconia, cor: A3,5');var o={passo:PC.passo,cli:E.cli&&E.cli.nome,pac:E.paciente,trab:E.trabalho,d:E.dentes};PC.digitando=false;PC.fila=[];pcResposta('id:c1');o.depois=E.cli&&E.cli.nome;o.passo2=PC.passo;PC.busy=false;pcFecha();return o;});
 const ok=r.passo==='cliente'&&!r.cli&&r.pac==='Mario'&&r.trab==='Coroa de Zircônia'&&r.d.join()==='12'&&r.depois==='JOSE RICARDO'&&r.passo2==='prazo';if(!ok)falhas++;console.log(ok?'ok  ':'FALHOU','sem cliente na frase',ok?'':JSON.stringify(r));}
// nome do paciente sem a palavra "paciente", antes do nome do cliente
{const r=await p.evaluate(()=>{RL.user={id:'u'};EMP.cli=[{id:'c9',nome:'Luiz Carlos Moreira (Prime Medicina e Odontologia)',ativo:true},{id:'c2',nome:'Orallis',ativo:true}];pclAbre();var E=PC.ed;PC.digitando=false;PC.fila=[];
  pcResposta('luizmar schroeder DR LUIZ MOREIRA DENTE 11 SPBRE IMPLANTE Gran morse 3.5x8 cor a1');var o={cli:E.cli&&E.cli.nome,pac:E.paciente,d:E.dentes,cor:E.cor,passo:PC.passo};PC.busy=false;pcFecha();return o;});
 const ok=/Luiz Carlos Moreira/.test(r.cli||'')&&r.pac==='Luizmar Schroeder'&&r.d.join()==='11'&&r.cor==='A1'&&r.passo!=='paciente';if(!ok)falhas++;console.log(ok?'ok  ':'FALHOU','paciente sem a palavra paciente',ok?'':JSON.stringify(r));}
// trabalho escrito sem cliente: não pode chutar um cliente parecido (ex.: LUCAS RODRIGUES)
{const r=await p.evaluate(()=>{RL.user={id:'u'};EMP.cli=[{id:'l',nome:'LUCAS RODRIGUES',ativo:true},{id:'p',nome:'Paulo Pagano',ativo:true}];pclAbre();var E=PC.ed;PC.digitando=false;PC.fila=[];
  pcResposta('confecção de placa de bruxismo acrílica com guias canina e incisiva superior');var o={passo:PC.passo,cli:E.cli&&E.cli.nome,trab:E.trabalho};PC.busy=false;pcFecha();return o;});
 const ok=r.passo==='cliente'&&!r.cli&&/Placa de bruxismo/.test(r.trab);if(!ok)falhas++;console.log(ok?'ok  ':'FALHOU','placa de bruxismo sem cliente',ok?'':JSON.stringify(r));}
// nome que serve para mais de um cliente: pergunta qual
{const r=await p.evaluate(()=>{RL.user={id:'u'};EMP.cli=[{id:'a',nome:'Dr. Eduardo de Mello Caprio',ativo:true},{id:'b',nome:'Eduardo Santos',ativo:true}];pclAbre();PC.digitando=false;PC.fila=[];pcResposta('eduardo');var o={passo:PC.passo,n:(PC.ed._opc||[]).length};PC.busy=false;pcFecha();return o;});
 const ok=r.passo==='cliente'&&r.n===2;if(!ok)falhas++;console.log(ok?'ok  ':'FALHOU','dois Eduardos',ok?'':JSON.stringify(r));}
// "Nome:" é o paciente; "Souza" sozinho não pode virar o cliente Alexandre Miranda Souza; cor BL1 com travessão; "23 barra square" = obs
{const r=await p.evaluate(()=>{RL.user={id:'u'};EMP.cli=[{id:'a',nome:'Alexandre Miranda Souza',ativo:true},{id:'p',nome:'Paulo Pagano',ativo:true}];pclAbre();PC.digitando=false;PC.fila=[];
  pcResposta('Nome: Antonio Claudio De Souza Mendes cor – BL1 coroa emax 23 barra square');var E=PC.ed,o={passo:PC.passo,cli:E.cli&&E.cli.nome,pac:E.paciente,trab:E.trabalho,d:E.dentes,cor:E.cor,obs:E.obs};PC.busy=false;pcFecha();return o;});
 const ok=r.passo==='cliente'&&!r.cli&&r.pac==='Antonio Claudio de Souza Mendes'&&r.trab==='Coroa de E.max'&&r.d.join()==='23'&&r.cor==='BL1'&&r.obs==='Square';if(!ok)falhas++;console.log(ok?'ok  ':'FALHOU','Nome: … BL1 … barra square',ok?'':JSON.stringify(r));}
for(const [v,esp] of casos){const r=await p.evaluate(v=>{RL.user={id:'u'};EMP.cli=[{id:'c1',nome:'Paulo Pagano',ativo:true},{id:'c2',nome:'Orallis',ativo:true}];pclAbre();pclTudo(v);var E=PC.ed,o={cli:E.cli&&E.cli.nome,pac:E.paciente,trab:E.trabalho,d:E.dentes,cor:E.cor};PC.busy=false;pcFecha();return o;},v);
 const ok=JSON.stringify(r)===JSON.stringify(esp);if(!ok)falhas++;console.log(ok?'ok  ':'FALHOU',v,ok?'':'\n   veio '+JSON.stringify(r));}
console.log(falhas?falhas+' falha(s)':'tudo certo');await b.close();process.exit(falhas?1:0);})();
