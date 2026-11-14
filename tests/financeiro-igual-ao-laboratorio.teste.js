// Prova que o banco (odo_fin_mes_resumo, 075) calcula a situação do mês IGUAL à tela Financeiro do laboratório.
// 1) psql -f tests/sql/gera_financeiro_aleatorio.sql   (gera /tmp/.../fin.json com dados aleatórios + resposta do banco)
// 2) node tests/financeiro-igual-ao-laboratorio.teste.js [caminho do fin.json]
const fs=require('fs'),path=require('path');
const arq=process.argv[2]||'/tmp/claude-0/t/f2/fin.json';const D=JSON.parse(fs.readFileSync(arq,'utf8'));
const h=fs.readFileSync(path.join(__dirname,'../odonto/app/index.html'),'utf8');
const linha=ini=>{const i=h.indexOf(ini);if(i<0)throw new Error('não achei: '+ini);return h.slice(i,h.indexOf('\n',i));};
// as funções de verdade da tela do laboratório
const src=['function finCliK(','function finPags(','function finPago(','function finAnt(','function finRest(','function finPagoTela(','function finFaltaTela(','function finSt(','finRest=function(','function finCredAtivo('].map(linha).join('\n');
const FIN={M:D.M||[],P:D.P||[]};
const f=new Function('FIN',src+';return {finPago,finRest,finPagoTela,finFaltaTela,finSt,finCredAtivo};')(FIN);
let n=0,dif=[];const perto=(a,b)=>Math.abs((+a)-(+b))<0.006;
for(const m of FIN.M){const r=D.R[m.id];n++;
  const js={pago:f.finPago(m),credito:f.finCredAtivo(m),pago_total:f.finPagoTela(m),falta:f.finFaltaTela(m),situacao:f.finSt(m)[0]};
  const ok=perto(js.pago,r.pago)&&perto(js.credito,r.credito)&&perto(js.pago_total,r.pago_total)&&perto(js.falta,r.falta)&&js.situacao===r.situacao;
  if(!ok)dif.push({mes:m.ano+'-'+m.mes,valor:m.valor_mes,quitado:m.quitado,abater:m.abater_credito,tela:js,banco:r});}
const sit={};FIN.M.forEach(m=>{const s=D.R[m.id].situacao;sit[s]=(sit[s]||0)+1;});
console.log('meses comparados: '+n+' · pagamentos: '+FIN.P.length+' · situações: '+JSON.stringify(sit)+' · com crédito: '+FIN.M.filter(m=>+D.R[m.id].credito>0).length);
if(dif.length){console.log('DIFERENTES: '+dif.length);console.log(JSON.stringify(dif.slice(0,3),null,1));process.exit(1);}
console.log('TUDO IGUAL: o banco e a tela do laboratório dão o mesmo resultado nos '+n+' meses');
