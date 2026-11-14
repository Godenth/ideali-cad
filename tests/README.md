# Testes automáticos (Ideali Odonto)

Rodam o sistema num navegador de verdade (Playwright), com dados de exemplo, sem tocar no banco.

```bash
python3 -m http.server 8765 &          # na raiz do repositório
mkdir -p tests/saida
node tests/todos-perfis.teste.js        # abre todas as telas de todos os perfis e procura erros
node tests/clinica-pedidos.teste.js     # clínica: filtros, busca, Por mês, detalhe, pendência, Início (computador escuro + celular claro)
```

O que conferem: nenhum erro de JavaScript, a página não estoura a largura no celular, contagens dos filtros, busca, abrir/fechar o detalhe, responder pendência.
