-- Gera meses e pagamentos aleatórios e devolve: as linhas cruas + o resumo calculado pelo banco.
-- Usado por tests/financeiro-igual-ao-laboratorio.teste.js para provar que o banco calcula igual à tela do laboratório.
\set QUIET on
\pset format unaligned
\pset tuples_only on
begin;
select setseed(0.42);
insert into auth.users (id) values ('10000000-0000-0000-0000-000000000001');
insert into public.odo_clientes (id, user_id, reg, nome)
  select ('30000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, '10000000-0000-0000-0000-000000000001', g, 'Cliente ' || g from generate_series(1, 40) g;
insert into public.odo_fin_meses (user_id, cliente_id, cliente_reg, ano, mes, valor_mes, quitado, abater_credito)
  select '10000000-0000-0000-0000-000000000001', ('30000000-0000-0000-0000-' || lpad(c::text, 12, '0'))::uuid, c,
         case when k <= 2 then 2025 else 2026 end, case when k <= 2 then 10 + k else k - 2 end,
         case when random() < 0.12 then 0 else round((200 + random() * 6000)::numeric, 2) end,
         random() < 0.10, (array[null, true, false, null])[1 + floor(random() * 4)::int]
    from generate_series(1, 40) c, generate_series(1, 13) k
   where random() < 0.85;
insert into public.odo_fin_pagamentos (user_id, mes_id, valor, data, anulado_em)
  select '10000000-0000-0000-0000-000000000001', m.id,
         greatest(10, case when random() < 0.35 then m.valor_mes when random() < 0.5 then round((m.valor_mes * (0.2 + random()))::numeric, 2) else round((50 + random() * 3000)::numeric, 2) end + 0.01 * (random() < 0.05)::int),
         make_date(m.ano, m.mes, 1) + (random() * 50)::int, case when random() < 0.08 then now() end
    from public.odo_fin_meses m, generate_series(1, 3) n
   where random() < 0.45 and m.valor_mes >= 0;
\o /tmp/claude-0/t/f2/fin.json
select jsonb_build_object(
  'M', (select jsonb_agg(to_jsonb(m)) from public.odo_fin_meses m),
  'P', (select jsonb_agg(to_jsonb(p)) from public.odo_fin_pagamentos p),
  'R', (select jsonb_object_agg(m.id, public.odo_fin_mes_resumo(m)) from public.odo_fin_meses m));
\o
rollback;
