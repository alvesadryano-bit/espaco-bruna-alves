# Espaço Bruna Alves

Sistema de gestão para salão/estética. O layout aprovado permanece como base; o app está sendo conectado ao Supabase e preparado para GitHub/Vercel.

## Estado do projeto

- A migration base `supabase/migrations/20261012000000_core_scheduling.sql` foi aplicada manualmente no Supabase e **não deve ser executada novamente**.
- A migration complementar `20261012010000_frontdesk_client_visibility.sql` foi criada depois de corrigir a leitura de clientes da recepção e os privilégios das RPCs. **Ela ainda precisa ser aplicada uma única vez** no SQL Editor do Supabase antes de validar o fluxo da recepção.
- Login/cadastro, confirmação de e-mail, criação da empresa/unidade, cadastro inicial de profissional/serviço, leitura do catálogo e da agenda, criação de cliente/agendamento/fila e reagendamento pelo Kanban estão ligados ao Supabase no frontend.
- Estoque, caixa/checkout, financeiro, comissões, histórico técnico completo, gestão de usuários/equipe e edição de clientes/serviços ainda não foram conectados aos dados reais. Essas áreas demonstrativas ficam ocultas no modo autenticado; não publicar o protótipo demonstrativo como produção.
- `npm run build` passou depois das alterações. **Ainda não houve teste end-to-end com uma sessão e dados reais do Supabase.**
- `api/` é um scaffold NestJS/Prisma exploratório anterior e não integra o fluxo atual Vite/Supabase/Vercel.

## Rodar localmente

Requer Node.js 20.19+.

```bash
npm ci
npm run dev
```

O arquivo `.env.local` já está presente e ignorado pelo Git. Se estiver preparando um clone, copie `.env.example` para `.env.local` e defina somente a URL do Supabase e a chave anon/public. Nunca use `service_role` no navegador.

Sem configuração válida do Supabase, o app mostra uma tela de configuração em vez de iniciar com dados fictícios. Durante desenvolvimento local, o protótipo isolado pode ser aberto explicitamente em `/?demo=1`; esse bypass é desativado em builds de produção.

```bash
npm run build
npm run preview
```

## Supabase e primeiro acesso

1. No SQL Editor do Supabase, aplique **somente** `20261012010000_frontdesk_client_visibility.sql`. A migration base já está aplicada.
2. Em Authentication → URL Configuration, configure a URL local e as URLs de produção permitidas. O fluxo de confirmação retorna para a origem atual (`window.location.origin`).
3. Crie a conta administradora na tela de cadastro; confirme o e-mail se o projeto exigir confirmação.
4. Entre, cadastre a empresa **Espaço Bruna Alves**, a unidade principal, o primeiro profissional e um serviço.
5. Cadastre uma cliente e então teste um agendamento futuro. A RPC do banco valida permissões, serviço habilitado, bloqueios e conflito de horário.
6. Teste a fila de encaixe e o reagendamento por arrastar/selecionar no Kanban. O servidor continua sendo a autoridade final de disponibilidade.

A chave anon/public pode estar no frontend porque as tabelas usam RLS; a chave `service_role` jamais deve ser colocada em `VITE_*`, `.env.local` do cliente, no Git ou no navegador.

### Histórico de migrations

A migration base foi aplicada manualmente pelo SQL Editor e não foi registrada via Supabase CLI. Antes de qualquer `supabase db push`, alinhe o histórico remoto/local; não tente reaplicar a migration base. O projeto não foi publicado nem conectado à Vercel.

## GitHub e Vercel

- Repositório informado: `https://github.com/alvesadryano-bit/espaco-bruna-alves`.
- Build Vite gera `dist/`; `vercel.json` contém configuração inicial.
- Na Vercel, configure `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` nos ambientes corretos e inclua o domínio de produção na lista de redirect URLs do Supabase.
- Nenhum commit, push ou deploy foi feito nesta etapa. Faça deploy de produção somente depois de aplicar a migration complementar e testar login, RLS, agenda, cadastro de cliente e Kanban com dados reais.
