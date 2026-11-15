-- 086 · Arquivos do caso no pedido do laboratório: Dental CAD (.zip), STL de fresagem e HTML do exocad.
-- Bucket PRIVADO "odonto-casos"; cada arquivo fica em <conta>/<pedido>/<arquivo> e só a própria conta
-- (dono ou membro ativo da equipe, via odo_conta()) lê, grava e apaga. Acesso pelo app com URL assinada/download autenticado.
-- No pedido fica só a lista dos arquivos e o resumo do projeto lido (coluna caso). Pode rodar mais de uma vez.
alter table public.odo_pedidos add column if not exists caso jsonb;
alter table public.odo_pedidos drop constraint if exists odo_pedidos_caso_tam;
alter table public.odo_pedidos add constraint odo_pedidos_caso_tam check (caso is null or pg_column_size(caso) < 200000);

insert into storage.buckets (id, name, public, file_size_limit)
values ('odonto-casos', 'odonto-casos', false, 524288000)
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit;

drop policy if exists odonto_casos_ler on storage.objects;
create policy odonto_casos_ler on storage.objects for select to authenticated
  using (bucket_id = 'odonto-casos' and (storage.foldername(name))[1] = (select public.odo_conta())::text);
drop policy if exists odonto_casos_gravar on storage.objects;
create policy odonto_casos_gravar on storage.objects for insert to authenticated
  with check (bucket_id = 'odonto-casos' and (storage.foldername(name))[1] = (select public.odo_conta())::text);
drop policy if exists odonto_casos_trocar on storage.objects;
create policy odonto_casos_trocar on storage.objects for update to authenticated
  using (bucket_id = 'odonto-casos' and (storage.foldername(name))[1] = (select public.odo_conta())::text)
  with check (bucket_id = 'odonto-casos' and (storage.foldername(name))[1] = (select public.odo_conta())::text);
drop policy if exists odonto_casos_apagar on storage.objects;
create policy odonto_casos_apagar on storage.objects for delete to authenticated
  using (bucket_id = 'odonto-casos' and (storage.foldername(name))[1] = (select public.odo_conta())::text);
