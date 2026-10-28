---
name: pr-review
description: >
  Revisa um pull request contra um critério de pronto fechado (task do card,
  ADRs, lista de falhas completa, sabotagem, portão do projeto) e entrega um
  rascunho de revisão com veredito: APROVADO quando os critérios são cumpridos,
  mesmo com observações. Na segunda rodada, confere só o que a anterior pediu e
  o que mudou desde então. Use quando o usuário pedir para revisar um PR, seu ou
  de colega. Não posta nada no PR. Para caçar bug num diff sem critério de
  pronto, use /code-review.
disable-model-invocation: true
argument-hint: "<número do PR>"
allowed-tools: Bash(gh pr view *) Bash(gh pr diff *) Bash(gh pr checks *) Bash(gh repo view *) Bash(git fetch *) Bash(git log *) Bash(git diff *) Bash(git show *) Bash(git status *) Bash(git merge-base *) Bash(git worktree list *)
---

# PR Review

A revisão termina quando o critério de pronto é cumprido, não quando o revisor
não acha mais nada para melhorar. Sempre dá para melhorar; isso não é motivo
para segurar um PR.

**Nunca postar, comentar, aprovar ou pedir mudança no PR.** A saída é um
rascunho para o usuário ler, ajustar e postar em nome dele.

---

## Step 0 — Contexto

```bash
gh pr view <n> --json number,title,author,body,baseRefName,headRefName,headRefOid,files,commits
gh pr checks <n>
git fetch origin
```

Ler, na raiz do projeto, o que existir: `AGENTS.md`, `CLAUDE.md`,
`CONTRIBUTING.md`, `.github/pull_request_template.md`, `docs/testes.md` e as
`path_instructions` do `.coderabbit.yaml`. São as regras escritas que o PR
precisa cumprir. Regra que não está escrita em lugar nenhum não bloqueia.

**Card da task.** Procurar o identificador na descrição, no nome da branch e
nos comentários (`CAI-56`, `Trello #59`). Ler pelo MCP do Linear ou do Trello.
Sem card acessível, pedir ao usuário os critérios da task antes de continuar.

**ADRs.** Os citados na descrição e no card, mais os que tratam do que o diff
toca (buscar pelo nome da feature em `docs/adr/`).

**Rodada anterior.** Ler as revisões já feitas:

```bash
gh api "repos/<repo>/pulls/<n>/reviews" -q '.[] | {autor: .user.login, estado: .state, data: .submitted_at, texto: .body}'
```

E a resposta do autor, quando houver: comentário que começa com
`## Revisão:` e lista cada correção como `### N. título (sha)`, com **Teste**,
**Sabotagem**, **Teste existente alterado**, **Decisão registrada** e **Fica
fora deste PR**.

```bash
gh pr view <n> --json comments -q '.comments[] | select(.body | test("^## Revis")) | {data: .createdAt, texto: .body}'
```

Se existe revisão anterior com pedido de mudança, ou uma resposta do autor a
uma revisão, esta é uma **rodada de conferência**: seguir o Step 3 e pular o
Step 2.

---

## Step 1 — Diff do PR

Só o que o PR muda, sem o que veio de merge da base:

```bash
git diff origin/<base>...<head>
```

Código que já existia e o PR não tocou não é revisado, salvo pelo item 3 do
critério (filtro antigo de consulta que passa a devolver mais).

---

## Step 2 — Critério de pronto (primeira rodada)

Conferir **todos** os itens, um por um, até o fim. Não parar quando já houver
achado suficiente: o achado que fica para a rodada seguinte é o que faz a
revisão não terminar.

| # | Critério | Como conferir |
|---|---|---|
| 1 | **Task** | Cada critério do card tem correspondência no diff. Critério do card sem implementação, ou implementação que o card não pede, é achado |
| 2 | **ADRs** | O código segue o que cada ADR do Step 0 decidiu. Citar o ADR e o trecho |
| 3 | **Lista de falhas completa** | Listar toda condição, limite, filtro e valor padrão que o diff escreve, mais os filtros antigos de consulta que passa a devolver mais. Cada um precisa de um item na lista de falhas da descrição do PR. Regra sem item é achado |
| 4 | **Sabotagem** | Cada item da lista tem teste que fica vermelho quando a regra é quebrada. Conferir na descrição e reproduzir uma amostra (abaixo), priorizando as regras que o item 3 achou fora da lista |
| 5 | **Portão** | CI verde (`gh pr checks`) e cada item do checklist do template cumprido |
| 6 | **Bug** | Nenhum comportamento errado com cenário concreto (entrada → resultado errado) que os testes não pegam |

