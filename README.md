# Ideali CAD

Sistema por assinatura para cadistas odontológicos: pedidos em kanban, clientes com tabela de preços, financeiro, cobrança Pix e controle de arquivos STL.

- `index.html` — página de apresentação
- `app/` — o sistema (HTML, CSS e JavaScript puro)
- `supabase/migrations/` — banco de dados (rodar em ordem no SQL Editor)
- `supabase/functions/` — funções do servidor (Edge Functions)
- `supabase/tests/` — testes de segurança (isolamento entre contas)

## Segurança
- Login pelo Supabase Auth. Só a chave pública (anon) fica no navegador.
- Todas as tabelas têm dono (`user_id`) e Row Level Security: cada cadista só vê os próprios dados.
- Nada é apagado de verdade pelo app: "excluir" manda para a lixeira (`deleted_at`).
- Com a assinatura vencida, o cadista continua lendo e exportando, mas não grava.
