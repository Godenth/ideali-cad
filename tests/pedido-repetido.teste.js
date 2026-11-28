// Aviso de pedido repetido no Ideali CAD (roda com banco falso, sem tocar na produção).
// Uso: node tests/pedido-repetido.teste.js  (precisa de python -m http.server 8765 na raiz)
const { chromium } = require('playwright');
const { preparar } = require('./banco-de-mentira');
const fs = require('fs');
const path = require('path');

function rowPedido(o) {
  return Object.assign({
    numero: 1, cliente_id: null, paciente: '', elementos: [], tipo_trabalho_id: null,
    valor: 0, status: 'entrada', recebido_em: null, prazo: null, urgente: false,
    cancelado_em: null, deleted_at: null, itens: [], extras: [], ajustes: 0
  }, o);
}

(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ viewport: { width: 1100, height: 900 } });
  const p = await ctx.newPage();
  const errs = [];
  p.on('pageerror', e => errs.push(e.message));

  const hoje = new Date();
  const dia = d => d.toISOString().slice(0, 10);
  const menos = n => { const d = new Date(hoje); d.setDate(d.getDate() - n); return dia(d); };

  await preparar(p, {
    usuario: { id: 'u1', email: 'teste@ideali.com' },
    db: {
      perfis: [{ user_id: 'u1', nome: 'Teste', preferencias: {} }],
      assinaturas: [{ user_id: 'u1', plano: 'basico', status: 'teste' }],
      clientes: [{ id: 'c1', nome: 'Claudinei', telefone: '', tipo: 'dentista', deleted_at: null }],
      tipos_trabalho: [
        { id: 't1', nome: 'Coroa sobre dente', forma: 'elemento', valor_padrao: 100, ativo: true, deleted_at: null }
      ],
      precos_cliente: [],
      pedidos: [
        rowPedido({ numero: 106, cliente_id: 'c1', paciente: 'MARIA SILVA', elementos: [11, 21, 22], tipo_trabalho_id: 't1', valor: 200, status: 'entrada', recebido_em: menos(10) })
      ]
    }
  });

  await p.goto('http://localhost:8765/app/');
  await p.waitForFunction(() => window.S && S.sessao && window.ui && ui.dadosOk, null, { timeout: 15000 });
  await p.waitForTimeout(400);

  const abriu = await p.evaluate(() => {
    A.novoPedido();
    var f = document.querySelector('form[data-form="pedido"]');
    if (!f) return 'sem form';
    f.dataset.modOk = '1';
    document.getElementById('pd-cli').value = 'c1';
    document.getElementById('pd-pac').value = 'Maria Silva';
    document.getElementById('pd-rec').value = new Date().toISOString().slice(0, 10);
    ui.pdItens = [{ d: 11, t: 't1' }, { d: 21, t: 't1' }, { d: 22, t: 't1' }];
    ui.pdExtras = [];
    f.requestSubmit();
    return 'ok';
  });
  if (abriu !== 'ok') { console.log('FALHOU abrir form:', abriu); process.exit(1); }

  await p.waitForSelector('#peddup', { timeout: 5000 });
  const texto = await p.textContent('#peddup');
  const okAviso = /Possível pedido repetido/.test(texto) && /#106/.test(texto) && /Claudinei/.test(texto) && /11, 21, 22/.test(texto);
  fs.mkdirSync(path.join(__dirname, 'saida'), { recursive: true });
  await p.screenshot({ path: path.join(__dirname, 'saida', 'pedido-repetido-aviso.png') });

  await p.click('#peddup [data-m="ver"]');
  await p.waitForTimeout(150);
  const det = await p.textContent('#peddup-det');
  const okDet = /Maria Silva/.test(det) && /Coroa sobre dente/.test(det) && /R\$\s*200/.test(det);
  await p.screenshot({ path: path.join(__dirname, 'saida', 'pedido-repetido-detalhe.png') });

  const antes = await p.evaluate(() => S.pedidos.length);
  await p.click('#peddup [data-m="salvar"]');
  await p.waitForFunction(() => !document.getElementById('peddup'), null, { timeout: 5000 });
  await p.waitForTimeout(300);
  const depois = await p.evaluate(() => S.pedidos.length);
  const okSalvou = depois === antes + 1;

  // saída "Cancelar" não cria pedido
  await p.evaluate(() => { A.novoPedido(); var f = document.querySelector('form[data-form="pedido"]'); f.dataset.modOk = '1'; document.getElementById('pd-cli').value = 'c1'; document.getElementById('pd-pac').value = 'maria silva'; document.getElementById('pd-rec').value = new Date().toISOString().slice(0, 10); ui.pdItens = [{ d: 11, t: 't1' }]; ui.pdExtras = []; f.requestSubmit(); });
  await p.waitForSelector('#peddup', { timeout: 5000 });
  const antes2 = await p.evaluate(() => S.pedidos.length);
  await p.click('#peddup [data-m="cancelar"]');
  await p.waitForTimeout(200);
  const depois2 = await p.evaluate(() => S.pedidos.length);
  const okCancel = depois2 === antes2;

  console.log(okAviso ? 'ok  ' : 'FALHOU', 'aviso aparece com #106, cliente e dentes');
  console.log(okDet ? 'ok  ' : 'FALHOU', 'Ver pedido mostra os detalhes');
  console.log(okSalvou ? 'ok  ' : 'FALHOU', 'Salvar mesmo assim cria o pedido');
  console.log(okCancel ? 'ok  ' : 'FALHOU', 'Cancelar não cria pedido');
  if (errs.length) console.log('ERROS JS:', [...new Set(errs)].slice(0, 5).join(' | '));
  const falhou = !okAviso || !okDet || !okSalvou || !okCancel || errs.length;
  await b.close();
  process.exit(falhou ? 1 : 0);
})();
