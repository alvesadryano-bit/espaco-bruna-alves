# Espaço Bruna Alves

Sistema de gestão para salão/estética em Vite + Supabase. O frontend usa Supabase Auth, RLS e RPCs transacionais para agenda, estoque, financeiro e comissões.

## Estado do projeto

### Operacional no frontend

- Login e confirmação de e-mail; cadastro público removido.
- Área **Usuários** para convites, perfis de administrador/recepcionista/profissional, alteração e remoção de acessos.
- Novas contas entram na empresa existente por convite pessoal; a criação de novas empresas está bloqueada.
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

## Convites e contas da equipe

A tela pública não oferece cadastro. A administradora informa nome e e-mail em **Usuários**, escolhe o perfil e envia o link à pessoa. O link exige o mesmo e-mail do convite, expira em 7 dias e vincula a nova conta à empresa já existente. Ao escolher **Profissional**, a plataforma cria automaticamente a ficha da agenda com o nome informado; o uso de um profissional já cadastrado fica disponível como opção para preservar histórico.

O Supabase Auth precisa continuar aceitando criação de usuários por e-mail para que o link de convite possa concluir o cadastro. Isso não libera dados: sem aceitar um convite válido, a conta não recebe `business_membership` e permanece sem acesso. Configure `https://espacobrunaalves.vercel.app/**` em **Authentication → URL Configuration → Redirect URLs** para a confirmação de e-mail retornar ao convite.

## Senhas e recuperação

- Qualquer usuário conectado pode abrir **Alterar minha senha**, confirmar a senha atual e definir uma nova.
- A tela de login oferece **Esqueci minha senha** sem revelar se o e-mail está cadastrado.
- Em **Usuários**, a administradora pode enviar o link oficial de redefinição para uma pessoa ativa.
- A administradora nunca vê nem escolhe a nova senha; a pessoa cria a senha no fluxo seguro do Supabase antes de continuar para a plataforma.
- O navegador usa apenas `resetPasswordForEmail` e `updateUser` com a chave pública. Nenhuma API administrativa ou `service_role` é exposta.

O redirecionamento usa `https://espacobrunaalves.vercel.app?password-reset=1`, coberto pela regra curinga recomendada acima.

## Migrations

A migration base abaixo foi aplicada manualmente anteriormente e **não deve ser executada de novo**:

- `20261012000000_core_scheduling.sql`

Aplique uma única vez, nesta ordem:

1. `20261012010000_frontdesk_client_visibility.sql`
2. `20261012020000_management_modules.sql`
3. `20261012030000_user_access_management.sql`
4. `20261012040000_user_invitation_names.sql`

As três primeiras já podem estar aplicadas no ambiente de produção. A terceira adiciona convites internos, perfis, revogação de acessos e bloqueia a criação de empresas adicionais. A quarta adiciona o nome ao convite e permite criar automaticamente a ficha de um novo profissional.

As migrations dos módulos criam tabelas, RLS e RPCs para:

- produtos, saldos e movimentações de estoque;
- comandas, itens, pagamentos e despesas;
- lançamentos e repasses de comissão;
- fechamento atômico do atendimento, financeiro e comissão;
- convites de usuários com validade, vínculo de perfil e proteção contra remoção do último administrador;
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
2. Aplicar as migrations pendentes na ordem documentada.
3. Testar uma sessão administradora com dados reais e gerar um convite na área Usuários.
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
