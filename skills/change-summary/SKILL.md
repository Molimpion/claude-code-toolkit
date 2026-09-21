---
name: change-summary
description: >
  Resume mudanças de código em descrição de PR, mensagem de commit ou entrada de
  changelog, seguindo a convenção que o projeto já usa. Use quando o usuário pedir
  para descrever um PR, escrever mensagem de commit, gerar entrada de changelog,
  ou resumir o que mudou numa branch.
disable-model-invocation: true
argument-hint: "[pr | commit | changelog] [range opcional]"
allowed-tools: Bash(git diff *) Bash(git log *) Bash(git status *) Bash(git branch *) Bash(git merge-base *)
---

# Change Summary

Descreve **o que mudou e por quê**, no formato que o projeto já usa.

O produto é intenção, não inventário. "Modificado UserService, 3 métodos novos" é
o `git diff` com mais palavras — não serve. "Usuários agora exportam relatório em
CSV" serve.

---

## Step 1 — Determinar o escopo

Se o usuário passou um range, usar. Senão, nesta ordem:

```bash
git status --short
git branch --show-current
git merge-base --fork-point origin/main HEAD 2>/dev/null || git merge-base origin/main HEAD
```

| Situação | Escopo |
|---|---|
| há mudanças em stage | o que está em stage |
| branch diferente da principal | da divergência com a principal até HEAD |
| nenhum dos dois | último commit, confirmando com o usuário |

Ler o diff de verdade, não só os nomes de arquivo:

```bash
git diff <range> --stat
git diff <range>
```

Diff muito grande: ler o `--stat` primeiro, depois os arquivos mais relevantes ao
propósito da mudança. Dizer no fim quais arquivos não foram lidos em detalhe.

---

## Step 2 — Detectar a convenção do projeto

**Não impor formato.** Descobrir o que já se usa:

```bash
git log --oneline -20
ls CONTRIBUTING.md .github/PULL_REQUEST_TEMPLATE.md CHANGELOG.md 2>/dev/null
```

| Fonte | O que extrair |
|---|---|
| `git log --oneline -20` | formato das mensagens (Conventional Commits? prefixo de ticket? idioma?), imperativo vs passado, tamanho típico |
| `CONTRIBUTING.md` | regra explícita de commit e de PR — tem prioridade sobre o inferido |
| `.github/PULL_REQUEST_TEMPLATE.md` | seções obrigatórias do PR — preencher todas |
| `CHANGELOG.md` | categorias em uso e formato de versão |

**Idioma:** seguir o que o repositório usa. Não traduzir um histórico em inglês
para português nem o contrário.

Se o histórico for inconsistente (sem convenção clara), usar Conventional Commits
e **dizer ao usuário** que adotou isso por ausência de padrão.

---

## Step 3 — Produzir

### Modo `commit`

Uma linha de assunto no formato detectado, no imperativo, sem ponto final.
Corpo só quando o "porquê" não couber no assunto — e o corpo explica **motivo**,
não mecânica.

Rodapé obrigatório quando aplicável: indicação de breaking change no formato que
o projeto usa.

Se as mudanças em stage cobrem propósitos distintos, **dizer isso e sugerir a
separação** em vez de escrever uma mensagem que junta tudo.

### Modo `pr`

```
## O que muda
<1 a 3 frases, em linguagem de quem vai usar ou revisar>

## Por quê
<motivo; se não estiver claro no diff, PERGUNTAR — não inventar>

## Como testar
<passos concretos: comando, rota, tela, dado de entrada>

## Atenção
<só quando houver: migration, breaking change, variável de ambiente nova,
dependência nova, mudança de comportamento existente>
```

Existindo template no repositório, ele manda — preencher as seções dele.

### Modo `changelog`

Entrada no formato do `CHANGELOG.md` existente. Sem arquivo, usar Keep a
Changelog (`Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`).

Escrever para quem **usa** o projeto. Refatoração interna sem efeito visível não
entra no changelog.

---

## Regras

- **Nunca inventar motivação.** O diff mostra o quê, raramente o porquê. Se o
  motivo não estiver em commit, issue referenciada ou no código, perguntar.
- **Sempre sinalizar:** migration, breaking change, nova variável de ambiente,
  nova dependência, mudança em contrato de API. São o que quebra o próximo.
- **Não listar arquivos** como se fosse conteúdo. O revisor já vê a lista.
- **Não elogiar a própria mudança.** Nada de "melhora significativamente" ou
  "refatoração robusta".
- **Não commitar nem abrir PR.** A saída é texto para o usuário usar.
- Se o diff contiver segredo aparente ou arquivo que não deveria estar
  versionado, avisar antes de qualquer coisa.
