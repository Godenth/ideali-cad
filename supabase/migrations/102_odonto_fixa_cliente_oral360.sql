-- 102 — Corrige o cliente dos pedidos antigos da "Oral 360 Copa" que estavam sem cliente_id.
-- Com isso, ao vincular a clínica ao cliente "Oral 360 Copa", todos os pedidos antigos aparecem.
update public.odo_pedidos
   set cliente_id = 'd0e04e35-4aab-4618-babc-b5504f4d28d0'
 where numero in (291, 292, 293, 294)
   and cliente_nome = 'Oral 360 Copa'
   and cliente_id is null
   and user_id = 'd75221a8-18c5-411e-a120-98647eb8af0e';
