# AGENTS.md — Guia para agentes de IA no Ideali

Documento de referência para qualquer agente que for trabalhar neste repositório.

---

## O que o sistema faz

O **Ideali** é uma plataforma SaaS para laboratórios de prótese odontológica e cadistas (fresadores de CAD/CAM). Tem dois produtos no ar:

| Produto | Arquivo | URL |
|---|---|---|
| **Ideali CAD** | `app/index.html` | https://idealisystems.com/app/ |
| **Ideali Odonto** | `odonto/app/index.html` | https://idealisystems.com/odonto/app |

**Ideali CAD** — sistema para cadistas: pedidos em kanban, clientes com tabela de preços, financeiro, cobrança Pix e controle de arquivos STL/3D.

**Ideali Odonto** — sistema para laboratórios de prótese: recebimento de pedidos de dentistas/clínicas, financeiro, agenda, equipe, catálogo de serviços e rede de parceiros.

Ambos são **single-page apps** em HTML/CSS/JS puro (sem framework). Banco no Supabase (PostgreSQL). Deploy via GitHub Pages no push do branch `main`.

---

## Mapa das pastas e arquivos

```
ideali-cad/
├── index.html              Página de apresentação do Ideali CAD
├── tour.html               Tour/onboarding
├── rede.html               Página da rede de parceiros
├── privacidade.html        Política de privacidade
├── termos.html             Termos de uso
├── CNAME                   Domínio: idealisystems.com
├── pixel.js / visita.js    Rastreamento de visitas
│
├── app/                    ★ Ideali CAD (o sistema do cadista)
│   ├── index.html          App inteiro (~9 mil linhas, ES5+, tudo em 1 arquivo)
│   ├── componentes.js      Componentes reutilizáveis (separado para cache)
│   ├── visualizador.html   Visualizador 3D de arquivos STL
│   ├── manifest.webmanifest  PWA manifest
│   └── equipe/             Avatares da Ana, Bia e Klose (assistentes de IA)
│
├── odonto/                 ★ Ideali Odonto (o sistema do laboratório)
│   ├── index.html          Página de apresentação do Odonto
│   ├── demo-inove.html     Demo para a rede Inove
│   └── app/
│       ├── index.html      App Odonto inteiro (~9 mil linhas)
│       └── br-mapa.json    Mapa do Brasil para o módulo de rede
│
├── c/index.html            Página de captura de leads
├── enviar/index.html       Página de envio de arquivos por link
│
├── supabase/
│   ├── migrations/         ★ Histórico do banco (001 a 091, em ordem)
│   └── functions/          Edge Functions (funções do servidor)
│
├── tests/                  Testes Playwright (rodar com: node tests/<arquivo>)
├── docs/ver-depois.md      Lista de pendências e decisões adiadas
└── .github/workflows/
    └── backup.yml          Backup semanal do banco (todo seg. 04h, criptografado)
```

---

## Como é feito o deploy

- **Plataforma:** GitHub Pages. O branch `main` é a produção.
- **Fluxo:** `git push origin main` → GitHub Pages publica automaticamente em segundos.
- **Domínio:** configurado via `CNAME` (idealisystems.com).
- **Sem build step:** os arquivos são servidos diretamente. Não há npm install, bundler nem CI de build.
- **Backup do banco:** GitHub Actions (`.github/workflows/backup.yml`) faz dump do Supabase toda segunda às 04h de Brasília, criptografa com AES-256 e guarda como artifact por 90 dias. Requer dois secrets no GitHub: `SUPABASE_DB_URL` e `BACKUP_SENHA`.

> ⚠️ **Push no `main` vai direto ao ar.** Sempre faça `git pull` antes de editar. Teste localmente com `python3 -m http.server` + Playwright antes de commitar.

---

## Tabelas do Supabase usadas

Projeto: **IDEALI CAD** (`qxspiaqaigjkmilxxfri`). Migrations em `supabase/migrations/`, rodar em ordem no SQL Editor.

