-- ============================================================
-- RPC: submit_cadastro
-- Recebe parceiro + cliente + até 10 contatos e insere tudo numa
-- única transação, retornando apenas sucesso/erro (sem expor dados).
-- SECURITY DEFINER: necessário para poder usar RETURNING internamente
-- (linkar os IDs gerados) sem precisar dar SELECT a "anon" nas tabelas.
-- ============================================================

create or replace function public.submit_cadastro(
  p_parceiro_nome    text,
  p_parceiro_codigo  text,
  p_cliente_nome     text,
  p_cliente_codigo   text,
  p_contatos         jsonb  -- array de objetos: {"nome":..,"cargo":..,"telefone":..,"email":..}
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_parceiro_id uuid;
  v_cliente_id  uuid;
  v_contato     jsonb;
  v_ordem       int := 1;
  v_count       int;
begin
  v_count := jsonb_array_length(p_contatos);

  if v_count is null or v_count < 1 then
    raise exception 'É necessário informar ao menos 1 contato.';
  end if;

  if v_count > 10 then
    raise exception 'Máximo de 10 contatos por cliente (recebido: %).', v_count;
  end if;

  if coalesce(trim(p_parceiro_nome), '') = '' or coalesce(trim(p_parceiro_codigo), '') = '' then
    raise exception 'Nome e código do parceiro são obrigatórios.';
  end if;

  if coalesce(trim(p_cliente_nome), '') = '' or coalesce(trim(p_cliente_codigo), '') = '' then
    raise exception 'Nome e código do cliente são obrigatórios.';
  end if;

  insert into public.parceiros (codigo, nome)
  values (p_parceiro_codigo, p_parceiro_nome)
  returning id into v_parceiro_id;

  insert into public.clientes (codigo, nome, parceiro_id, status)
  values (p_cliente_codigo, p_cliente_nome, v_parceiro_id, 'pendente')
  returning id into v_cliente_id;

  for v_contato in select * from jsonb_array_elements(p_contatos)
  loop
    if coalesce(trim(v_contato->>'nome'), '') = '' or coalesce(trim(v_contato->>'telefone'), '') = '' then
      raise exception 'Cada contato precisa de nome e telefone (contato % incompleto).', v_ordem;
    end if;

    insert into public.contatos (cliente_id, ordem, nome, cargo, telefone, email)
    values (
      v_cliente_id,
      v_ordem,
      trim(v_contato->>'nome'),
      nullif(trim(v_contato->>'cargo'), ''),
      trim(v_contato->>'telefone'),
      nullif(trim(v_contato->>'email'), '')
    );
    v_ordem := v_ordem + 1;
  end loop;
end;
$$;

-- Só quem tem EXECUTE explícito pode chamar; revoga qualquer permissão
-- pública implícita antes de conceder especificamente a anon.
revoke all on function public.submit_cadastro(text, text, text, text, jsonb) from public;
grant execute on function public.submit_cadastro(text, text, text, text, jsonb) to anon;

-- ------------------------------------------------------------
-- Endurecimento: com a função cobrindo toda a escrita legítima,
-- as tabelas não precisam mais aceitar INSERT direto de anon.
-- Remove as policies antigas de insert direto (o formulário público
-- passa a usar exclusivamente a função acima).
-- ------------------------------------------------------------
drop policy if exists "anon insere parceiro" on public.parceiros;
drop policy if exists "anon insere cliente pendente" on public.clientes;
drop policy if exists "anon insere contato" on public.contatos;

-- Sem nenhuma policy para anon nas 3 tabelas = acesso negado por padrão
-- em INSERT/SELECT/UPDATE/DELETE direto. Todo acesso público passa a
-- ser exclusivamente via submit_cadastro().
