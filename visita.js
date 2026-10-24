/* Ideali CAD · contagem de visitas do site (agregada por dia, página e origem).
   Sem cookie, sem IP e sem identificador: só "mais uma visita nesta página hoje, vinda do Google".
   Conta uma vez por página por sessão do navegador. Chave pública (anon), a mesma do app. */
(function(){
  var URL_SB='https://qxspiaqaigjkmilxxfri.supabase.co',K='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InF4c3BpYXFhaWdqa21pbHh4ZnJpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE2MjYwMzMsImV4cCI6MjEwNzIwMjAzM30.TeIHiEvHx1PmvS5PQ3lzvByYP9ppYuq5GLZURtutXc0';
  function origem(){try{var q=new URLSearchParams(location.search),u=(q.get('utm_source')||'').toLowerCase();
    if(q.get('fbclid'))u=u||'facebook';if(q.get('gclid'))u=u||'google';
    if(u){if(/insta|\big\b/.test(u))return 'instagram';if(/face|fb|meta/.test(u))return 'facebook';if(/google|gads/.test(u))return 'google';if(/whats|wa/.test(u))return 'whatsapp';return u.replace(/[^a-z0-9_]/g,'').slice(0,20)||'outro';}
    var r=document.referrer||'';if(!r)return 'direto';var h=new URL(r).hostname;
    if(/idealisystems|github\.io/.test(h))return 'interno';if(/google\./.test(h))return 'google';if(/instagram/.test(h))return 'instagram';if(/facebook|fb\.|messenger/.test(h))return 'facebook';if(/whatsapp|wa\.me/.test(h))return 'whatsapp';if(/youtube/.test(h))return 'youtube';if(/bing|yahoo|duckduckgo/.test(h))return 'busca';return 'outro';}catch(e){return 'outro';}}
  function conta(pg,uma){try{var k='iv_'+pg;if(uma!==false){if(sessionStorage.getItem(k))return;sessionStorage.setItem(k,'1');}}catch(e){}
    try{fetch(URL_SB+'/rest/v1/rpc/registrar_visita',{method:'POST',keepalive:true,headers:{apikey:K,Authorization:'Bearer '+K,'Content-Type':'application/json'},body:JSON.stringify({pagina:pg,origem:origem()})}).catch(function(){});}catch(e){}}
  window.idealiVisita=conta;
  var p=location.pathname.replace(/\/+$/,'/'),M={'/':'inicio','/index.html':'inicio','/tour.html':'tour','/rede.html':'rede','/privacidade.html':'privacidade','/termos.html':'termos'};
  var pg=window.IDEALI_PAGINA||M[p]||(/^\/c\//.test(p)?'captura':/^\/app\//.test(p)?'app':null);
  if(pg)conta(pg);
})();
