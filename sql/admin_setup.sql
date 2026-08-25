-- ============================================================
-- Painel de Administração — acesso por senha única (hash bcrypt)
-- ============================================================
-- Risco conhecido e aceito: senha única compartilhada, sem limite
-- de tentativas (sem rate limiting/lockout). Adequado apenas como
-- controle de acesso básico para uso interno, não como segurança
-- forte — mesma categoria de risco já documentada no Scorecard RCA.
-- ============================================================

create table if not exists public.admin_settings (
  key   text primary key,
  value text not null
);

alter table public.admin_settings enable row level security;
-- Sem nenhuma policy para anon = bloqueado por padrão em SELECT/INSERT/
-- UPDATE/DELETE direto. Só acessível via as funções SECURITY DEFINER abaixo.

-- Define/atualiza a senha (rode isso uma vez; para trocar a senha depois,
-- rode de novo com o novo valor).
insert into public.admin_settings (key, value)
values ('admin_password_hash', crypt('cah251120', gen_salt('bf')))
on conflict (key) do update set value = excluded.value;

-- ------------------------------------------------------------
-- Verifica a senha sem nunca expor o hash pra fora do banco.
-- ------------------------------------------------------------
create or replace function public.admin_verify(p_senha text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_hash text;
begin
  select value into v_hash from public.admin_settings where key = 'admin_password_hash';
  if v_hash is null then
    return false;
  end if;
  return v_hash = crypt(p_senha, v_hash);
end;
$$;

revoke all on function public.admin_verify(text) from public;
grant execute on function public.admin_verify(text) to anon;

-- ------------------------------------------------------------
-- Lista todos os cadastros (clientes + parceiro + contatos aninhados).
-- ------------------------------------------------------------
create or replace function public.admin_list_cadastros(p_senha text)
returns table (
  cliente_id      uuid,
  cliente_codigo  text,
  cliente_nome    text,
  status          text,
  submitted_at    timestamptz,
  parceiro_nome   text,
  parceiro_codigo text,
  contatos        jsonb
)
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if not public.admin_verify(p_senha) then
    raise exception 'Senha incorreta.';
  end if;

  return query
  select
    c.id,
    c.codigo,
    c.nome,
    c.status,
    c.submitted_at,
    p.nome,
    p.codigo,
    coalesce(
      (select jsonb_agg(jsonb_build_object(
         'ordem', ct.ordem, 'nome', ct.nome, 'cargo', ct.cargo,
         'telefone', ct.telefone, 'email', ct.email
       ) order by ct.ordem)
       from public.contatos ct where ct.cliente_id = c.id),
      '[]'::jsonb
    ) as contatos
  from public.clientes c
  join public.parceiros p on p.id = c.parceiro_id
  order by c.submitted_at desc;
end;
$$;

revoke all on function public.admin_list_cadastros(text) from public;
grant execute on function public.admin_list_cadastros(text) to anon;

-- ------------------------------------------------------------
-- Apaga um cadastro (cliente + contatos, via cascade da FK).
-- Não apaga o parceiro — ele pode estar ligado a outros clientes.
-- ------------------------------------------------------------
create or replace function public.admin_delete_cadastro(p_senha text, p_cliente_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if not public.admin_verify(p_senha) then
    raise exception 'Senha incorreta.';
  end if;

  delete from public.clientes where id = p_cliente_id;
  -- contatos são apagados automaticamente (on delete cascade no schema).
end;
$$;

revoke all on function public.admin_delete_cadastro(text, uuid) from public;
grant execute on function public.admin_delete_cadastro(text, uuid) to anon;

-- ------------------------------------------------------------
-- Atualiza o status de um cadastro (pendente/aprovado/rejeitado).
-- reviewed_by fica fixo como 'admin' — limitação conhecida: como o
-- acesso é por senha única compartilhada, não há como saber QUAL
-- pessoa aprovou/rejeitou, só QUE alguém com a senha o fez.
-- ------------------------------------------------------------
create or replace function public.admin_update_status(
  p_senha       text,
  p_cliente_id  uuid,
  p_novo_status text
)
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  if not public.admin_verify(p_senha) then
    raise exception 'Senha incorreta.';
  end if;

  if p_novo_status not in ('pendente', 'aprovado', 'rejeitado') then
    raise exception 'Status inválido: %', p_novo_status;
  end if;

  update public.clientes
  set status = p_novo_status,
      reviewed_by = 'admin',
      reviewed_at = now()
  where id = p_cliente_id;
end;
$$;

revoke all on function public.admin_update_status(text, uuid, text) from public;
grant execute on function public.admin_update_status(text, uuid, text) to anon;
