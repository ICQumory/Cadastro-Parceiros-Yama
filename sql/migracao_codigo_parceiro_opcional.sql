-- ============================================================
-- Ajuste: código do parceiro passa a ser opcional
-- ============================================================

alter table public.parceiros
  alter column codigo drop not null;

-- Recria a função sem exigir p_parceiro_codigo (mantém nome do
-- parceiro como obrigatório, único jeito de saber quem cadastrou).
create or replace function public.submit_cadastro(
  p_parceiro_nome    text,
  p_parceiro_codigo  text,
  p_cliente_nome     text,
  p_cliente_codigo   text,  -- agora representa o CNPJ do cliente
  p_contatos         jsonb
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

  if coalesce(trim(p_parceiro_nome), '') = '' then
    raise exception 'Nome do parceiro é obrigatório.';
  end if;
  -- código do parceiro agora é opcional — sem validação de obrigatoriedade.

  if coalesce(trim(p_cliente_nome), '') = '' or coalesce(trim(p_cliente_codigo), '') = '' then
    raise exception 'Nome e CNPJ do cliente são obrigatórios.';
  end if;

  insert into public.parceiros (codigo, nome)
  values (nullif(trim(p_parceiro_codigo), ''), p_parceiro_nome)
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
