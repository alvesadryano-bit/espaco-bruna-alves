# Espaço Bruna Alves

Sistema de gestão para salão/estética em Vite + Supabase. O frontend usa Supabase Auth, RLS e RPCs transacionais para agenda, estoque, financeiro e comissões.

## Estado do projeto

### Operacional no frontend

- Login/cadastro e confirmação de e-mail.
- Criação inicial da empresa, unidade, profissional e serviço.
- Clientes, agenda diária, fila de encaixe e reagendamento por Kanban.
- Estoque real: produtos, saldo por unidade, entradas, consumo, perdas, devoluções, ajustes, custo médio e histórico.
- Financeiro real: fechamento de comandas, múltiplas formas de pagamento, descontos, despesas e saldo realizado.
- Comissões reais: regras gerais ou por profissional, cálculo no fechamento da comanda e repasses.

### Ainda fora deste escopo

- Edição completa de clientes e serviços.
- Visão semanal conectada ao Supabase.
- Consumo automático de insumos por ficha técnica do serviço.
- Venda avulsa de produtos sem um atendimento.
- Estornos de comandas e conciliação bancária.

## Segurança das chaves

O navegador deve receber **somente** uma chave `sb_publishable_...` (ou `anon` legada). Chaves `sb_secret_...`, `service_role`, tokens pessoais do Supabase e tokens do GitHub nunca podem aparecer em variáveis `VITE_*`, arquivos `.env` versionados ou mensagens.

O comando `npm run build` executa `scripts/validate-public-env.mjs` antes do Vite e bloqueia o build se detectar uma chave privilegiada.

```bash
VITE_SUPABASE_URL=https://SEU-PROJETO.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_COLE_A_CHAVE_PUBLICA
```

Se uma `service_role` já foi publicada no bundle, substitua-a por uma chave publishable, faça novo deploy e desative/revogue a chave legada comprometida no Supabase. Trocar apenas a variável da Vercel não invalida o segredo que já ficou público.

## Migrations

A migration base abaixo foi aplicada manualmente anteriormente e **não deve ser executada de novo**:

- `20261012000000_core_scheduling.sql`

Aplique uma única vez, nesta ordem:

1. `20261012010000_frontdesk_client_visibility.sql`
2. `20261012020000_management_modules.sql`

A migration dos módulos cria tabelas, RLS e RPCs para:

- produtos, saldos e movimentações de estoque;
- comandas, itens, pagamentos e despesas;
- lançamentos e repasses de comissão;
- fechamento atômico do atendimento, financeiro e comissão;
- trilha no `audit_logs` para operações críticas.

Como a migration base foi aplicada manualmente pelo SQL Editor, alinhe o histórico remoto/local antes de executar `supabase db push`. Não tente reaplicar a base.

## Rodar localmente

Requer Node.js 20.19+.

```bash
npm ci
cp .env.example .env.local
npm run dev
```

Sem Supabase configurado, o app mostra uma tela de configuração. O protótipo visual local pode ser aberto em `/?demo=1`; para revisar os três módulos novos com dados locais, use `/?demo=1&management=1`. Esses bypasses só funcionam em desenvolvimento.

```bash
npm test
npm run build
npm run preview
```

## Validação antes da produção

1. Confirmar que o bundle contém uma chave `sb_publishable_...`, nunca `service_role`/`sb_secret_...`.
2. Aplicar as duas migrations pendentes na ordem documentada.
3. Testar uma sessão administradora com dados reais.
4. Cadastrar produto e validar entrada, saída e bloqueio de saldo negativo.
5. Configurar regra de comissão e fechar uma comanda com PIX e pagamento dividido.
6. Confirmar que atendimento, pagamento e comissão são atualizados juntos.
7. Registrar despesa e conferir o saldo do mês.
8. Registrar repasse e validar a visão do profissional.
9. Testar RLS com administrador, recepcionista e profissional.
10. Só então promover o deploy para produção.

## Vercel

Configure em **Production**, **Preview** e **Development**, conforme necessário:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`

Alterações de variáveis só entram em um novo deployment. O `vercel.json` adiciona cabeçalhos de segurança, bloqueio de indexação e a política de conexão limitada ao projeto Supabase atual.
