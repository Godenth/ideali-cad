-- =====================================================================
-- Ideali CAD · Migração 020 · Perfil da Rede + portfólio de fotos
--  · perfil_rede: 1 linha por cadista (dono = user_id). O dono lê e escreve.
--    Outros usuários LOGADOS só leem se o dono marcou "publicado".
--    Nunca expõe pedidos, clientes ou valores: só o que está nesta tabela.
--  · Bucket "portfolio" PRIVADO: fotos comprimidas (até 700 KB, webp/jpeg),
--    pasta = id do dono, até 12 fotos + 1 foto de perfil. Acesso por URL assinada.
--  · Vídeo não é guardado: só o link (YouTube, Instagram, Vimeo, TikTok, Drive).
-- =====================================================================
create table if not exists public.perfil_rede (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  nome text not null default '' check (char_length(nome) <= 80),
  cidade text not null default '' check (char_length(cidade) <= 80),
  uf text not null default '' check (char_length(uf) <= 2),
  softwares text[] not null default '{}' check (cardinality(softwares) <= 10),
  especialidades text[] not null default '{}' check (cardinality(especialidades) <= 15),
  prazo text not null default '' check (char_length(prazo) <= 40),
  bio text not null default '' check (char_length(bio) <= 600),
  video_url text check (video_url is null or (char_length(video_url) <= 300 and video_url ~* '^https://([a-z0-9-]+\.)*(youtube\.com|youtu\.be|instagram\.com|vimeo\.com|tiktok\.com|drive\.google\.com)/')),
  foto_perfil text check (foto_perfil is null or char_length(foto_perfil) <= 200),
  fotos jsonb not null default '[]'::jsonb check (jsonb_typeof(fotos) = 'array' and jsonb_array_length(fotos) <= 12),
  publicado boolean not null default false,
  atualizado_em timestamptz not null default now()
);
alter table public.perfil_rede enable row level security;

create policy perfil_rede_dono on public.perfil_rede for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy perfil_rede_publicados on public.perfil_rede for select to authenticated
  using (publicado);

grant select, insert, update, delete on public.perfil_rede to authenticated;

-- Bucket privado do portfólio
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('portfolio', 'portfolio', false, 716800, array['image/webp','image/jpeg'])
on conflict (id) do nothing;

create policy portfolio_dono_le on storage.objects for select to authenticated
  using (bucket_id = 'portfolio' and (
    (storage.foldername(name))[1] = auth.uid()::text
    or exists (select 1 from public.perfil_rede p where p.publicado and p.user_id::text = (storage.foldername(name))[1])
  ));
create policy portfolio_dono_envia on storage.objects for insert to authenticated
  with check (bucket_id = 'portfolio'
    and (storage.foldername(name))[1] = auth.uid()::text
    and (select count(*) from storage.objects o where o.bucket_id = 'portfolio' and (storage.foldername(o.name))[1] = auth.uid()::text) < 13);
create policy portfolio_dono_altera on storage.objects for update to authenticated
  using (bucket_id = 'portfolio' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'portfolio' and (storage.foldername(name))[1] = auth.uid()::text);
create policy portfolio_dono_apaga on storage.objects for delete to authenticated
  using (bucket_id = 'portfolio' and (storage.foldername(name))[1] = auth.uid()::text);
