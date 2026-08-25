-- ============================================================
-- CADASTRO DE PARCEIROS / CLIENTES (CRM BASE)
-- Classificação: Importante | Dependência de IA: Baixa
-- Custódio: a definir | Runbook: não iniciado
-- Baseado no mockup: mockup_cadastro_parceiros_v2.html
-- Execução: manual, via SQL Editor do painel Supabase
-- ============================================================

create extension if not exists "pgcrypto";

-- ------------------------------------------------------------
-- Tabela: parceiros
-- ------------------------------------------------------------
create table if not exists public.parceiros (
  id uuid primary key default gen_random_uuid(),
  codigo text not null,
  nome text not null,
  created_at timestamptz not null default now()
);

comment on table public.parceiros is
  'Parceiros de negócios que preenchem o formulário público de cadastro. '
  'Código sem validação contra base externa (decisão registrada: texto livre '
  'por enquanto — risco de duplicidade/erro de digitação assumido).';

-- ------------------------------------------------------------
-- Tabela: clientes
-- ------------------------------------------------------------
create table if not exists public.clientes (
  id uuid primary key default gen_random_uuid(),
  codigo text not null,
  nome text not null,
  parceiro_id uuid not null references public.parceiros(id) on delete restrict,
  status text not null default 'pendente'
    check (status in ('pendente','aprovado','rejeitado')),
  submitted_at timestamptz not null default now(),
  reviewed_by text,
  reviewed_at timestamptz
);

comment on table public.clientes is
  'Clientes cadastrados via formulário público. Toda submissão nasce como '
  '"pendente" e só vira dado oficial após revisão manual (ver política de RLS).';

create index if not exists idx_clientes_codigo on public.clientes (codigo);
create index if not exists idx_clientes_status on public.clientes (status);

-- ------------------------------------------------------------
-- Tabela: contatos
-- ------------------------------------------------------------
create table if not exists public.contatos (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references public.clientes(id) on delete cascade,
  ordem smallint not null check (ordem between 1 and 10),
  nome text not null,
  cargo text,
  telefone text not null,
  email text,
  created_at timestamptz not null default now(),
  unique (cliente_id, ordem)
);

comment on table public.contatos is
  'Até 10 contatos por cliente. Limite reforçado em banco (check + unique), '
  'não só na aplicação.';

-- ------------------------------------------------------------
-- Row Level Security
-- ------------------------------------------------------------
alter table public.parceiros enable row level security;
alter table public.clientes  enable row level security;
alter table public.contatos  enable row level security;

-- A chave pública (anon, usada no formulário) só pode INSERIR.
-- Sem política de SELECT/UPDATE/DELETE para anon = negado por padrão.
-- Leitura/aprovação/edição ficam reservadas à service_role (nunca exposta
-- no frontend) até existir um painel de revisão com autenticação própria.

create policy "anon insere parceiro"
  on public.parceiros
  for insert
  to anon
  with check (true);

create policy "anon insere cliente pendente"
  on public.clientes
  for insert
  to anon
  with check (status = 'pendente');

create policy "anon insere contato"
  on public.contatos
  for insert
  to anon
  with check (true);

-- ============================================================
-- FIM DO SCHEMA INICIAL
-- Pendências conhecidas (não resolvidas neste script, propositalmente):
--   1. Sem validação de código de parceiro contra base externa.
--   2. Sem mecanismo de deduplicação de código de cliente (duas
--      submissões com o mesmo código geram duas linhas "pendente").
--   3. Sem painel de revisão/autenticação — aprovação hoje depende de
--      acesso manual via service_role/SQL Editor.
--   4. Sem aviso de privacidade/LGPD formal fora do checkbox do form.
-- ============================================================
