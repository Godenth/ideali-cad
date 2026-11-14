# Testes automáticos (Ideali Odonto)

Rodam o sistema num navegador de verdade (Playwright), com dados de exemplo, sem tocar no banco.

```bash
python3 -m http.server 8765 &          # na raiz do repositório
mkdir -p tests/saida
node tests/todos-perfis.teste.js        # abre todas as telas de todos os perfis e procura erros
node tests/clinica-pedidos.teste.js     # clínica: filtros, busca, Por mês, detalhe, pendência, Início (computador escuro + celular claro)
```

O que conferem: nenhum erro de JavaScript, a página não estoura a largura no celular, contagens dos filtros, busca, abrir/fechar o detalhe, responder pendência.

## Fonte única (atualização 074)

```bash
# banco: regras de segurança, etapa, prazo (precisa de um Postgres de TESTE com as migrações e auth.uid() lendo t.uid)
psql -v ON_ERROR_STOP=1 -f tests/sql/074_fonte_unica.teste.sql
# gera de novo o exemplo usado nas telas (resposta real da função do banco)
psql -v ON_ERROR_STOP=1 -f tests/sql/gera_exemplo_clinica.sql
# telas: dona (computador e celular), funcionária e banco ainda sem a 074
node tests/clinica-fonte-unica.teste.js
```
