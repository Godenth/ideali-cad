-- =====================================================================
-- 049 · Ideali Odonto · Pré-cadastros (contatos importados, ESCONDIDOS).
-- Ninguém aparece na Rede por estar aqui. Só o dono da lista vê.
-- Cada contato recebe um convite com link pessoal; ao aceitar, o cadastro dele
-- já vem preenchido e ELE confirma e escolhe o que fica visível.
-- Repetidos: o mesmo e-mail ou o mesmo WhatsApp não entra duas vezes na mesma lista.
-- =====================================================================
create table if not exists public.odo_pre_cadastros (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nome          text check (char_length(nome) <= 120),
  email         text check (char_length(email) <= 160),
  whatsapp      text check (char_length(whatsapp) <= 20),
  profissao     text check (char_length(profissao) <= 80),
  cidade        text check (char_length(cidade) <= 80),
  uf            text check (char_length(uf) <= 2),
  origem        text check (char_length(origem) <= 60),
  token         text not null unique default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  convidado_em  timestamptz,
  aberto_em     timestamptz,
  aceito_por    uuid references auth.users(id) on delete set null,
  aceito_em     timestamptz,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  check (email is not null or whatsapp is not null)
);
create unique index if not exists odo_pre_email_unico on public.odo_pre_cadastros (user_id, lower(email)) where email is not null;
create unique index if not exists odo_pre_whats_unico on public.odo_pre_cadastros (user_id, whatsapp) where whatsapp is not null;
alter table public.odo_pre_cadastros enable row level security;
drop policy if exists odo_pre_dono on public.odo_pre_cadastros;
create policy odo_pre_dono on public.odo_pre_cadastros for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke all on public.odo_pre_cadastros from anon;
drop trigger if exists odo_pre_dono on public.odo_pre_cadastros;
create trigger odo_pre_dono before update on public.odo_pre_cadastros for each row execute function public.odo_dono_fixo();

-- quem recebeu o convite abre o link já logado: recebe SÓ os próprios dados para preencher o cadastro
create or replace function public.odo_pre_aceita(p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r public.odo_pre_cadastros; eu uuid := auth.uid();
begin
  if eu is null then raise exception 'Entre na sua conta'; end if;
  select * into r from public.odo_pre_cadastros where token = p_token;
  if r.id is null then raise exception 'Convite inválido'; end if;
  if r.aceito_por is not null and r.aceito_por <> eu then raise exception 'Este convite já foi usado'; end if;
  update public.odo_pre_cadastros set aceito_por = eu, aceito_em = coalesce(aceito_em, now()), aberto_em = coalesce(aberto_em, now()) where id = r.id;
  return jsonb_build_object('nome', r.nome, 'whatsapp', r.whatsapp, 'profissao', r.profissao, 'cidade', r.cidade, 'uf', r.uf);
end $$;
revoke all on function public.odo_pre_aceita(text) from public, anon;
grant execute on function public.odo_pre_aceita(text) to authenticated;

select 'ok: 049 aplicada' as resultado;
