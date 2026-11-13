-- =====================================================================
-- 070 · Ideali Odonto · Vídeo no pedido digital
-- A pasta privada "odonto-ped" passa a aceitar vídeos (mp4, mov, webm, 3gp), até 50 MB cada.
-- Continua privada e com as mesmas regras (só a clínica que mandou e o laboratório veem;
-- apaga em 3 dias). Pode rodar de novo.
-- =====================================================================
update storage.buckets
   set allowed_mime_types = array['application/zip','image/jpeg','image/png','image/webp','application/pdf',
                                  'video/mp4','video/quicktime','video/webm','video/3gpp'],
       public = false, file_size_limit = 52428800
 where id = 'odonto-ped';
select 'ok: 070 aplicada' as resultado;
