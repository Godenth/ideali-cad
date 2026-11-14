// Rede · Cursos e lives (protótipo sem banco): aluno, professor e aprovação. Rode com o servidor local na porta 8765.
const {chromium}=require('playwright');const path=require('path');let falhas=0;const R=[];const ok=(c,t)=>{R.push((c?'ok   ':'FALHOU ')+t);if(!c)falhas++;};
const DIR=process.argv[2]||path.join(__dirname,'dados'),SAIDA=path.join(__dirname,'saida');
(async()=>{const b=await chromium.launch();const p=await b.newPage({viewport:{width:1440,height:900}});const errs=[];p.on('pageerror',e=>errs.push(e.message));p.on('dialog',d=>d.accept(d.type()==='prompt'?'Áudio ruim':undefined));
 await p.goto('http://localhost:8765/odonto/app/');await p.waitForTimeout(1000);
 await p.evaluate(()=>{try{localStorage.clear();}catch(e){}document.documentElement.setAttribute('data-theme','light');if(!S.dent)S.dent=dCarrega()||dSeed('Carla');S.role='dent';RL.admin=true;S.redeOn=true;S.rede.sec='cursos';CUR.d=null;CUR.v='explorar';render();});
 await p.waitForTimeout(500);
 ok(/Cursos e lives/.test(await p.$eval('.rs-menu',x=>x.innerText)),'menu da Rede mostra "Cursos e lives"');
 ok((await p.$$eval('.cu-card',x=>x.length))>=3&&/Próximas lives/.test(await p.$eval('.cu',x=>x.innerText)),'Explorar: prateleiras de cursos e próximas lives (exemplos marcados)');
 await p.screenshot({path:path.join(SAIDA,'cursos-1-explorar.png')});
 // aluno
 await p.click('.cu-card[data-v=ex2]');await p.waitForTimeout(300);
 ok(/Maquiagem em zircônia/.test(await p.$eval('.cu-top',x=>x.innerText))&&(await p.$$eval('.cu-lock',x=>x.length))===2,'página do curso: aulas pagas com cadeado antes de se inscrever');
 await p.click('[data-cu=insc]');await p.waitForTimeout(300);
 ok((await p.$$eval('.cu-lock',x=>x.length))===0&&!!(await p.$('.cu-player')),'inscrito: libera as aulas e abre o player');
 for(let i=0;i<3;i++){await p.click('.cu-pl-b [data-cu=feito]');await p.waitForTimeout(200);}
 ok(/100%/.test(await p.$eval('.cu-ring',x=>x.innerText)),'marcou as 3 aulas: 100% concluído');
 await p.fill('#cu-pt','Qual glaze vocês usam?');await p.click('[data-cu=perg]');await p.waitForTimeout(200);
 ok(/Qual glaze/.test(await p.$eval('.cu-perg',x=>x.innerText)),'pergunta ao professor aparece');
 await p.screenshot({path:path.join(SAIDA,'cursos-2-curso.png'),fullPage:true});
 await p.click('.cu-prog [data-cu=cert]');await p.waitForTimeout(300);ok(/CERTIFICADO/.test(await p.$eval('#cu-cert',x=>x.innerText))&&/Maquiagem em zircônia/.test(await p.$eval('#cu-cert',x=>x.innerText)),'certificado de conclusão');
 await p.screenshot({path:path.join(SAIDA,'cursos-3-certificado.png')});
 // professor
 await p.click('.cu-abas [data-v=ensinar]');await p.waitForTimeout(200);await p.click('[data-cu=novo]');await p.waitForTimeout(200);
 await p.fill('[data-cuf=titulo]','Exocad: protocolo sobre implante');await p.selectOption('[data-cuf=esp]','CAD/CAM');await p.fill('[data-cuf=desc]','Do escaneamento ao desenho final do protocolo.');
 await p.setInputFiles('[data-cu-capa]',path.join(DIR,'capa-teste.jpg'));await p.waitForTimeout(500);
 await p.fill('.cu-ela input[data-cua$="|t"]','Planejamento');
 await p.setInputFiles('.cu-ela [data-cu-vid]',path.join(DIR,'aula-teste.mp4'));await p.waitForTimeout(1500);
 const vi=await p.$eval('.cu-vinfo',x=>x.innerText).catch(()=>'');ok(/1080p/.test(vi)&&/2 min/.test(vi),'vídeo enviado: lê resolução e duração do arquivo → '+vi);
 await p.click('[data-cu=a-nova]');await p.waitForTimeout(200);await p.fill('.cu-ela li:nth-child(2) input[data-cua$="|t"]','Desenho da barra');
 await p.click('.cu-ela li:nth-child(2) [data-cu=a-sobe]');await p.waitForTimeout(200);
 ok((await p.$eval('.cu-ela li:first-child input[data-cua$="|t"]',x=>x.value))==='Desenho da barra','reordenar aulas');
 ok(!!(await p.$('.cu-capa-ed img')),'capa enviada aparece');
 await p.screenshot({path:path.join(SAIDA,'cursos-4-editor.png'),fullPage:true});
 await p.click('[data-cu=ed-envia]');await p.waitForTimeout(300);
 ok(/Em análise/.test(await p.$eval('.cu',x=>x.innerText)),'enviado: fica "Em análise" e não aparece no Explorar');
 // live
 await p.click('[data-cu=lv-novo]');await p.waitForTimeout(200);await p.fill('[data-cul=titulo]','Live: dúvidas de protocolo');
 await p.fill('[data-cul=quando]','2026-12-02T19:30');await p.fill('[data-cul=link]','https://meet.google.com/abc-defg-hij');await p.click('[data-cu=lv-envia]');await p.waitForTimeout(300);
 // aprovação
 await p.click('.cu-abas [data-v=aprovar]');await p.waitForTimeout(200);
 ok((await p.$$eval('[data-cu=aprova]',x=>x.length))===2,'Aprovar: curso e live esperando');
 await p.screenshot({path:path.join(SAIDA,'cursos-5-aprovar.png')});
 await p.click('[data-cu=aprova][data-v^="c|"]');await p.waitForTimeout(200);await p.click('[data-cu=recusa]');await p.waitForTimeout(300);
 await p.click('.cu-abas [data-v=explorar]');await p.waitForTimeout(200);
 ok(/Exocad: protocolo sobre implante/.test(await p.$eval('.cu',x=>x.innerText)),'aprovado: aparece no Explorar para todos');
 await p.click('.cu-abas [data-v=ensinar]');await p.waitForTimeout(200);ok(/Recusado/.test(await p.$eval('.cu',x=>x.innerText))&&/Áudio ruim/.test(await p.$eval('.cu',x=>x.innerText)),'live recusada mostra o motivo ao professor');
 await p.screenshot({path:path.join(SAIDA,'cursos-6-ensinar.png'),fullPage:true});
 // continua depois de recarregar
 await p.reload();await p.waitForTimeout(1000);await p.evaluate(()=>{if(!S.dent)S.dent=dCarrega()||dSeed('Carla');S.role='dent';S.redeOn=true;S.rede.sec='cursos';CUR.v='meus';render();});await p.waitForTimeout(300);
 ok(/Maquiagem em zircônia/.test(await p.$eval('.cu',x=>x.innerText)),'depois de recarregar, "Meus cursos" continua com o curso concluído');
 // celular
 await p.setViewportSize({width:390,height:844});await p.evaluate(()=>{CUR.v='explorar';render();});await p.waitForTimeout(300);
 const larg=await p.evaluate(()=>{var o=[];document.querySelectorAll('body *').forEach(function(e){var r=e.getBoundingClientRect();if(r.right>392&&r.width>0)o.push((e.className||e.tagName)+' '+Math.round(r.right));});var a=document.querySelector('.cu'),c=[];while(a&&a!==document.body){c.push((a.className||a.tagName).toString().slice(0,30)+':'+Math.round(a.getBoundingClientRect().width)+':'+getComputedStyle(a).display);a=a.parentElement;}return [document.documentElement.scrollWidth,c.join(' < ')];});ok(larg[0]<=391,'celular sem rolagem para o lado'+(larg[0]>391?' → '+larg[1]:''));
 await p.screenshot({path:path.join(SAIDA,'cursos-7-celular.png'),fullPage:true});
 ok(errs.length===0,'nenhum erro de JavaScript'+(errs.length?' → '+errs.join(' ; '):''));
 console.log(R.join('\n'));console.log(falhas?('\n'+falhas+' FALHA(S)'):'\nTUDO PASSOU ('+R.length+' conferências)');await b.close();process.exit(falhas?1:0);})();
