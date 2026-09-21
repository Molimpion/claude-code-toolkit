# Runbook: GH_TOKEN em devcontainer

Como o `gh` e o `git push` autenticam dentro dos containers, sem expor o token
de escopo amplo do `gh` ao ambiente de build.

Criado em 2026-09-09.

## O desenho

O bind de `~/.config/gh` foi removido dos devcontainers. No lugar, um
**fine-grained token** vive no `~/.bashrc` do host e é repassado ao container
por `remoteEnv`.

Motivo: o bind dava a qualquer processo do container — inclusive scripts de
instalação de pacote npm — acesso a um token com poder sobre todos os
repositórios da conta. O fine-grained token alcança só os repositórios
escolhidos, com quatro permissões, e expira em 90 dias.

A linha no `~/.bashrc` do host tem esta forma (valor real nunca é copiado
para lugar nenhum):

```bash
export GH_TOKEN=github_pat_...
```

---

## `dc` e `dcr`

Funções do `~/.bashrc` do host (`dcr` = `dc` com `--remove-existing-container`).

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
echo ${#GH_TOKEN}

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
coisa no mesmo `postCreateCommand` (o `notif-api`, por exemplo, ajusta permissão
do `@anthropic-ai` depois). Ao aplicar em projeto que já existe, **acrescente**
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

# 2. EDITAR a linha existente no ~/.bashrc (não acrescentar outra)
nano ~/.bashrc

# 3. recarregar e conferir
source ~/.bashrc
echo ${#GH_TOKEN}

# 4. reabrir o container
dc          # se o gh continuar falhando: dcr
```

### Máquina nova, ou `~/.bashrc` sem a linha

Não há o que editar: acrescente a linha do início deste runbook ao
`~/.bashrc` do host, com um token gerado pelo passo 1 acima. Depois
`source ~/.bashrc`, confirme com `echo ${#GH_TOKEN}` **no host**, e só então
suba o container daquele mesmo terminal.

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
git config --local user.name "Manoel Olímpio"
git config --local user.email "olimpiommelo@gmail.com"
```

**`gh` falha com erro de autenticação dentro do container.**
Depois da expiração, quase sempre é token expirado — não defeito do
devcontainer. Confirmar com `gh auth status` (não com `echo ${#GH_TOKEN}`, que
continua dando 93 com token vencido) e checar a validade em
github.com/settings/personal-access-tokens.

**`echo ${#GH_TOKEN}` dá 0 dentro do container.**
O `${localEnv:GH_TOKEN}` lê a variável do terminal que chamou o devcontainer.
Se aquele terminal não tinha a variável, chega vazia. Abrir terminal novo,
confirmar `echo ${#GH_TOKEN}` no host, e subir de novo dali.

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
