# Runbook: GH_TOKEN em devcontainer

Como o `gh` e o `git push` autenticam dentro dos containers, sem expor o token
de escopo amplo do `gh` ao ambiente de build.

Criado em 2026-09-09.

## O desenho

O bind de `~/.config/gh` foi removido dos devcontainers. No lugar, um
**fine-grained token** vive em `~/.config/gh-devcontainer/token` no host
(permissão `0600`), e os atalhos `dc`, `dcr` e `dcsh` de `ai-memory/dc.sh` o
passam como `GH_TOKEN` só aos comandos `devcontainer`, que o repassam ao
container por `remoteEnv`.

Motivo: o bind dava a qualquer processo do container — inclusive scripts de
instalação de pacote npm — acesso a um token com poder sobre todos os
repositórios da conta. O fine-grained token alcança só os repositórios
escolhidos, com quatro permissões, e expira em 90 dias.

Por que arquivo e não `export GH_TOKEN` no `~/.bashrc`: no host, `GH_TOKEN` tem
prioridade sobre o login do `gh`. Exportado no shell, ele limitaria o `gh` e o
`git push` do host aos repositórios do token, e o host pararia junto quando o
token expirasse. Pelo arquivo, o host fica com o próprio login.

O arquivo é gravado por `bin/gravar-gh-token.sh`; o valor real nunca é copiado
para lugar nenhum além dele.

---

## `dc` e `dcr`

Funções do `ai-memory/dc.sh`, carregado pelo `~/.bashrc` do host (`dcr` = `dc` com
`--remove-existing-container`). O `dca`, que abre o `agy`, e o `dcsh` sobem o container pelo
mesmo caminho e passam o mesmo `GH_TOKEN`.

**Tudo que o `postCreateCommand` escreve só é restaurado pelo `dcr`** — o
credential helper do `gh`, as permissões, qualquer coisa fora do bind mount.
O `/app` sobrevive aos dois. É a causa de "identidade do git" e "push pede
usuário e senha" em Problemas comuns.

---

## A) Verificar se está funcionando

As três primeiras linhas provam que a *fiação* está montada; as duas últimas
provam que o GitHub aceita. São coisas diferentes — um token expirado passa
nas três primeiras.

```bash
# no HOST (esperado: 93)
tr -d '\n' < ~/.config/gh-devcontainer/token | wc -c

# DENTRO do container
echo ${#GH_TOKEN}                      # esperado: 93 — a variável CHEGOU
ls ~/.config/gh                        # esperado: ERRO — o bind não existe mais
git config --get-regexp credential     # esperado: helper apontando para o gh

gh auth status                         # esperado: autenticado via GH_TOKEN
git ls-remote origin HEAD              # esperado: um SHA — leitura real, não destrutiva
```

`echo ${#GH_TOKEN}` dando 93 **não prova que o token é válido**, só que ele
chegou ao container. Validade se comprova com `gh auth status`. E `ls-remote`
prova a permissão de leitura (*Contents: Read*); a de escrita só se comprova
num push de verdade.

---

## B) Projeto novo

```bash
# 1. acrescentar o repositório à lista do token que já existe
#    https://github.com/settings/personal-access-tokens
#    abrir o token > Repository access > marcar o repo novo > Update
#    NAO criar outro token

# 2. ajustar o devcontainer.json (trechos abaixo)

# 3. subir
cd ~/Documentos/Projetos/PROJETO-NOVO
dc
```

No `devcontainer.json`, **não** montar `~/.config/gh`, e incluir:

```json
"remoteEnv": {
  "GH_TOKEN": "${localEnv:GH_TOKEN}"
}
```

```json
"postCreateCommand": "npm install && if [ -n \"$GH_TOKEN\" ]; then gh auth setup-git; fi"
```

O `gh auth setup-git` precisa ficar no `postCreateCommand` porque o
`~/.gitconfig` do container não persiste entre recriações.

**Este trecho é o mínimo, não o literal.** Projetos existentes encadeiam mais
coisa no mesmo `postCreateCommand` (um projeto Node, por exemplo, pode ajustar a
permissão do `@anthropic-ai` depois). Ao aplicar em projeto que já existe, **acrescente**
ao comando atual em vez de substituí-lo.

Cuidado com o encadeamento por `&&`: se o `gh auth setup-git` falhar (token
expirado), tudo que vier depois dele na mesma linha deixa de rodar, e o sintoma
não parece de credencial.

---

## C) Renovar o token (quando expirar)

```bash
# 1. gerar novo fine-grained token, mesmas permissões, 90 dias
#    https://github.com/settings/personal-access-tokens/new
#    Repository access: only select repositories
#    Contents: RW | Pull requests: RW | Workflows: RW | Metadata: R
#    (todo o resto: No access)

# 2. gravar por cima do arquivo (o script confere o token antes de gravar)
~/.claude/toolkit/bin/gravar-gh-token.sh

# 3. reabrir o container
dc          # se o gh continuar falhando: dcr
```

### Máquina nova, ou sem `~/.config/gh-devcontainer/token`

Gere o token pelo passo 1 acima, rode `~/.claude/toolkit/bin/gravar-gh-token.sh`
e confira que `~/.bashrc` carrega `ai-memory/dc.sh` (é ele que lê o arquivo).

---

## Problemas comuns

**`gh auth status` passa, mas `git push` pede usuário e senha.**
O `~/.gitconfig` do container está vazio: o container foi reaproveitado e o
`postCreateCommand` não rodou de novo. Conserto imediato: `gh auth setup-git`
na mão. Conserto durável: `dcr`. Confirmar com
`git config --get-regexp credential` — sem saída, é este caso.

**`git commit` falha com "Author identity unknown".**
O `gh auth setup-git` escreve só o credential helper, não `user.name` nem
`user.email` — e o `~/.gitconfig` do container não persiste. Grave a identidade
no repositório, não no global: o `.git/config` fica no bind mount do workspace
e sobrevive ao `dcr`.

```bash
git config --local user.name "Seu Nome"
git config --local user.email "voce@exemplo.com"
```

**`gh` falha com erro de autenticação dentro do container.**
Depois da expiração, quase sempre é token expirado — não defeito do
devcontainer. Confirmar com `gh auth status` (não com `echo ${#GH_TOKEN}`, que
continua dando 93 com token vencido) e checar a validade em
github.com/settings/personal-access-tokens.

**`echo ${#GH_TOKEN}` dá 0 dentro do container.**
O container subiu sem o `dc` (um `devcontainer up` direto não lê o arquivo), ou
`~/.config/gh-devcontainer/token` não existe. Rodar `gravar-gh-token.sh` se
faltar o arquivo, e subir com `dcr`.

**Push recusado ao alterar `.github/workflows/`.**
Falta a permissão *Workflows: Read and write* no token.

**Push recusado num repositório que funcionava antes.**
O repositório não está na lista do token. Acrescentar em
github.com/settings/personal-access-tokens.

---

## Regras que continuam valendo

- **Não rodar `dc` em repositório de terceiro.** O `~/.claude` (credenciais e
  histórico) é montado em qualquer projeto, e o `npm ci` executa scripts
  escritos por outra pessoa.
- **`npm ci` em vez de `npm install`** no dia a dia: respeita o lock e não puxa
  versão nova sem pedido.
- **Dependência nova merece desconfiança** — é o vetor realista de vazamento do
  `GH_TOKEN`, não uma invasão da máquina.
