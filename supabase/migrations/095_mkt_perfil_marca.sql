-- 095_mkt_perfil_marca.sql  (idempotente)

create table if not exists public.mkt_perfil_marca (
  id                uuid        primary key default gen_random_uuid(),
  cliente_id        uuid        not null references auth.users on delete cascade,
  nome_marca        text,
  instagram_handle  text,
  o_que_faz         text,
  publico_alvo      text,
  tom_de_voz        text,
  temas_pode        text,
  temas_proibidos   text,
  produtos_servicos text,
  cta_padrao        text,
  atualizado_em     timestamptz not null default now(),
  constraint mkt_perfil_marca_uniq unique (cliente_id)
);

alter table public.mkt_perfil_marca enable row level security;
drop policy if exists "mpm_select" on public.mkt_perfil_marca;
drop policy if exists "mpm_insert" on public.mkt_perfil_marca;
drop policy if exists "mpm_update" on public.mkt_perfil_marca;
create policy "mpm_select" on public.mkt_perfil_marca for select using (cliente_id = auth.uid());
create policy "mpm_insert" on public.mkt_perfil_marca for insert with check (cliente_id = auth.uid());
create policy "mpm_update" on public.mkt_perfil_marca for update using (cliente_id = auth.uid());

-- Perfil piloto: @ideali.odonto (UUID fixo do dono da conta)
insert into public.mkt_perfil_marca (
  cliente_id,
  nome_marca,
  instagram_handle,
  o_que_faz,
  publico_alvo,
  tom_de_voz,
  temas_pode,
  temas_proibidos,
  produtos_servicos,
  cta_padrao
) values (
  'd75221a8-18c5-411e-a120-98647eb8af0e',
  'Ideali Odonto',
  '@ideali.odonto',
  'Sistema online para laboratórios de prótese, protéticos e dentistas. Módulos de pedidos, clientes, financeiro, equipe, vagas, agentes de IA e rede de profissionais. Faz parte do ecossistema Ideali Systems.',
  'Donos de laboratório de prótese, protéticos, dentistas, estudantes de odontologia e de prótese dentária.',
  'Próximo, direto, profissional, com humor leve.',
  'Dicas de gestão de laboratório, produtividade, novidades do sistema, vagas na odontologia, bastidores do Ideali, depoimentos de usuários.',
  'Conteúdo genérico sem relação com odontologia ou gestão. Comparações negativas com concorrentes. Promessas de resultados sem base.',
  'Ideali Odonto (sistema de gestão para laboratório e clínica). Módulos: Pedidos, Financeiro, Equipe, Vagas, Ana (IA), Pedro (IA), Rede de profissionais.',
  'Conheça o Ideali Odonto — link na bio.'
)
on conflict (cliente_id) do update set
  nome_marca        = excluded.nome_marca,
  instagram_handle  = excluded.instagram_handle,
  o_que_faz         = excluded.o_que_faz,
  publico_alvo      = excluded.publico_alvo,
  tom_de_voz        = excluded.tom_de_voz,
  temas_pode        = excluded.temas_pode,
  temas_proibidos   = excluded.temas_proibidos,
  produtos_servicos = excluded.produtos_servicos,
  cta_padrao        = excluded.cta_padrao,
  atualizado_em     = now();