**Reproduzir a sabotagem sem tocar no checkout do usuário:**

```bash
d=$(mktemp -d) && git worktree add "$d" <headRefOid>
```

No worktree, instalar e rodar os testes do jeito que o projeto documenta. Para
cada regra da amostra: quebrar, rodar o teste do arquivo, conferir o vermelho,
desfazer. No fim, `git worktree remove "$d" --force`.

Sem conseguir rodar os testes (banco, serviço ou dependência indisponível): o
critério 4 fica **não reproduzido**, e o veredito não pode ser APROVADO por esse
critério. Dizer o que faltou e perguntar ao usuário como seguir.

---

## Step 3 — Rodada de conferência

Quando já existe revisão anterior pedindo mudança, ou resposta do autor a uma
revisão. A head anterior é a citada na revisão; sem ela, o pai do commit da
primeira correção da resposta.

1. Para cada item pedido antes: **atendido** ou **não atendido**, com a
   evidência (commit, linha, teste). Com resposta do autor, partir dela e
   conferir cada correção:
   - o commit citado existe no PR e mexe no que o item diz;
   - o teste citado existe, com o nome dado, e verifica o que o item pediu;
   - a sabotagem citada fica vermelha de verdade (reproduzir uma amostra, como
     no Step 2);
   - teste existente alterado tem o motivo dito, e a alteração não afrouxa a
     asserção.

   Item pedido antes que não aparece na resposta é **não atendido**. Item em
   "Fica fora deste PR" que era bloqueante não é atendido por estar lá: vai
   para Decisões de produto, para o usuário aceitar ou não o adiamento.
2. O que o PR mudou desde a head revisada antes, sem os merges da base:

   ```bash
   git log --first-parent --no-merges <head-anterior>..<head-atual>
   git diff <head-anterior> <head-atual> -- <arquivos desses commits>
   ```

   Esse trecho novo passa pelo critério de pronto inteiro (Step 2).
3. **Linha que não mudou desde a rodada anterior não gera bloqueante novo**,
   salvo bug com cenário concreto (critério 6). O que a rodada anterior deixou
   passar ali vira observação. O critério só funciona se a rodada não reabre o
   que já passou.

Conflito com a base não é achado de revisão: registrar em uma linha, fora dos
critérios.

---

## Veredito

- **APROVADO:** os seis critérios cumpridos. Observações não mudam o veredito,
  qualquer que seja a quantidade.
- **MUDANÇAS:** algum critério falhou. Cada bloqueante diz qual critério falhou
  e traz a evidência: o item do card, o trecho do ADR, a regra sem item na
  lista, a sabotagem que passou verde, o check vermelho, ou o cenário do bug.

Achado sem critério e sem evidência não é bloqueante. É observação.

Decisão de produto que o PR levanta (algo que nenhum card, ADR ou documento
decide) não bloqueia o código. Vai num bloco próprio, para o usuário decidir.

---

## Rascunho

```markdown
**<APROVADO | MUDANÇAS>** — revisão na head `<sha curto>`.

| # | Critério | Situação | Evidência |
|---|---|---|---|
| 1 | Task | ✓ / ✗ | ... |
| 2 | ADRs | ✓ / ✗ | ... |
| 3 | Lista de falhas | ✓ / ✗ | ... |
| 4 | Sabotagem | ✓ / ✗ / não reproduzido | o que foi quebrado e qual teste pegou |
| 5 | Portão | ✓ / ✗ | ... |
| 6 | Bug | ✓ / ✗ | ... |

## O que precisa mudar
1. **<critério>:** o problema, a evidência e a correção proposta.

## Decisões de produto
- a pergunta, e por que nenhum documento a responde.

## Não precisa fazer nada disso para mesclar
- observações, sem limite de quantidade.
```

Na rodada de conferência, antes da tabela: a lista dos itens anteriores com
atendido ou não atendido. Seção vazia sai do rascunho.

Escrever na língua e no tom das revisões anteriores do PR, quando houver.
