// Teste visual da dashboard do Financeiro (clínica/dentista) com banco falso.
// Roda o código real da tela; só o servidor é trocado. Salva prints desktop e celular.
const {chromium,devices}=require('playwright');
const SEED=`(function(){
  var ch=function(){var o={};['select','eq','in','order','limit','update','delete','upsert','neq','gte','lte','is','or','match','insert','ilike','like'].forEach(function(k){o[k]=function(){return o;};});o.single=function(){return Promise.resolve({data:null});};o.maybeSingle=o.single;o.then=function(f,r){return Promise.resolve({data:[]}).then(f,r);};return o;};
  window.SB={from:ch,rpc:ch,storage:{from:function(){var o=ch();o.createSignedUrls=function(){return Promise.resolve({data:[]});};return o;}},channel:function(){return {on:function(){return this;},subscribe:function(){return this;}};}};
  RL.user={id:'u1',email:'contato.021barra@gmail.com'};RL.perfil={nome:'Fernando',prof:'Dentista'};S.role='dent';S.cad=Object.assign(S.cad||{},{nome:'Fernando',prof:'Dentista',ok:true});S.redeOn=false;document.body.classList.add('rl-in');
  labVMeus=function(){return [{id:'v1',status:'aceito',lab_id:'l1',lab_nome:'Ideali Lab'}];};
  try{if(typeof UNI!=='undefined'){UNI.ok=true;UNI.dono=true;UNI.voando=null;}}catch(e){}
  try{PH.d=[];PH.carregando=false;PH.erro='';}catch(e){}
  var months=[5,6,7,8,9,10].map(function(m){var v={5:1208.5,6:5230,7:2772,8:6406,9:6646,10:4534}[m];return {lab_id:'l1',lab:'Ideali Lab',ano:2026,mes:m,valor:v,pago:v,falta:0,credito:0,situacao:'pago',pagamentos:[],extrato:null};});
  var pac=['Valnice Nery','Rafael Quintana Pinto','Maria Isabel Gomes','Alberto Rocha de Oliveira','Saullo Ferreira','William Souza','Iaramara Lima','Fabiana Alves','Leonardo Frota','Andreia Flores','Fernando Lopes','Beatriz Nunes'];
  var tipos=[['Coroa de zircônia','Zircônia'],['Coroa de E.max','E.max'],['Protocolo zircônia','Zircônia'],['Faceta E.max','E.max'],['Modelagem 3D','Resina'],['Ponte de zircônia','Zircônia'],['Coroa sobre implante','Zircônia'],['Onlay E.max','E.max']];
  var teeth=[11,12,13,14,15,16,17,21,22,23,24,25,26,27,36,37,46,47];
  var s=7;function r(n){s=(s*9301+49297)%233280;return Math.floor(s/233280*n);}
  var F=[];
  for(var i=0;i<120;i++){
    var d;
    if(i<10){d=new Date(2026,10,1+r(26));}            // novembro (mês atual)
    else {var mo=1+r(9);d=new Date(2026,mo-1,1+r(27));} // jan a out
    var tp=tipos[r(tipos.length)],ds=[];
    var q=1+r(3);for(var j=0;j<q;j++){var t=teeth[r(teeth.length)];if(ds.indexOf(t)<0)ds.push(t);}
    var val=280+r(1200);val=Math.round(val*100)/100;
    var st,et,ab;
    if(i<10){var k=i%5;st=k<2?'desenho':k<4?'producao':'finalizado';et=k<2?'Desenho CAD':k===2?'Enviado para fresagem':k===3?'Maquiagem':'Pronto';ab=st!=='finalizado';}
    else{st='entregue';et='Entregue';ab=false;}
    F.push({id:'lab-'+i,envio:null,lab_id:'l1',lab:'Ideali Lab',paciente:pac[r(pac.length)],trabalho:tp[0],material:tp[1],dentes:ds,qtd:ds.length,valor:val,_est:false,status:st,enviado_inove:st==='producao'&&i%2===0,em_maquiagem:et==='Maquiagem',cor:['A2','A3','BL2','A3,5'][r(4)],criado:d.toISOString(),finalizado_em:null,entregue_em:null,etapa:et,aberto:ab});
  }
  PDG.L=[];PDG.carregado=true;DFL.d={pedidos:F,meses:months};DFL.erro='';DFL.carregando=false;
  S.tab.dent='pedidos';S.labSub='fin';render();
})();`;
(async()=>{
  const b=await chromium.launch();const out=[];
  const casos=[['pc-escuro',{viewport:{width:1440,height:900},colorScheme:'dark'}],['cel-claro',Object.assign({},devices['Pixel 7'],{colorScheme:'light'})]];
  for(const [nm,opt] of casos){
    const c=await b.newContext(opt);const p=await c.newPage();const errs=[];p.on('pageerror',e=>errs.push(e.message));
    await p.goto('http://localhost:8765/odonto/app/');await p.waitForTimeout(1400);
    await p.evaluate(SEED);await p.waitForTimeout(600);
    const cards=await p.$$eval('.pdb-kc b',a=>a.map(x=>x.textContent.trim())).catch(()=>[]);
    const overflow=await p.evaluate(()=>document.documentElement.scrollWidth-document.documentElement.clientWidth);
    out.push(nm+' cards: '+cards.join(' | '));
    out.push(nm+' overflow: '+overflow+'px · erros JS: '+(errs.length?errs.join(' ; '):'nenhum'));
    await p.screenshot({path:'tests/saida/dash-fin-'+nm+'.png',fullPage:true});
    // rola até os rankings para um segundo print
    await p.evaluate(()=>{var e=document.querySelector('.pdb-g2');if(e)e.scrollIntoView({block:'start'});});
    await p.waitForTimeout(300);
    await p.screenshot({path:'tests/saida/dash-fin-'+nm+'-rank.png'});
    await c.close();
  }
  console.log(out.join('\n'));await b.close();
})();
