-- =====================================================================
-- 054 · Ideali Odonto · A Inove confirma os pagamentos (como no sistema antigo).
-- A conta espelho continua só de leitura em tudo. A ÚNICA coisa que ela pode fazer
-- é marcar "Confirmado" (ou desfazer) nos pagamentos do laboratório de quem ela é parceira,
-- por uma função que só mexe nesses dois campos.
-- Se você mudar o valor ou trocar o comprovante depois, a confirmação cai sozinha.
-- Traz as 3 confirmações que já existiam no sistema antigo. Pode rodar de novo.
-- =====================================================================
alter table public.odo_fin_pagamentos add column if not exists inove_ok_em timestamptz;
alter table public.odo_fin_pagamentos add column if not exists inove_ok_por uuid;

create or replace function public.odo_inove_confirma(p_ids uuid[], p_ok boolean default true) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  if auth.uid() is null then raise exception 'Entre na sua conta'; end if;
  if coalesce(array_length(p_ids,1),0) = 0 or array_length(p_ids,1) > 200 then return 0; end if;
  perform set_config('odo.inove_confirma','1',true);
  update public.odo_fin_pagamentos p
     set inove_ok_em = case when p_ok then now() else null end,
         inove_ok_por = case when p_ok then auth.uid() else null end
   where p.id = any(p_ids) and p.anulado_em is null
     and (p.user_id = auth.uid() or public.odo_parceiro_de(p.user_id));
  get diagnostics n = row_count;
  perform set_config('odo.inove_confirma','',true);
  return n;
end $$;
revoke all on function public.odo_inove_confirma(uuid[], boolean) from public, anon;
grant execute on function public.odo_inove_confirma(uuid[], boolean) to authenticated;

-- confirmação cai quando o valor muda ou o comprovante é trocado (não quando é só copiado do sistema antigo)
create or replace function public.odo_inove_ok_reseta() returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('odo.inove_confirma', true),'') = '1' then return new; end if;
  new.inove_ok_em := old.inove_ok_em; new.inove_ok_por := old.inove_ok_por;
  if new.valor is distinct from old.valor
     or (old.comprovante_path is not null and new.comprovante_path is distinct from old.comprovante_path)
     or (new.anulado_em is not null and old.anulado_em is null) then
    new.inove_ok_em := null; new.inove_ok_por := null;
  end if;
  return new;
end $$;
drop trigger if exists odo_fin_pag_inove_ok on public.odo_fin_pagamentos;
create trigger odo_fin_pag_inove_ok before update on public.odo_fin_pagamentos
  for each row execute function public.odo_inove_ok_reseta();

-- confirmações que já existiam no sistema antigo
select set_config('odo.inove_confirma','1',false);
update public.odo_fin_pagamentos p set inove_ok_em = x.em
from (values ('a:430c4969-32e5-4d3e-acbb-175f3924931f','2026-09-30 15:55:58.806+00'::timestamptz),
             ('a:c95c347b-abda-4f03-8a0b-06d61b308c44','2026-09-30 15:58:24.286+00'::timestamptz),
             ('a:6e8e3df8-f28a-469d-bc76-31a15f1c47b2','2026-09-26 01:53:57.691+00'::timestamptz)) as x(leg, em)
where p.legado = x.leg and p.inove_ok_em is null;
select set_config('odo.inove_confirma','',false);

select 'ok: 054 aplicada' as resultado;
