// Exporta dados reais da 021 Barra + confere o rateio (regra final: todos os pedidos no mês fechado).
const {execFileSync}=require('child_process');const fs=require('fs');
const CLI='C:\\Users\\CLIENTE\\AppData\\Local\\supabase-cli\\supabase.exe';
const C='f8e23d0c-5f1f-4bba-b6c4-8d8b07984f0a',LAB='0e669d45-90e2-4397-9c1e-95433ae3b5aa';
function q(sql){const out=execFileSync(CLI,['db','query','--linked',sql,'-o','json'],{encoding:'utf8',maxBuffer:64*1024*1024});const i=out.indexOf('[');return JSON.parse(out.slice(i));}
function norm(s){return String(s||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9 ]+/g,' ').replace(/\s+/g,' ').trim();}
function preco(p){const s=norm((p.trabalho||'')+' '+(p.material||''));if(/barra|protocolo|modelagem/.test(s))return null;if(s.indexOf('emax')>=0||s.indexOf('e max')>=0||s.indexOf('dissilicato')>=0)return 380;if(s.indexOf('zirconia')>=0)return 324.5;return null;}
const ped=q(`select id,numero,paciente,trabalho,material,dentes,qtd,valor,status,enviado_inove,em_maquiagem,desenho_feito,cor,criado_em from public.odo_pedidos where cliente_id='${C}' and envio_id is null and apagado is not true and status not in ('orcamento','cancelado') order by criado_em`);
const mes=q(`select m.ano,m.mes,m.valor_mes,coalesce(sum(p.valor),0) as pago from public.odo_fin_meses m left join public.odo_fin_pagamentos p on p.mes_id=m.id where m.cliente_id='${C}' and m.ano=2026 group by m.ano,m.mes,m.valor_mes order by m.mes`);
const F={};mes.forEach(m=>{F[m.ano+'-'+m.mes]=(F[m.ano+'-'+m.mes]||0)+(+m.valor_mes||0);});
const G={};ped.forEach(p=>{const d=new Date(p.criado_em);const k=d.getFullYear()+'-'+(d.getMonth()+1);(G[k]=G[k]||[]).push(p);});
const VAL={};let semMapa={};
Object.keys(G).sort().forEach(k=>{const cl=F[k];if(cl==null)return;const L=G[k];
  const ws=L.map(p=>{if(p.valor!=null)return +p.valor;const pr=preco(p);if(pr==null){semMapa[p.trabalho+' | '+(p.material||'')]=(semMapa[p.trabalho+' | '+(p.material||'')]||0)+1;return null;}return Math.round(pr*(+p.qtd||(p.dentes||[]).length||1)*100)/100;});
  const pos=ws.filter(w=>w!=null&&w>0),avg=pos.length?pos.reduce((s,w)=>s+w,0)/pos.length:1,fw=ws.map(w=>w==null?avg:w),sumW=fw.reduce((s,w)=>s+w,0)||1,closure=Math.round(cl*100)/100;let acc=0,sum=0;
  L.forEach((p,i)=>{const v=i===L.length-1?Math.round((closure-acc)*100)/100:Math.round(closure*fw[i]/sumW*100)/100;acc+=v;sum+=v;VAL[p.id]=v;});
  console.log(k+': fechamento '+closure.toFixed(2)+' · soma '+(Math.round(sum*100)/100).toFixed(2)+(Math.abs(sum-closure)<0.006?' OK':' DIFERENTE'));
});
function etapa(p){if(p.status==='entregue')return 'Entregue';if(p.status==='finalizado')return 'Pronto';if(p.status==='aguardando')return 'Aguardando informação';if(p.status==='producao')return p.em_maquiagem?'Maquiagem':(p.enviado_inove?'Enviado para fresagem':'Em produção');return p.desenho_feito?'Desenhado':'Desenho CAD';}
const agosto=ped.filter(p=>new Date(p.criado_em).getFullYear()===2026&&new Date(p.criado_em).getMonth()===7);
const man=agosto.filter(p=>p.numero===623)[0];
const comSalvo=agosto.filter(p=>p.valor!=null)[0];
const semSalvo=agosto.filter(p=>p.valor==null&&p.numero!==623)[0];
function linha(p){return p?('#'+p.numero+' '+p.paciente+' · '+p.trabalho+' · salvo='+(p.valor==null?'—':p.valor)+' → R$ '+VAL[p.id].toFixed(2)):'(nao achou)';}
console.log('\nManuella: '+linha(man));
console.log('Agosto com valor salvo: '+linha(comSalvo));
console.log('Agosto sem valor salvo: '+linha(semSalvo));
const nomes=Object.keys(semMapa);console.log('\nNomes sem ligação: '+nomes.length+' (pedidos '+Object.keys(semMapa).reduce((s,k)=>s+semMapa[k],0)+')');nomes.sort((a,b)=>semMapa[b]-semMapa[a]).forEach(k=>console.log('  '+semMapa[k]+'x  '+k));
const pedidos=ped.map(p=>({id:p.id,envio:null,lab_id:LAB,lab:'Ideali Lab',paciente:p.paciente,trabalho:p.trabalho,material:p.material,dentes:p.dentes||[],qtd:p.qtd,valor:p.valor==null?null:+p.valor,_est:false,status:p.status,enviado_inove:p.enviado_inove,em_maquiagem:p.em_maquiagem,cor:p.cor,criado:p.criado_em,etapa:etapa(p),aberto:['desenho','producao','aguardando'].indexOf(p.status)>=0}));
const meses=mes.map(m=>{const valor=+m.valor_mes,pago=+m.pago,falta=Math.max(0,Math.round((valor-pago)*100)/100);return {lab_id:LAB,lab:'Ideali Lab',ano:m.ano,mes:m.mes,valor:valor,pago:pago,falta:falta,credito:0,situacao:pago>=valor-0.005?'pago':pago>0?'parcial':'aberto',pagamentos:[],extrato:null};});
fs.writeFileSync('tests/saida/real-021barra.json',JSON.stringify({pedidos:pedidos,meses:meses,manuella:man},null,0));
console.log('\nexportado tests/saida/real-021barra.json');
