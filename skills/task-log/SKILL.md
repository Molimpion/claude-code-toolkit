---
name: task-log
description: Gera um registro de aprendizado ao final de uma task — o que mudou, quais decisões foram tomadas, em que ordem ler o código e perguntas de verificação. Use quando o usuário terminar uma unidade de trabalho e pedir para registrar, documentar ou entender o que foi feito. NÃO use para gerar descrição de PR, mensagem de commit ou changelog — para isso use a skill change-summary.
---

# task-log

Registro pós-task escrito para **quem vai estudar o código**, não para quem vai revisar o PR.

## Princípio

O diff é a fonte de verdade. Este documento não substitui a leitura do código — ele diz
**onde olhar, em que ordem e o que perguntar**. Se um trecho do resumo não puder ser
apontado para uma linha real do código, ele não entra no arquivo.

## Saída

Raiz do repo via `git rev-parse --show-toplevel`. Determine o destino nesta ordem —
**respeite a estrutura que já existe, não imponha uma nova**:

1. Se existir `docs/tasks/log/` → use.
2. Se existir `docs/tasks/` (ou variação: `docs/task/`, `doc/tasks/`) → crie e use o
   subdiretório `log/` dentro dela.
3. Se existir `docs/` mas sem pasta de tasks → crie `docs/tasks/log/`.
4. Se não existir `docs/` → crie `docs/tasks/log/` na raiz.

Antes de decidir, rode `git ls-files 'doc*/**' | sed 's|/[^/]*$||' | sort -u` para ver a
convenção real do repositório (ex.: `docs/adrs` vs `docs/adr` — não crie uma variante nova
ao lado de uma existente).

`docs/tasks/` é onde o usuário escreve a descrição da task **antes** de começar. Este
registro é o que foi feito **depois** — por isso vai no subdiretório `log/`. Nunca escreva
direto em `docs/tasks/`.

Arquivo: `YYYY-MM-DD-<slug-da-task>.md`. Nunca sobrescreva — sufixe com `-2`, `-3`.

Se o repositório tiver `CLAUDE.md` ou `CONTRIBUTING.md` definindo onde vai documentação,
essa instrução vence esta seção.

## Passo 0 — Reconhecimento do projeto

Antes de qualquer coisa, entenda com o que você está lidando. **Não leia o projeto
inteiro** — leia os pontos que revelam stack e convenção:

1. Estrutura: `git ls-files | head -200` e, em repo grande,
   `git ls-files | sed 's|/[^/]*$||' | sort -u | head -60`
2. Manifestos, o que existir: `package.json`, `pom.xml`, `build.gradle`,
   `requirements.txt`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `composer.json`,
   `*.csproj`, `Gemfile`
3. Infra: `docker-compose.yml`, `Dockerfile`, `Makefile`, `.github/workflows/`
4. Convenção do projeto: `CLAUDE.md`, `CONTEXT.md`, `CONTRIBUTING.md`, `README.md`,
   `docs/adr/`
5. Saída de `repomix` se houver arquivo gerado no repo

Disso extraia: linguagem e versão, framework, gerenciador de pacotes, runner de teste,
camadas e estrutura de pastas, convenções escritas. **Nunca assuma um stack padrão** —
tudo vem do repositório. Se algo essencial não for identificável, pergunte em vez de supor.

Leia código-fonte apenas dos arquivos que a task tocou (Passo 1), mais os vizinhos diretos
necessários para explicar as decisões.

## Passo 1 — Levantar o que mudou de fato

Determine a linha de base, nesta ordem:

1. Se `git rev-parse HEAD` falha (repositório sem commits) → **modo projeto novo**.
   Use `git status --short` e `git ls-files --others --exclude-standard`.
   Não tente gerar diff.
2. Se a task já tem commits próprios → `git diff <base>...HEAD`, onde base é a branch
   de origem.
3. Caso contrário → `git status --short`, `git diff --stat HEAD`, `git diff HEAD`.

Se não houver mudança nenhuma — nem arquivo novo, nem commit, nem working tree sujo —
**pare** e avise o usuário. Não escreva um arquivo baseado na memória da conversa.

## Passo 2 — Escrever o arquivo

Esqueleto:

```markdown
# <título da task>

**Data:** YYYY-MM-DD
**Stack:** <linguagem, versão, framework — do Passo 0>
**Escopo:** <uma frase: qual problema essa task resolve>

## O que mudou

<saída literal de `git diff --stat`, em bloco de código>

Uma linha por arquivo — o que aquele arquivo passou a fazer:

- `caminho/do/arquivo` — <o que mudou ali>

## Decisões

Uma seção por decisão. Só entram decisões onde havia mais de um caminho razoável.
Refatoração óbvia e renomeação não são decisão.

### <decisão>
- **Escolha:** <o que foi feito>
- **Alternativas descartadas:** <o que também funcionaria, e por que não foi escolhido>
- **Custo:** <o que essa escolha torna mais difícil depois>
- **Onde ver no código:** `arquivo:linha`

## Ordem de leitura

Numerada, do ponto de entrada até o detalhe. Cada item diz o que procurar naquele arquivo.

1. `arquivo` — <o que entender aqui antes de seguir>

## Conceitos usados

Só o que apareceu no código e o usuário pode não conhecer. Nome + uma frase + onde aparece.
Sem tutorial.

## Perguntas

De 3 a 5 perguntas sobre este código específico, **sem resposta no arquivo**. Devem exigir
leitura do código — não podem ser respondíveis lendo só este documento. Foque em:
por que aqui e não ali, o que quebra se mudar X, qual caso não está coberto.

## Pendências

O que ficou incompleto, com TODO, ou foi deliberadamente adiado.
```

### Modo projeto novo

Quando não há commit anterior, ajuste:

- "O que mudou" vira **"Estrutura criada"**: árvore de diretórios e uma linha por arquivo
  dizendo qual responsabilidade ele carrega.
- "Decisões" e "Ordem de leitura" passam a ser as seções principais — em projeto do zero
  quase tudo é decisão.
- Em "Decisões", inclua obrigatoriamente: escolha da estrutura de pastas, cada dependência
  adicionada e por quê, e o que foi deixado de fora de propósito.

## Regras

- **Não elogie o próprio trabalho.** Nada de "implementação limpa" ou "solução robusta".
  Descrição factual.
- **Aponte fraquezas.** Falta de teste, tratamento de erro incompleto, acoplamento
  indesejado, decisão tomada por conveniência — tudo isso vai em **Pendências**.
  Um registro que só mostra acerto não ensina nada.
- **Seção vazia é removida**, não preenchida com enchimento.
- **Não duplique o diff em prosa.** Se a informação está no diff, aponte para ela.
- Se a task tocou mais de ~15 arquivos, avise o usuário que a task era grande demais para
  um registro útil e sugira commits menores nas próximas.

## Depois de gerar

Informe o caminho do arquivo e repita as **Perguntas** no chat. Não responda a elas.
Se o usuário responder, corrija apontando o trecho exato do código.
