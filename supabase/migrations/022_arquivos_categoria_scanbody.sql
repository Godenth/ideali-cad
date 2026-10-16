-- =====================================================================
-- Ideali CAD · Migração 022 · Arquivos por categoria + print do scanbody
--  · arquivos.categoria: 'scan' (escaneamento do cliente), 'html' (HTML do exocad),
--    'fres' (STL do elemento para fresagem). Nulo = arquivos antigos (sem categoria).
--  · pedidos.scanbody_img: caminho da imagem colada (Ctrl+V) do scanbody, no bucket
--    PRIVADO "pedido-img" (pasta = id do dono, até 700 KB, webp/jpeg). O cliente vê
--    pelo link de acompanhamento, por URL assinada gerada no servidor (função portal).
-- =====================================================================
alter table public.arquivos add column if not exists categoria text check (categoria is null or categoria in ('scan','html','fres'));
alter table public.pedidos add column if not exists scanbody_img text check (scanbody_img is null or char_length(scanbody_img) <= 200);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('pedido-img', 'pedido-img', false, 716800, array['image/webp','image/jpeg'])
on conflict (id) do nothing;

create policy pedido_img_le on storage.objects for select to authenticated
  using (bucket_id = 'pedido-img' and (storage.foldername(name))[1] = auth.uid()::text);
create policy pedido_img_envia on storage.objects for insert to authenticated
  with check (bucket_id = 'pedido-img' and (storage.foldername(name))[1] = auth.uid()::text);
create policy pedido_img_altera on storage.objects for update to authenticated
  using (bucket_id = 'pedido-img' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'pedido-img' and (storage.foldername(name))[1] = auth.uid()::text);
create policy pedido_img_apaga on storage.objects for delete to authenticated
  using (bucket_id = 'pedido-img' and (storage.foldername(name))[1] = auth.uid()::text);
