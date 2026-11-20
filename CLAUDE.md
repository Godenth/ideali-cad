# Ideali — instruções para agentes

Fale com o dono em português do Brasil simples e curto. Ele usa o sistema todo dia no laboratório.

## O que é cada coisa
- `odonto/app/index.html` — **Ideali Odonto** (um arquivo só, ES5, ~9 mil linhas). No ar em https://idealisystems.com/odonto/app
- `app/index.html` — **Ideali CAD**. No ar em https://idealisystems.com/app/
- `odonto/index.html` — página de apresentação.
- `supabase/migrations/NNN_*.sql` — atualizações do banco. **O agente não roda SQL no Supabase**: o dono roda no editor SQL do projeto `qxspiaqaigjkmilxxfri`. Entregue o arquivo e diga o número.
- `tests/*.teste.js` — testes com Playwright (`node tests/<arquivo>`). Rode os da Ana depois de mexer nela.
- `docs/ver-depois.md` — lista de pendências.
- Publicação: GitHub Pages. **Push no `main` vai direto para o ar.** Antes de editar, `git pull`.

## Regras que não mudam
- Cada conta vê **só os próprios dados**. Supabase Auth + Row Level Security em TODAS as tabelas, com coluna de dono (`user_id`). Nunca vazar dado de um usuário para outro.
- Nenhuma senha fixa no código. Nenhuma chave `service_role` no front-end; só a chave pública (anon).
- Buckets do Storage **privados**, acesso por URL assinada e política por usuário.
- Se uma decisão mudar custo ou segurança, **pergunte antes**.
- Não remova funções sem perguntar. Coisa grande: converse antes de construir. Coisa ambígua: confirme o entendimento.
- Não invente números nem depoimentos.
- Banco antigo `alqhhgysvehtgkwsxeok` é só leitura. Não mexa nos projetos Supabase de advocacia.
- Nunca cole segredos em chat, código ou commit.
- Visual sóbrio, nada infantil.

## Jeito do código
- Módulos novos entram antes do marcador `/* conta real: nada de dados de exemplo no painel */`.
- CSS novo vai no segundo bloco `<style>`. Confira que as chaves `{}` fecham (um `@media` aberto já quebrou o visual).
- Ações: `ACT` + `data-act`/`data-v`. Cada módulo usa seus próprios atributos `data-*` e listeners delegados.
- Ana = assistente que entende pedidos escritos; Pedro = estagiário das tarefas e lembretes.
- Testar antes de publicar: abrir a página com `python3 -m http.server` e Playwright; checar erros no console.
