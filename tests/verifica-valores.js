// Verifica o rateio do fechamento com os dados reais da 021 Barra (somente leitura).
const {execFileSync}=require('child_process');
const CLI='C:\\Users\\CLIENTE\\AppData\\Local\\supabase-cli\\supabase.exe';
const C='f8e23d0c-5f1f-4bba-b6c4-8d8b07984f0a';
function q(sql){const out=execFileSync(CLI,['db','query','--linked',sql,'-o','json'],{encoding:'utf8',maxBuffer:64*1024*1024});const i=out.indexOf('[');return JSON.parse(out.slice(i));}
function norm(s){return String(s||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9 ]+/g,' ').replace(/\s+/g,' ').trim();}
const NOMES=[['e max',0],['emax',0],['coroa de e max',0],['coroa e max',0],['zirconia',1],['coroa zirconia',1],['coroa de zirconia',1]];
const PRECO=[380,324.5];
function preco(p){const t=norm(p.trabalho),m=norm(p.material);for(const [n,i] of NOMES){if(n===t||n===m)return PRECO[i];}return null;}
const ped=q(`select id,paciente,trabalho,material,dentes,qtd,valor,status,criado_em from public.odo_pedidos where cliente_id='${C}' and envio_id is null and apagado is not true and status not in ('orcamento','cancelado') order by criado_em`);
const mes=q(`select ano,mes,valor_mes from public.odo_fin_meses where cliente_id='${C}' and ano=2026 order by mes`);
const F={};mes.forEach(m=>{F[m.ano+'-'+m.mes]=(F[m.ano+'-'+m.mes]||0)+(+m.valor_mes||0);});
const G={};ped.forEach(p=>{const d=new Date(p.criado_em);const k=d.getFullYear()+'-'+(d.getMonth()+1);(G[k]=G[k]||[]).push(p);});
let semMapa={};
Object.keys(G).sort().forEach(k=>{
  const L=G[k],cl=F[k];if(cl==null){return;}
  let saved=0,uns=[];L.forEach(p=>{(p.valor!=null? saved+=+p.valor : uns.push(p));});
  const ws=uns.map(p=>{const pr=preco(p);if(pr==null){semMapa[p.trabalho+' | '+(p.material||'')]=(semMapa[p.trabalho+' | '+(p.material||'')]||0)+1;return null;}return Math.round(pr*(+p.qtd||(p.dentes||[]).length||1)*100)/100;});
  const pos=ws.filter(w=>w!=null&&w>0),avg=pos.length?pos.reduce((s,w)=>s+w,0)/pos.length:1,fw=ws.map(w=>w==null?avg:w),sumW=fw.reduce((s,w)=>s+w,0)||1,rem=Math.max(0,Math.round((cl-saved)*100)/100);
  let acc=0,dist=0;uns.forEach((p,i)=>{const v=i===uns.length-1?Math.round((rem-acc)*100)/100:Math.round(rem*fw[i]/sumW*100)/100;acc+=v;dist+=v;});
  console.log(k+': fechamento '+cl.toFixed(2)+' · salvos '+saved.toFixed(2)+' · rateio '+dist.toFixed(2)+' · total '+(saved+dist).toFixed(2)+' · pedidos '+L.length+' (sem preço '+uns.length+')');
});
console.log('\nNomes sem ligação (contagem):');
Object.keys(semMapa).sort((a,b)=>semMapa[b]-semMapa[a]).forEach(k=>console.log('  '+semMapa[k]+'x  '+k));
