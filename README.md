# claude-code-toolkit

![Claude Code](https://img.shields.io/badge/Claude_Code-D97757?style=for-the-badge&logo=claude&logoColor=white) ![Markdown](https://img.shields.io/badge/Markdown-000000?style=for-the-badge&logo=markdown&logoColor=white) ![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white) ![Docker](https://img.shields.io/badge/Devcontainers-2496ED?style=for-the-badge&logo=docker&logoColor=white) ![MIT](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)

Skills, regras e guardrails que uso no Claude Code para desenvolver com IA sem abrir mão de revisão, testes e segurança. O agente acelera o trabalho, mas as decisões e o entendimento do código continuam comigo.

## Arquitetura

As skills são organizadas em duas camadas:

- **Orquestradoras:** acionadas por mim com `/nome`, conduzem um fluxo completo (TDD, revisão de arquitetura, auditoria de segurança, resumo de mudanças, registro pós-task).
- **Primitivos compartilhados:** acionados pelo próprio modelo quando uma orquestradora precisa deles (vocabulário de design de módulos, interrogação de planos).

As skills são agnósticas de stack: detectam a linguagem em runtime e leem o contexto do repositório (`CLAUDE.md`, ADRs, `CONTEXT.md`) antes de agir.

## Skills

| Skill | Camada | O que faz | Origem |
|---|---|---|---|
| `tdd` | orquestradora | Ciclo red-green com um teste por vez; detecta a stack e checa a saúde da suíte antes de começar | adaptada de mattpocock/skills |
| `arch-review` | orquestradora | Encontra módulos rasos e propõe aprofundamento, com escopo por hot spot do git log | adaptada de mattpocock/skills |
| `sec-review` | orquestradora | Auditoria de segurança ancorada no OWASP Top 10, com filtro de falso positivo; propõe correção, nunca aplica | autoral |
| `change-summary` | orquestradora | Descrição de PR, mensagem de commit ou changelog seguindo a convenção do projeto | autoral |
| `task-log` | orquestradora | Registro de aprendizado pós-task: o que mudou, decisões, alternativas descartadas e ordem de leitura do código | autoral |
| `post-refactor` | orquestradora | Varredura do que vários commits ou PRs deixaram para trás: regressão, erro engolido, duplicação, teste fraco ou instável | autoral, ideia de akitaonrails/my-skills |
| `humanizer` | orquestradora | Reescreve texto com cara de IA (pt-BR e inglês) sem mudar o que ele diz | adaptada de blader/humanizer |
| `verification-planning` | orquestradora | Antes de implementar, define o que precisa virar verdade e que evidência prova cada afirmação; depois, relata o que ficou provado | autoral, ideia de akitaonrails/my-skills |
| `reflect` | orquestradora | Procura nas sessões passadas (ai-memory e transcrições) atrito que se repete e propõe a menor mudança no toolkit; não aplica nada | autoral, ideia de akitaonrails/my-skills |
| `codebase-design` | primitivo | Vocabulário de design de módulos (depth, seam, adapter, leverage, locality) | adaptada de mattpocock/skills |
| `grilling` | primitivo | Interroga um plano em rodadas até esvaziar a árvore de decisão | adaptada de mattpocock/skills |

## Guardrails

- **Permissões** (`settings.example.json`): qualquer comando git que altera histórico (commit, push, merge, rebase, reset, checkout, branch, stash) exige confirmação.
- **Bloqueio de leitura de segredos:** regras `deny` impedem o agente de ler `.env`, variações e a pasta `secrets/`, mesmo que ele tente. A regra do `CLAUDE.md` pede; a permissão garante.
- **Hook PreToolUse (`bloquear-env.mjs`):** cobre o que as regras `deny` de `Read` não alcançam. Recusa qualquer ferramenta que mire um `.env` (um `cat .env` no Bash, um `Grep` com glob `**/.env`, uma edição), deixando passar `.env.example`.
- **Hook PostToolUse:** registra em log cada arquivo que o agente escreve ou edita.
- **Hook UserPromptSubmit:** bloqueia o envio de prompts que contenham tokens, chaves de API, chaves privadas ou URLs de banco com senha, antes que cheguem ao modelo.
- **`CLAUDE.md` global:** regras de trabalho do agente. Entre elas: parar quando inventar uma regra de negócio, nunca pular ou apagar teste que falha, não alterar credenciais e não instalar dependência sem perguntar.
- **Devcontainers com token de escopo mínimo** (guia em [`docs/devcontainer.md`](docs/devcontainer.md), procedimento do token em [`docs/runbook-gh-token.md`](docs/runbook-gh-token.md)): o agente roda isolado, com um token GitHub fine-grained limitado aos repositórios necessários.

## Memória entre sessões

A pasta [`ai-memory/`](ai-memory/) roda o [ai-memory](https://github.com/akitaonrails/ai-memory) num container próprio e o liga aos devcontainers: hooks registram cada sessão, a seguinte recebe um resumo do que ficou em aberto e o agente pesquisa a memória por MCP. Os atalhos `dc`/`dcr`/`dcsh` de [`ai-memory/dc.sh`](ai-memory/dc.sh) ligam o container à rede do servidor e passam a chave, sem configuração por projeto. Um filtro garante que prompt barrado por conter segredo não seja gravado. Riscos e instalação no [README da pasta](ai-memory/README.md).

## Como usar

```bash
git clone https://github.com/Molimpion/claude-code-toolkit.git ~/.claude/toolkit
mkdir -p ~/.claude/skills
cd ~/.claude/skills
for s in ../toolkit/skills/*/; do n=$(basename "$s"); ln -s "../toolkit/skills/$n" "$n"; done
```

O clone fica dentro de `~/.claude` e os links são relativos para funcionarem também nos devcontainers, que montam só `~/.claude`: um link para fora dessa pasta aponta para um caminho que não existe dentro do container, e as skills somem sem aviso.

Cada skill vira um symlink próprio dentro de `~/.claude/skills/`, em vez de a pasta inteira apontar para o repo: o Claude Code grava ali as skills sincronizadas da conta (`synced/`), e elas não podem cair dentro do repositório. Se já existir em `~/.claude/skills/` uma skill com o mesmo nome, remova-a antes; caso contrário o link é criado dentro dela.

Mescle `settings.example.json` ao seu `~/.claude/settings.json` e adapte o `CLAUDE.md` ao seu contexto antes de copiá-lo para `~/.claude/`.

## Créditos e licença

`tdd`, `arch-review`, `codebase-design` e `grilling` são adaptações de [mattpocock/skills](https://github.com/mattpocock/skills), sob licença MIT (ver `THIRD_PARTY_LICENSES/`). `humanizer` é adaptação de [blader/humanizer](https://github.com/blader/humanizer), de Siqi Chen, também MIT. `post-refactor`, `verification-planning` e `reflect` são autorais, a partir de ideias de [akitaonrails/my-skills](https://github.com/akitaonrails/my-skills); aquele repositório não tem licença, então nenhum texto dele é reproduzido aqui. A integração em `ai-memory/` usa o [ai-memory](https://github.com/akitaonrails/ai-memory), de [Fabio Akita](https://github.com/akitaonrails), também MIT; nenhum código dele é distribuído aqui, os scripts de hook são extraídos da imagem oficial na instalação. O restante é distribuído sob licença MIT (ver `LICENSE`).
