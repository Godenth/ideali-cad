-- =====================================================================
-- 047 · Ideali Odonto · Corrige o mês do financeiro importado.
-- No sistema antigo o mês era guardado começando do zero (0 = janeiro, 9 = outubro).
-- No sistema novo é 1 = janeiro. A importação 044 copiou o número sem ajustar,
-- então tudo ficou um mês antes (outubro aparecia como setembro).
-- Soma 1 no mês SÓ das linhas que vieram do sistema antigo.
-- Trava: se já existir outubro/2026 vindo do sistema antigo, é porque já rodou, e não faz nada.
-- =====================================================================
do $c$ declare r record; n int := 0; begin
  if exists (select 1 from public.odo_fin_meses where legado like 'm:%' and ano = 2026 and mes = 10) then
    raise notice 'A 047 já tinha sido rodada. Nada mudou.'; return; end if;
  -- do mês mais alto para o mais baixo, para nunca bater com outro mês do mesmo cliente
  for r in select id from public.odo_fin_meses where legado like 'm:%' order by ano desc, mes desc loop
    update public.odo_fin_meses set ano = case when mes = 12 then ano + 1 else ano end,
                                    mes = case when mes = 12 then 1 else mes + 1 end
     where id = r.id;
    n := n + 1;
  end loop;
  update public.odo_fin_comissoes set ano = case when mes = 12 then ano + 1 else ano end,
                                      mes = case when mes = 12 then 1 else mes + 1 end
   where legado like 'c:%' and mes is not null;
  raise notice 'meses corrigidos: %', n;
end $c$;
select ano, mes, count(*) clientes, sum(valor_mes) faturado from public.odo_fin_meses group by ano, mes order by 1, 2;
