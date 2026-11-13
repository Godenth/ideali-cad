-- =====================================================================
-- 064 · Tutoriais em vídeo (Ideali CAD e Ideali Odonto)
-- Lista de vídeos do YouTube escolhidos pela Ideali (exocad, impressora, fresadora...).
-- Guarda só o código do vídeo, título, canal e categoria; o vídeo toca pelo player oficial do YouTube.
-- Todo usuário com conta VÊ a lista; só o administrador do sistema (tabela admins) adiciona, muda ou tira.
-- Não guarda nenhum dado de usuário. Pode rodar de novo.
-- =====================================================================
create table if not exists public.tutoriais (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  video_id   text not null check (video_id ~ '^[A-Za-z0-9_-]{11}$'),
  titulo     text not null check (char_length(titulo) between 1 and 200),
  canal      text check (char_length(canal) <= 120),
  categoria  text not null default 'Outros' check (char_length(categoria) between 1 and 60),
  onde       text not null default 'ambos' check (onde in ('cad','odonto','ambos')),
  ordem      int  not null default 0,
  criado_em  timestamptz not null default now()
);
create index if not exists tutoriais_onde_idx on public.tutoriais (onde, categoria, ordem);

alter table public.tutoriais enable row level security;
revoke all on public.tutoriais from anon;
grant select, insert, update, delete on public.tutoriais to authenticated;

drop policy if exists tutoriais_ve on public.tutoriais;
create policy tutoriais_ve on public.tutoriais for select to authenticated using (true);
drop policy if exists tutoriais_cria on public.tutoriais;
create policy tutoriais_cria on public.tutoriais for insert to authenticated
  with check (user_id = (select auth.uid()) and public.sou_admin());
drop policy if exists tutoriais_muda on public.tutoriais;
create policy tutoriais_muda on public.tutoriais for update to authenticated
  using (public.sou_admin()) with check (public.sou_admin());
drop policy if exists tutoriais_apaga on public.tutoriais;
create policy tutoriais_apaga on public.tutoriais for delete to authenticated
  using (public.sou_admin());

select 'ok: 064 aplicada' as resultado;
