-- =====================================================================
-- 065 · Lembretes e tarefas da Ana (Ideali CAD e Ideali Odonto)
-- Cada usuário vê, cria, muda e apaga SÓ os próprios lembretes (Row Level Security por user_id).
-- Pode rodar de novo.
-- =====================================================================
create table if not exists public.lembretes (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  texto        text not null check (char_length(texto) between 1 and 300),
  quando       timestamptz,
  repetir_min  int check (repetir_min between 1 and 1440),
  feito        boolean not null default false,
  feito_em     timestamptz,
  avisado_em   timestamptz,
  app          text not null default 'cad' check (app in ('cad','odonto')),
  criado_em    timestamptz not null default now()
);
create index if not exists lembretes_user_idx on public.lembretes (user_id, feito, quando);

alter table public.lembretes enable row level security;
revoke all on public.lembretes from anon;
grant select, insert, update, delete on public.lembretes to authenticated;

drop policy if exists lembretes_dono on public.lembretes;
create policy lembretes_dono on public.lembretes for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

select 'ok: 065 aplicada' as resultado;