### Bloco CAD (001–038)
| # | Arquivo | O que cria/altera |
|---|---|---|
| 001 | `001_base.sql` | `perfis`, `assinaturas`, funções `tg_atualizado_em` / `tg_dono` |
| 002 | `002_trabalho.sql` | `clientes`, `pedidos`, `etapas`, `arquivos` |
| 003 | `003_admin.sql` | Tabelas e funções de administração |
| 004 | `004_clientes_cadastro.sql` | Campos extras no cadastro de clientes |
| 005 | `005_cidade_estado.sql` | Campo cidade/estado no perfil |
| 006 | `006_tipos_padrao_no_cadastro.sql` | Tipos de serviço padrão |
| 007 | `007_tipos_sem_repetidos.sql` | Deduplicação de tipos |
| 008 | `008_lista_referencia.sql` | Listas de referência (materiais, etc.) |
| 009 | `009_modelo_3d.sql` | Suporte a modelos 3D nos pedidos |
| 010 | `010_scanbody.sql` | Dados de scanbody/implante |
| 011 | `011_elemento_sobre.sql` | Elemento "sobre implante" |
| 012 | `012_itens_material.sql` | Itens e materiais dos pedidos |
| 013 | `013_plano_gratis.sql` | Plano gratuito |
| 014 | `014_link_cliente.sql` | Link de envio por cliente |
| 015 | `015_cliente_titulo.sql` | Título/apelido do cliente |
| 016 | `016_ajustes_motivos.sql` | Motivos de ajuste/retrabalho |
| 017 | `017_uso_admin.sql` | Métricas de uso para admin |
| 018 | `018_admin_mfa.sql` | MFA para admin |
| 019 | `019_lancamento_gratis.sql` | Período de lançamento gratuito |
| 020 | `020_perfil_rede.sql` | Perfil público na rede |
| 021 | `021_rede_stats.sql` | Estatísticas da rede |
| 022 | `022_arquivos_categoria_scanbody.sql` | Categoria de arquivo scanbody |
| 023 | `023_espaco_1gb_e_ia.sql` | Limite de espaço 1 GB + flag de IA |
| 024 | `024_whatsapp_no_cadastro.sql` | WhatsApp no cadastro |
| 025 | `025_arquivos_conteudo_verificado.sql` | Flag de conteúdo verificado |
| 026 | `026_rede_stats_so_comprovados.sql` | Stats só de perfis comprovados |
| 027 | `027_pagina_captura_leads.sql` | Leads da página de captura |
| 028 | `028_captura_whatsapp_destino.sql` | Destino WhatsApp para captura |
| 029 | `029_captura_pixel.sql` | Pixel de rastreamento na captura |
| 030 | `030_pedido_cancelado_pausado.sql` | Status cancelado/pausado |
| 031 | `031_comp_notas.sql` | Notas de complemento |
| 032 | `032_prospeccao_equipe.sql` | Prospecção de equipe comercial |
| 033 | `033_telas_e_site.sql` | Configurações de telas e site |
| 034 | `034_painel_recursos.sql` | Recursos do painel |
| 035 | `035_caixa_entrada.sql` | Caixa de entrada de mensagens |
| 036 | `036_rede_sem_comprovar.sql` | Rede sem exigir comprovação |
| 037 | `037_perfil_logo.sql` | Logo no perfil |
| 038 | `038_paciente_nome_completo.sql` | Nome completo do paciente |

