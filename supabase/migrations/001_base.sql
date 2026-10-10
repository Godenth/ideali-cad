-- =====================================================================
-- Ideali CAD · Migração 001 · Base: perfis, assinaturas e regras gerais
-- Rodar no SQL Editor do Supabase (projeto novo, separado do Ideali).
-- =====================================================================

-- ---------- Funções utilitárias ----------

-- Atualiza "atualizado_em" automaticamente.
create or replace function public.tg_atualizado_em()
returns trigger language plpgsql set search_path = public as $$
begin
  new.atualizado_em := now();
  return new;
end $$;

-- Garante o dono do registro: no INSERT usa o usuário logado;
-- no UPDATE impede trocar o dono.
create or replace function public.tg_dono()
returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.user_id := coalesce(auth.uid(), new.user_id);
  else
    new.user_id := old.user_id;
  end if;
  return new;
end $$;

-- ---------- Perfis ----------
create table public.perfis (
  user_id          uuid primary key references auth.users(id) on delete cascade,
  nome             text check (char_length(nome) <= 80),
  telefone         text check (char_length(telefone) <= 30),
  tipo_chave_pix   text check (tipo_chave_pix in ('cpf','cnpj','email','telefone','aleatoria')),
  chave_pix        text check (char_length(chave_pix) <= 77),
  nome_recebedor   text check (char_length(nome_recebedor) <= 25),
  cidade           text check (char_length(cidade) <= 60),
  cidade_cptec_id  integer,
  preferencias     jsonb not null default '{}'::jsonb,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now()
);
create trigger perfis_atualizado before update on public.perfis
  for each row execute function public.tg_atualizado_em();
create trigger perfis_dono before update on public.perfis
  for each row execute function public.tg_dono();

-- ---------- Assinaturas (somente leitura para o cadista) ----------
create table public.assinaturas (
  user_id                uuid primary key references auth.users(id) on delete cascade,
  plano                  text not null default 'basico' check (plano in ('basico','plus','rede','vitrine')),
  status                 text not null default 'teste' check (status in ('teste','ativa','vencida')),
  teste_ate              timestamptz,
  vence_em               timestamptz,
  limite_bytes           bigint not null default 5368709120,  -- 5 GB
  bytes_usados           bigint not null default 0,
  gateway                text,                                 -- 'mercadopago' no futuro
  gateway_assinatura_id  text,
  criado_em              timestamptz not null default now(),
  atualizado_em          timestamptz not null default now()
);
create trigger assinaturas_atualizado before update on public.assinaturas
  for each row execute function public.tg_atualizado_em();

-- Pode gravar? Teste dentro do prazo ou assinatura ativa e não vencida.
create or replace function public.pode_escrever()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.assinaturas a
    where a.user_id = auth.uid()
      and (
        (a.status = 'teste' and a.teste_ate > now())
        or (a.status = 'ativa' and (a.vence_em is null or a.vence_em > now()))
      )
  );
$$;
revoke all on function public.pode_escrever() from public, anon;
grant execute on function public.pode_escrever() to authenticated;

-- ---------- Cadastro: cria perfil e 14 dias de teste ----------
create or replace function public.novo_usuario()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.perfis (user_id, nome)
  values (new.id, left(coalesce(new.raw_user_meta_data->>'nome', ''), 80));

  insert into public.assinaturas (user_id, status, teste_ate)
  values (new.id, 'teste', now() + interval '14 days');
  return new;
end $$;
revoke all on function public.novo_usuario() from public, anon, authenticated;

create trigger ao_criar_usuario
  after insert on auth.users
  for each row execute function public.novo_usuario();

-- ---------- Segurança (RLS) ----------
alter table public.perfis      enable row level security;
alter table public.assinaturas enable row level security;

-- Perfil: cada um lê e edita só o próprio. Sem INSERT/DELETE pelo app
-- (o perfil nasce no cadastro e some junto com a conta).
create policy perfis_ler on public.perfis
  for select to authenticated using (user_id = auth.uid());
create policy perfis_editar on public.perfis
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Assinatura: só leitura da própria linha. Status, plano e limites
-- só mudam pelo servidor (chave service_role, nunca no navegador).
create policy assinaturas_ler on public.assinaturas
  for select to authenticated using (user_id = auth.uid());

revoke all on public.perfis, public.assinaturas from anon, authenticated;
grant select, update on public.perfis to authenticated;
grant select on public.assinaturas to authenticated;
