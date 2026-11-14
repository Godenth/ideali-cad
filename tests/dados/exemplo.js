// Dados de EXEMPLO para os testes de tela. Tudo inventado: nenhum cliente ou paciente real.
const fs = require('fs'); const path = require('path');
let s = 4242; const r = n => { s = (s * 9301 + 49297) % 233280; return Math.floor(s / 233280 * n); };
const id = (p, n) => p + '0000000-0000-0000-0000-' + String(n).padStart(12, '0');
const dia = n => new Date(Date.now() - n * 864e5).toISOString();

const LAB = { id: id('1', 1), email: 'laboratorio@exemplo.com' };
const CLI = { id: id('1', 2), email: 'clinica@exemplo.com' };
const NOMES_CLI = ['Clínica Sorriso Barra', 'Odonto Prime Copacabana', 'Dr. Renato Vasques', 'Dra. Helena Prado', 'Consultório Dr. Ivo Lessa', 'Oral Center Tijuca', 'Dr. Caio Bittencourt', 'Dra. Lívia Sampaio',
  'Instituto Dental Recreio', 'Dr. Otávio Neves', 'Clínica Bem Sorrir', 'Dra. Marina Coelho', 'Dr. Paulo Arantes', 'Odonto Vida Niterói', 'Dr. Sérgio Maia', 'Dra. Bianca Furtado',
  'Clínica Dente a Dente', 'Dr. Hugo Teles', 'Dra. Paula Reis', 'Dr. André Lobo', 'Odonto Família Méier', 'Dr. Fábio Dutra', 'Dra. Carla Nunes', 'Dr. Miguel Sá', 'Sorria Mais Ipanema', 'Dr. Luan Peixoto', 'Dra. Rita Moraes'];
const PAC = ['Antônio Carlos Figueira', 'Maria Souza Lima', 'João Pedro Lacerda', 'Ana Beatriz Rocha', 'Cláudio Menezes', 'Francisca Rosa Almeida', 'Ronaldo Guedes', 'Jennifer Marques', 'Rogério Coelho', 'Camila Wanzeller',
  'Michel Magalhães', 'Armando Alves', 'Josué Carvalho', 'Luiz Carneiro', 'Meuri Vedovello', 'Vitória Barbosa', 'Rafaela Oliveira', 'Zoe Mello', 'Rosana Pozza', 'Leandro Bispo'];
const SERV = [['Coroa de zircônia', 350, 7], ['Coroa E.max', 420, 7], ['Faceta E.max', 380, 7], ['Coroa metalocerâmica', 300, 10], ['Protocolo de zircônia', 2500, 10], ['Onlay E.max', 320, 7], ['Placa de bruxismo', 180, 5], ['Coroa sobre implante zircônia', 450, 7]];
const DENTES = [11, 12, 13, 14, 15, 16, 17, 21, 22, 23, 24, 25, 26, 27, 31, 32, 34, 35, 36, 37, 41, 42, 44, 45, 46, 47];

