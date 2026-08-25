# Cadastro de Parceiros / Clientes (CRM base)

Formulário público para parceiros de negócios da Yamá cadastrarem clientes e seus contatos (até 10 por cliente). As submissões entram como "pendentes" e passam por revisão manual antes de virarem dado oficial.

## Estrutura

- `index.html` — formulário público (identidade visual Yamá aplicada)
- `obrigado.html` — página exibida após envio bem-sucedido
- `sql/` — scripts para rodar manualmente no SQL Editor do Supabase, na ordem:
  1. `schema_cadastro_parceiros.sql` — cria as tabelas (`parceiros`, `clientes`, `contatos`) e RLS inicial
  2. `rpc_submit_cadastro.sql` — cria a função RPC atômica usada pelo formulário e remove os INSERTs diretos (toda escrita pública passa a ser só via essa função)
  3. `migracao_codigo_parceiro_opcional.sql` — torna o código do parceiro opcional e ajusta a função

## Backend

- Supabase, projeto `zsscctppxyjrvzttggns` (conta do departamento de Inteligência Comercial)
- Escrita pública via `anon` key, restrita exclusivamente à função `submit_cadastro` (sem INSERT/SELECT direto nas tabelas)
- A chave usada em `index.html` é a `anon`/`publishable key` — feita para ser pública, não é segredo

## Status do projeto (Ficha de Continuidade)

- Classificação: Importante
- Dependência de IA: Baixa
- Impacto no negócio: sistema pontual, não crítico
- Runbook: não iniciado
- Classificação Exodus: propriedade Yamá — nada sai com o desenvolvedor original

## Pendências conhecidas

- Sem validação de código de parceiro contra base externa
- Sem tela de revisão/aprovação (aprovação hoje é manual, direto no banco)
- Sem aviso de LGPD formal além do checkbox de autorização no formulário
