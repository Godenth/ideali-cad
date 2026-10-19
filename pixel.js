/* Ideali CAD · Pixel do Meta com consentimento (LGPD).
   O Pixel só carrega depois que a pessoa clica em "Aceitar" no aviso de cookies.
   Para ligar: coloque o ID do seu Pixel em PIXEL_ID (Gerenciador de Eventos do Meta → Fontes de dados). */
(function(){
  var PIXEL_ID = window.IDEALI_PIXEL_ID || ''; // ex.: '123456789012345' (a página de captura informa o Pixel do próprio dono)
  var CHAVE = 'ideali_cookies'; // 'sim' | 'nao'
  function le(){ try { return localStorage.getItem(CHAVE); } catch(e){ return null; } }
  function grava(v){ try { localStorage.setItem(CHAVE, v); } catch(e){} }
  var naApp = /\/app\//.test(location.pathname);
  function carrega(semPageView){
    if (!PIXEL_ID || window.fbq) return;
    !function(f,b,e,v,n,t,s){if(f.fbq)return;n=f.fbq=function(){n.callMethod?n.callMethod.apply(n,arguments):n.queue.push(arguments)};
      if(!f._fbq)f._fbq=n;n.push=n;n.loaded=!0;n.version='2.0';n.queue=[];t=b.createElement(e);t.async=!0;
      t.src=v;s=b.getElementsByTagName(e)[0];s.parentNode.insertBefore(t,s)}(window,document,'script','https://connect.facebook.net/en_US/fbevents.js');
    window.fbq('set', 'autoConfig', false, PIXEL_ID);
    window.fbq('init', PIXEL_ID);
    if (!semPageView) window.fbq('track', 'PageView');
  }
  // Evento para o sistema chamar no momento do cadastro (só envia se a pessoa aceitou).
  // Dentro do sistema o Pixel nunca carrega sozinho nem registra visitas de tela: só este evento, na tela de cadastro.
  window.idealiEvento = function(nome){ if (le() === 'sim' && PIXEL_ID) { carrega(naApp); window.fbq && window.fbq('track', nome); } };

  if (naApp) return;
  if (le() === 'sim') { carrega(); return; }
  if (le() === 'nao' || !PIXEL_ID) return; // no sistema não mostramos o aviso; sem ID não há o que pedir

  function aviso(){
    var d = document.createElement('div');
    d.setAttribute('role','dialog'); d.setAttribute('aria-label','Cookies');
    d.style.cssText = 'position:fixed;left:16px;right:16px;bottom:16px;z-index:9999;max-width:560px;margin:0 auto;background:#1B1826;color:#ECEAF4;border:1px solid #2D2940;border-radius:16px;padding:14px 16px;box-shadow:0 20px 50px rgba(0,0,0,.35);font:14px/1.5 Figtree,system-ui,sans-serif;display:flex;gap:12px;align-items:center;flex-wrap:wrap';
    d.innerHTML = '<span style="flex:1;min-width:220px">Usamos cookies do Meta para medir nossos anúncios. Nada do sistema é compartilhado. <a href="/privacidade.html#cookies" style="color:#9E8CFF">Saiba mais</a></span>' +
      '<button data-c="nao" style="border:1px solid #3a3550;background:none;color:#ECEAF4;border-radius:999px;padding:8px 14px;font:600 14px inherit;cursor:pointer">Recusar</button>' +
      '<button data-c="sim" style="border:0;background:#9E8CFF;color:#121019;border-radius:999px;padding:8px 16px;font:700 14px inherit;cursor:pointer">Aceitar</button>';
    d.addEventListener('click', function(e){ var c = e.target.getAttribute('data-c'); if(!c) return; grava(c); d.remove(); if (c === 'sim') carrega(); });
    document.body.appendChild(d);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', aviso); else aviso();
})();