function laboratorio() {
  s = 4242;
  const clientes = NOMES_CLI.map((n, i) => ({ id: id('3', i + 1), user_id: LAB.id, reg: i + 1, nome: n, cidade: 'Rio de Janeiro', uf: 'RJ', whatsapp: i % 3 ? '2199999' + String(1000 + i) : null, ativo: i !== 26, criado_em: dia(300) }));
  const precos = SERV.map((x, i) => ({ id: id('8', i + 1), user_id: LAB.id, nome: x[0], grupo: 'Fixa', valor: x[1], prazo: x[2], ordem: i }));
  const cadistas = [{ id: id('9', 1), user_id: LAB.id, reg: 1, nome: 'Bruna Cad', ativo: true }, { id: id('9', 2), user_id: LAB.id, reg: 2, nome: 'Diego Cad', ativo: true }];
  const pedidos = []; let num = 0;
  const novo = (o) => { num++; const sv = SERV[r(SERV.length)], c = clientes[r(26)], q = 1 + (r(5) === 0 ? 1 : 0), ds = []; for (let k = 0; k < q; k++) ds.push(DENTES[r(DENTES.length)]);
    const p = Object.assign({ id: id('6', num), user_id: LAB.id, numero: num, cliente_id: c.id, cliente_reg: c.reg, cliente_nome: c.nome, paciente: PAC[r(PAC.length)], tipo: 'cad', trabalho: sv[0], descricao: null,
      dentes: ds, qtd: q, cor: ['A1', 'A2', 'A3', 'A3,5', 'BL2', 'B1'][r(6)], material: /zirc/i.test(sv[0]) ? 'Zircônia' : /max/i.test(sv[0]) ? 'E.max' : '', sobre_implante: /implante/.test(sv[0]), componente: null,
      valor: sv[1] * q, prazo: null, urgente: false, status: 'desenho', desenho_feito: false, enviado_inove: false, cadista_id: null, cadista_nome: null, origem: 'manual', obs: null, arquivado: false, apagado: false,
      legado: null, finalizado_em: null, entregue_em: null, criado_em: dia(1), atualizado_em: dia(1), envio_id: null, arcada: null, falta_info: null, em_maquiagem: false, prazo_inicio: null }, o);
    p.prazo = p.prazo || new Date(new Date(p.criado_em).getTime() + sv[2] * 1.4 * 864e5).toISOString().slice(0, 10); pedidos.push(p); return p; };
  // do sistema antigo: 128 parados há mais de 30 dias (o caso real), nunca marcados como entregues
  for (let i = 0; i < 128; i++) novo({ status: i % 9 === 0 ? 'desenho' : 'producao', enviado_inove: i % 9 !== 0, desenho_feito: i % 9 !== 0, criado_em: dia(40 + r(260)), legado: 'L' + i, valor: i % 2 ? null : undefined });
  // entregues e arquivados
  for (let i = 0; i < 60; i++) { const d = 20 + r(200); novo({ status: 'entregue', arquivado: true, enviado_inove: true, desenho_feito: true, criado_em: dia(d + 8), entregue_em: dia(d), finalizado_em: dia(d + 1) }); }
  // a fila de verdade: novembro
  novo({ status: 'desenho', criado_em: dia(0.2), urgente: true });
  novo({ status: 'desenho', criado_em: dia(1), cadista_id: cadistas[0].id, cadista_nome: cadistas[0].nome });
  novo({ status: 'desenho', desenho_feito: true, criado_em: dia(2), cadista_id: cadistas[1].id, cadista_nome: cadistas[1].nome });
  novo({ status: 'producao', desenho_feito: true, enviado_inove: true, criado_em: dia(3) });
  novo({ status: 'producao', desenho_feito: true, enviado_inove: true, em_maquiagem: true, criado_em: dia(5) });
  novo({ status: 'producao', desenho_feito: true, enviado_inove: true, criado_em: dia(6) });
  novo({ status: 'aguardando', falta_info: 'Escaneamento do antagonista veio cortado.', criado_em: dia(2) });
  novo({ status: 'finalizado', desenho_feito: true, enviado_inove: true, criado_em: dia(7), finalizado_em: dia(0.5) });
  novo({ status: 'finalizado', desenho_feito: true, enviado_inove: true, criado_em: dia(8), finalizado_em: dia(1) });
  novo({ status: 'orcamento', criado_em: dia(1) });
  // um pedido que chegou pelo sistema (clínica conectada) e já foi aceito
  const envAceito = id('5', 2);
  novo({ status: 'desenho', criado_em: dia(1), origem: 'portal', envio_id: envAceito, cliente_id: clientes[0].id, cliente_reg: 1, cliente_nome: clientes[0].nome, paciente: 'Maria Souza Lima' });
  const hoje = new Date(), meses = [], pags = []; let mi = 0;
  for (let k = 1; k <= 4; k++) { const d = new Date(hoje.getFullYear(), hoje.getMonth() - k, 1); for (let c = 0; c < 8; c++) { mi++; const v = 900 + r(40) * 100;
      meses.push({ id: id('7', mi), user_id: LAB.id, cliente_id: clientes[c].id, cliente_reg: clientes[c].reg, ano: d.getFullYear(), mes: d.getMonth() + 1, valor_mes: v, valor_componente: 0, extrato_recebido: true, enviado: true, quitado: k > 1 && c % 3 !== 0, criado_em: dia(30 * k) });
      if (k > 1 && c % 3 !== 0) pags.push({ id: id('a', mi), user_id: LAB.id, mes_id: id('7', mi), valor: v, data: new Date(d.getFullYear(), d.getMonth() + 1, 8).toISOString().slice(0, 10), criado_em: dia(30 * k - 8) });
      else if (k > 1) pags.push({ id: id('a', mi), user_id: LAB.id, mes_id: id('7', mi), valor: Math.round(v / 2), data: new Date(d.getFullYear(), d.getMonth() + 1, 12).toISOString().slice(0, 10), criado_em: dia(30 * k - 12) }); } }
  const empresa = { id: id('2', 1), user_id: LAB.id, tipo: 'lab', nome: 'Laboratório Exemplo', uf: 'RJ', cidade: 'Rio de Janeiro', papel: 'dono', rt: 'TPD Exemplo', dados: { eq: [], vagas: [] }, codigo: 1, criado_em: dia(400) };
  const envios = [
    { id: id('5', 1), user_id: CLI.id, vinculo_id: id('4', 1), lab_id: empresa.id, dentista_nome: 'Dra. Helena Prado', paciente: 'Antônio Carlos Figueira', itens: [{ trabalho: 'Coroa de zircônia', dentes: [35, 36], material: 'Zircônia', tipo: 'cad' }], cor: 'A3,5', prazo: null, urgente: false, obs: 'Paciente com mordida cruzada.', arquivos: [{ path: 'x/y/scan.stl', nome: 'scan-superior.stl', tipo: 'scan', tam: 8400000 }, { path: 'x/y/foto.jpg', nome: 'foto-cor.jpg', tipo: 'foto', tam: 900000 }], tam_total: 9300000, status: 'enviado', criado_em: dia(0.1), enviado_em: dia(0.1), apagar_em: dia(-3) },
    { id: envAceito, user_id: CLI.id, vinculo_id: id('4', 1), lab_id: empresa.id, dentista_nome: 'Dra. Helena Prado', paciente: 'Maria Souza Lima', itens: [{ trabalho: 'Coroa E.max', dentes: [11], material: 'E.max', tipo: 'cad' }], cor: 'BL2', arquivos: [], tam_total: 0, status: 'aceito', etapa: 'Desenho CAD', criado_em: dia(1), enviado_em: dia(1), respondido_em: dia(0.9), apagar_em: dia(-2), lab_pedidos: [] }];
  const vinculos = [{ id: id('4', 1), user_id: CLI.id, lab_id: empresa.id, lab_nome: empresa.nome, quem_nome: 'Dra. Helena Prado', status: 'aceito', cliente_id: clientes[3].id, criado_em: dia(20), respondido_em: dia(19) },
    { id: id('4', 2), user_id: id('1', 9), lab_id: empresa.id, lab_nome: empresa.nome, quem_nome: 'Dr. Novo Cliente', status: 'pendente', cliente_id: null, criado_em: dia(0.5) }];
  return { usuario: LAB, db: {
      odo_perfis: [{ user_id: LAB.id, nome: 'Danilo Exemplo', whats: '21999990000', prof: 'Protético', cargo: '', idade: 35, sexo: 'M', uf: 'RJ', cidade: 'Rio de Janeiro', softs: [], pos: [], cursos: [], exp: [], vis: {}, aberto: false, cadastro: {} }],
      perfis: [], odo_empresas: [empresa], odo_clientes: clientes, odo_precos: precos, odo_cadistas: cadistas, odo_pedidos: pedidos, odo_fin_meses: meses, odo_fin_pagamentos: pags,
      odo_fin_leituras: [], odo_fin_config: [{ user_id: LAB.id, chave_pix: 'pix@exemplo.com', comissao_pct: 0 }], odo_fin_comissoes: [], odo_parceiros: [], odo_ped_env: envios, odo_lab_vinculos: vinculos,
      lembretes: [{ id: id('b', 1), user_id: LAB.id, texto: 'Ligar para a Clínica Sorriso sobre o protocolo', quando: dia(-0.1), feito: false, app: 'odonto', criado_em: dia(1) }], tutoriais: [], odo_membros: [], odo_ped_msgs: [] },
    rpc: { odo_minha_equipe: [], odo_rede_profs: [], odo_rede_pre: [], odo_rede_empresas: [], odo_clinica_pedidos: { dono: true, envios: [], pedidos: [], meses: [] }, odo_labs_parceiros: [] } };
}

