-- Relatório (SÓ LEITURA) — pedidos que podem estar repetidos no Ideali CAD.
-- Rode no SQL Editor do Supabase (projeto IDEALI CAD). Nada é alterado.
-- Regra: mesmo cliente + mesmo paciente (sem diferenciar maiúscula/minúscula nem acento)
--        + pelo menos 1 dente em comum + mesmo tipo de trabalho
--        + criados com até 30 dias de diferença.
-- Não conta pedidos apagados, cancelados ou arquivados.
with base as (
  select p.user_id, p.id, p.numero, p.cliente_id, p.paciente,
         regexp_replace(
           lower(translate(p.paciente,
             'ÁÀÂÃÄÅáàâãäåÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÕÖóòôõöÚÙÛÜúùûüÇçÑñ',
             'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCcNn')),
           '\s+', ' ', 'g') as pac_norm,
         p.elementos, p.tipo_trabalho_id, p.recebido_em, p.valor, p.status
  from public.pedidos p
  where p.deleted_at is null
    and p.cancelado_em is null
    and p.status <> 'arquivado'
)
select least(a.numero, b.numero)    as pedido_a,
       greatest(a.numero, b.numero) as pedido_b,
       c.nome                        as cliente,
       a.paciente                    as paciente,
       t.nome                        as tipo,
       a.elementos                   as dentes_a,
       b.elementos                   as dentes_b,
       a.recebido_em                 as data_a,
       b.recebido_em                 as data_b,
       a.valor                       as valor_a,
       b.valor                       as valor_b,
       a.status                      as status_a,
       b.status                      as status_b,
       abs(a.recebido_em - b.recebido_em) as dias_diferenca
from base a
join base b
  on a.user_id = b.user_id
 and a.id < b.id
 and a.cliente_id = b.cliente_id
 and a.pac_norm = b.pac_norm
 and a.tipo_trabalho_id is not distinct from b.tipo_trabalho_id
 and a.elementos && b.elementos
 and abs(a.recebido_em - b.recebido_em) <= 30
left join public.clientes c        on c.id = a.cliente_id and c.user_id = a.user_id
left join public.tipos_trabalho t  on t.id = a.tipo_trabalho_id and t.user_id = a.user_id
order by data_b desc, pedido_a;