### Bloco Odonto (039–091)
| # | Arquivo | O que cria/altera |
|---|---|---|
| 039 | `039_odonto_perfis.sql` | Perfis do Odonto |
| 040 | `040_odonto_cadastro.sql` | Cadastro base do Odonto |
| 042 | `042_odonto_empresa.sql` | Dados da empresa/laboratório |
| 043 | `043_odonto_pedidos.sql` | Pedidos do laboratório |
| 044 | `044_odonto_financeiro.sql` | Financeiro do laboratório |
| 045 | `045_odonto_resumo_diario.sql` | Resumo diário |
| 046 | `046_odonto_conta_espelho.sql` | Conta espelho (parceiro vê financeiro) |
| 047 | `047_odonto_corrige_mes_importado.sql` | Correção de mês importado |
| 048 | `048_odonto_aguardando_e_leitura.sql` | Status aguardando / marcação de leitura |
| 049 | `049_odonto_pre_cadastros.sql` | Pré-cadastros (antes de confirmar) |
| 050 | `050_odonto_pre_na_rede.sql` | Pré-cadastros na rede |
| 051 | `051_odonto_pre_especialidades.sql` | Especialidades dos pré-cadastros |
| 052 | `052_odonto_pre_empresas.sql` | Empresas dos pré-cadastros |
| 053 | `053_corrige_upload_storage.sql` | Correção de upload no Storage |
| 054 | `054_odonto_inove_confirma.sql` | Fluxo de confirmação Inove |
| 055 | `055_odonto_inove_anexa.sql` | Anexos Inove |
| 056 | `056_odonto_lab_convite.sql` | Convite entre laboratórios |
| 057 | `057_odonto_pedido_digital.sql` | Pedido digital (sem papel) |
| 058 | `058_cad_pagamento_parcial.sql` | Pagamento parcial no CAD |
| 059 | `059_odonto_pedido_arcada.sql` | Arcada no pedido Odonto |
| 060 | `060_odonto_etapa_pedido_clinica.sql` | Etapa do pedido para clínica |
| 061 | `061_odonto_financeiro_clinica.sql` | Financeiro da clínica |
| 062 | `062_odonto_contato_laboratorio.sql` | Contato entre laboratório e clínica |
| 063 | `063_odonto_contato_so_aceito.sql` | Contato só após aceite |
| 064 | `064_tutoriais_videos.sql` | Tutoriais em vídeo |
| 065 | `065_lembretes.sql` | Lembretes (Pedro) |
| 066 | `066_tutoriais_nivel.sql` | Nível dos tutoriais |
| 067 | `067_odonto_clinica_ve_pedidos_lab.sql` | Clínica vê pedidos do laboratório |
| 068 | `068_odonto_equipe_e_dono.sql` | Equipe e dono do laboratório |
| 069 | `069_odonto_historico_pagamentos_clinica.sql` | Histórico de pagamentos da clínica |
| 070 | `070_odonto_pedido_video.sql` | Vídeo anexado ao pedido |
| 071 | `071_odonto_prazo_contador.sql` | Contador de prazo |
| 072 | `072_odonto_pendencia_resposta.sql` | Pendência de resposta |
| 073 | `073_odonto_fin_clinica_pedidos_lab.sql` | Financeiro clínica × pedidos lab |
| 074 | `074_odonto_fonte_unica_pedidos.sql` | Fonte única de pedidos |
| 075 | `075_odonto_financeiro_unico.sql` | Financeiro unificado |
| 076 | `076_odonto_recebi_e_baixa_extrato.sql` | "Recebi" e baixa no extrato |
| 077 | `077_odonto_mapa_publico.sql` | Mapa público de laboratórios |
| 078 | `078_odonto_home_cartoes.sql` | Cartões da home do Odonto |
| 079 | `079_odonto_home_primeiro_nome.sql` | Primeiro nome na home |
| 080 | `080_odonto_home_cartoes_pre.sql` | Cartões da home (pré-cadastro) |
| 081 | `081_odonto_conta_provisoria.sql` | Conta provisória |
| 082 | `082_odonto_home_contagem.sql` | Contagens da home |
| 083 | `083_odonto_tarefas.sql` | Tarefas (Pedro) |
| 084 | `084_odonto_tarefas_cliente.sql` | Tarefas ligadas a cliente |
| 085 | `085_odonto_tarefas_urgente.sql` | Flag urgente nas tarefas |
| 086 | `086_odonto_caso_arquivos.sql` | Arquivos do caso |
| 087 | `087_odonto_tarefas_pedido.sql` | Tarefas ligadas a pedido |
| 088 | `088_odonto_tarefas_varios_pedidos.sql` | Tarefas em vários pedidos |
| 089 | `089_odonto_perfil_empresa.sql` | Perfil público da empresa |
| 090 | `090_odonto_catalogo.sql` | Catálogo de serviços |
| 091 | `091_odonto_espelho_so_inove.sql` | Conta espelho restrita à rede Inove |

---

## Regras de cuidado para agentes de IA

### Banco de dados
- **Nunca aplicar SQL no Supabase** sem o "ok" explícito do dono. Entregue o arquivo `.sql` e diga o número da migration.
- Projeto ativo: `qxspiaqaigjkmilxxfri`. O projeto `alqhhgysvehtgkwsxeok` é só leitura (advocacia), não mexa.
- Toda tabela nova precisa de RLS habilitado e política que filtre por `user_id = auth.uid()`.
- Nunca usar a chave `service_role` no front-end. Só a chave `anon` (pública) vai no código.
- Buckets do Storage são privados; acesso por URL assinada.

### Deploy
- **Push no `main` vai direto ao ar** (produção com clientes reais). Só faça push com o "ok" do dono.
- Sempre `git pull` antes de editar para não sobrescrever trabalho.
- Teste localmente antes de commitar: `python3 -m http.server` + Playwright (`node tests/<arquivo>`).

### Código
- Os dois apps são arquivos únicos enormes. Módulos novos entram **antes** do marcador `/* conta real: nada de dados de exemplo no painel */`.
- CSS novo vai no **segundo bloco `<style>`**. Confira que todas as chaves `{}` fecham — um `@media` aberto quebra o visual inteiro.
- Ações usam `ACT` + `data-act`/`data-v`. Listeners são delegados por módulo.
- **Ana** = assistente de IA que entende pedidos em texto. **Pedro** = estagiário de tarefas e lembretes.
- Nunca remova funções sem perguntar. Nunca invente números, depoimentos ou dados.
- Visual sóbrio (nada infantil). Sem comentários óbvios no código.

### Segurança
- Nenhuma senha ou chave secreta no código ou no commit.
- Cada conta vê só os próprios dados (RLS em todas as tabelas).
- "Excluir" = soft delete (`deleted_at`), nunca `DELETE` real pelo app.
- Se uma decisão mudar custo ou segurança, perguntar ao dono antes de implementar.

### Ordem de uso das IAs (regra global)
1. Gemini grátis → `gemini -p "<tarefa>" --yolo`
2. OpenCode grátis → `opencode run -m opencode/longcat-2.5-free "<tarefa>"`
3. OpenCode Go → `opencode-go/glm-5.3-flash` (só se os grátis falharem 2 vezes)
4. `opencode-go/kimi-k3.1-pro` só em último caso
