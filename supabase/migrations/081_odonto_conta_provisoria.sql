-- 081 · Conta provisória (login anônimo do Supabase) durante o cadastro.
-- A pessoa digita só o e-mail, faz o cadastro inteiro numa conta provisória e, no fim, confirma o e-mail e cria a senha.
-- Enquanto a conta é provisória ela mexe SÓ nos próprios dados: não lista a Rede, não busca laboratórios,
-- não convida ninguém, não manda mensagem e não cria link de cliente.
-- Antes de rodar: Supabase → Authentication → Sign In / Providers → ligar "Allow anonymous sign-ins".
-- Pode rodar mais de uma vez.

create or replace function public.odo_nao_provisoria() returns boolean
language sql stable set search_path = '' as $$
  select not coalesce((auth.jwt()->>'is_anonymous')::boolean, false)
$$;
grant execute on function public.odo_nao_provisoria() to anon, authenticated;

-- Coloca uma trava no começo das funções que mostram dados de outras pessoas ou agem sobre outras contas.
do $$
declare f record; corpo text; novo text; def text;
begin
  for f in
    select p.oid, p.proname, l.lanname, p.prosrc, p.proretset
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace join pg_language l on l.oid = p.prolang
     where n.nspname = 'public'
       and p.proname in ('odo_rede_profs','odo_rede_pre','odo_rede_empresas','odo_lab_busca','rede_stats',
                         'odo_lab_convida','odo_lab_responde','odo_lab_vincula_cliente','odo_parceiro_aceita',
                         'caixa_enviar','caixa_info','criar_link_cliente')
  loop
    if position('odo_nao_provisoria' in f.prosrc) > 0 then continue; end if;
    corpo := f.prosrc;
    if f.lanname = 'plpgsql' then
      novo := regexp_replace(corpo, '\mbegin\M',
        'begin if not public.odo_nao_provisoria() then raise exception ''Confirme o seu e-mail para usar isto.'' using errcode = ''42501''; end if;', 'i');
    elsif f.lanname = 'sql' then
      corpo := regexp_replace(corpo, ';\s*$', '');
      if f.proretset then
        novo := E'\n  select * from (' || corpo || E'\n  ) _g where public.odo_nao_provisoria();\n';
      else
        novo := E'\n  select (' || corpo || E'\n  ) where public.odo_nao_provisoria();\n';
      end if;
    else continue;
    end if;
    if novo = f.prosrc then raise exception 'Não consegui travar %', f.proname; end if;
    def := pg_get_functiondef(f.oid);
    def := replace(def, f.prosrc, novo);
    execute def;
  end loop;
end $$;

-- Currículos publicados do Ideali CAD: conta provisória vê só o próprio.
drop policy if exists perfil_rede_so_conta_real on public.perfil_rede;
create policy perfil_rede_so_conta_real on public.perfil_rede as restrictive for select to authenticated
  using (user_id = auth.uid() or public.odo_nao_provisoria());