// clínica: a resposta REAL da função do banco (gerada por tests/sql/gera_exemplo_clinica.sql)
function clinica(quem) {
  const D = JSON.parse(fs.readFileSync(path.join(__dirname, quem === 'funcionaria' ? 'clinica_funcionaria.json' : 'clinica_dona.json'), 'utf8'));
  const U = { id: quem === 'funcionaria' ? id('1', 3) : id('1', 2), email: 'clinica@exemplo.com' }, dona = id('1', 2), lab = id('2', 1);
  const semExtras = D.envios.map(e => { const o = {}; for (const k in e) if (['partes', 'aberto', 'parado', 'prazo_min', 'prazo_max', 'faixa', 'lab_nome'].indexOf(k) < 0) o[k] = e[k]; return o; });
  return { usuario: U, db: {
      odo_perfis: [{ user_id: U.id, nome: quem === 'funcionaria' ? 'Gilmara Exemplo' : 'Fernando Exemplo', whats: '21988880000', prof: 'Dentista', cargo: '', idade: 40, sexo: quem === 'funcionaria' ? 'F' : 'M', uf: 'RJ', cidade: 'Rio de Janeiro', softs: [], pos: [], cursos: [], exp: [], vis: {}, aberto: false, cadastro: {} }],
      perfis: [], odo_empresas: quem === 'funcionaria' ? [] : [{ id: id('2', 7), user_id: U.id, tipo: 'clinica', nome: 'Clínica Exemplo', uf: 'RJ', cidade: 'Rio de Janeiro', papel: 'dono', dados: {}, codigo: 7, criado_em: dia(30) }],
      odo_clientes: [], odo_precos: [], odo_cadistas: [], odo_pedidos: [], odo_fin_meses: [], odo_fin_pagamentos: [], odo_fin_leituras: [], odo_fin_config: [], odo_fin_comissoes: [], odo_parceiros: [],
      odo_ped_env: semExtras, odo_lab_vinculos: [{ id: id('4', 10), user_id: dona, lab_id: lab, lab_nome: 'Ideali Lab', status: 'aceito', cliente_id: id('3', 10), criado_em: dia(5), respondido_em: dia(5) }],
      lembretes: [], tutoriais: [], odo_membros: [], odo_ped_msgs: [] },
    rpc: { odo_minha_equipe: quem === 'funcionaria' ? [] : [], odo_rede_profs: [], odo_rede_pre: [], odo_rede_empresas: [], odo_clinica_pedidos: D,
      odo_labs_parceiros: [{ id: id('4', 10), lab_id: lab, lab_nome: 'Ideali Lab', status: 'aceito', codigo: 1 }], odo_clinica_pagamentos: [] } };
}
module.exports = { laboratorio, clinica, LAB, CLI };
