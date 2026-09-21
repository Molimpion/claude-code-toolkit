# Claude Code + Dev Container — Guia Explicado

> Como rodar o Claude Code isolado num dev container, conectado aos serviços do
> projeto (Postgres, Redis). O procedimento operacional do token do GitHub
> (verificar, renovar, diagnosticar) está em [`runbook-gh-token.md`](runbook-gh-token.md).
> Quando os dois tratarem do mesmo assunto, o runbook manda sobre o token.

---

# PARTE A — O que estamos montando e por quê

## O problema

Rodar o Claude Code direto na máquina significa dar a ele acesso ao teu sistema
inteiro. Rodar dentro de um container isola o sistema de arquivos: ele só
enxerga o projeto.

O efeito colateral é que um container isolado também não enxerga o banco do
projeto. Sem banco, o agente não roda migration, teste de integração nem sobe a
aplicação.

## A solução

O **dev container** sobe junto com os serviços do projeto (Postgres, Redis etc.),
na mesma rede. O Claude fica isolado da tua máquina, mas conectado ao ambiente
do projeto.

## As peças

| Peça | O que faz | Onde vive |
|---|---|---|
| `devcontainers/cli` | comando que sobe o container | instalado uma vez na máquina |
| `.devcontainer/devcontainer.json` | descreve o ambiente | no projeto |
| `.devcontainer/docker-compose.dev.yml` | acrescenta o serviço da app ao compose (variante C3) | no projeto |
| feature `claude-code` | instala o Claude Code no container | baixada no build |
| feature `github-cli` | instala o `gh` | baixada no build |
| bind de `~/.claude` | login + `CLAUDE.md` de usuário + config de MCP | pasta real na tua máquina |
| `GH_TOKEN` via `remoteEnv` | autentica `gh` e `git push` | `~/.bashrc` do host → container |
| volumes nomeados | cache de dependências entre execuções | no Docker |
| funções `dc`, `dcr`, `dcsh` | atalhos para subir + abrir | no `~/.bashrc` do host |

---

# PARTE B — Setup da máquina (UMA VEZ)

## Etapa B1 — Docker funcionando

````bash
docker ps
````

Se der erro de permissão:

````bash
sudo usermod -aG docker $USER
````

Depois faça **logout e login**. Abrir outro terminal não basta, porque o grupo só
é reavaliado no login.

Se disser que não conecta ao daemon:

````bash
sudo systemctl start docker
sudo systemctl enable docker
````

---

## Etapa B2 — npm global sem sudo

````bash
mkdir -p ~/.npm-global
npm config set prefix ~/.npm-global
echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
````

**Por quê:** sem isso, todo `npm install -g` exige sudo e deixa arquivos com dono
root no teu home.

---

## Etapa B3 — Instalar a CLI

````bash
npm install -g @devcontainers/cli
devcontainer --version
````

---

## Etapa B4 — Identidade do git (host)

````bash
git config --global user.name "Seu Nome"
git config --global user.email "seu@email.com"
````

Isso vale **só para o host**. A CLI do devcontainer não copia o `.gitconfig` para
dentro do container (quem faz isso é o VS Code). Dentro do container, a
identidade é gravada por repositório; ver Etapa C8.

---

## Etapa B5 — `GH_TOKEN` no host

Acrescente ao `~/.bashrc` do host a linha com o fine-grained token:

````bash
export GH_TOKEN=github_pat_...
````

````bash
source ~/.bashrc
echo ${#GH_TOKEN}      # esperado: 93
````

Como gerar o token, quais permissões ele leva e como renovar: **runbook, seção
C**. O valor real nunca é copiado para arquivo do projeto, `devcontainer.json`,
`CLAUDE.md` nem para nenhum outro lugar além dessa linha.

**Por que não o bind de `~/.config/gh`:** o bind entregava a qualquer processo do
container, inclusive scripts de instalação de pacotes npm, um token com poder
sobre todos os repositórios da conta. O fine-grained token alcança só os
repositórios escolhidos, com quatro permissões, e expira em 90 dias.

**O que ele não resolve:** o `GH_TOKEN` continua legível por qualquer processo do
container, inclusive pelos scripts do `npm ci`. O ganho é o **alcance reduzido**
e a **expiração**, não o isolamento. Ver Parte E.

---

## Etapa B6 — Atalhos no shell

Estas são as funções que estão no `~/.bashrc`:

````bash
dc() {
  devcontainer up --workspace-folder . >/dev/null && \
  devcontainer exec --workspace-folder . claude "$@"
}

dcr() {
  devcontainer up --workspace-folder . --remove-existing-container >/dev/null && \
  devcontainer exec --workspace-folder . claude "$@"
}

dcsh() {
  devcontainer up --workspace-folder . >/dev/null && \
  devcontainer exec --workspace-folder . bash
}
````

| Função | Faz | Quando usar |
|---|---|---|
| `dc` | sobe (ou reaproveita) e abre o Claude | dia a dia |
| `dcr` | **recria** o container e abre o Claude | mudou o `devcontainer.json`, ou algo do `postCreateCommand` sumiu |
| `dcsh` | sobe (ou reaproveita) e abre um shell | validar, diagnosticar, `gh auth status` |

**A regra que explica metade dos problemas:** o `postCreateCommand` só roda quando
o container é **criado**. O `dc` reaproveita o container existente, então não
reaplica nada. Tudo que o `postCreateCommand` escreve fora do bind mount
(credential helper do git, permissões, `~/.gitconfig`) só é restaurado pelo
`dcr`. O workspace sobrevive aos dois.

**O que o `>/dev/null` esconde:** ele descarta o JSON de saída do `up` e boa parte
do log. Se o ambiente parecer quebrado, suba sem o atalho para ver o que
aconteceu:

````bash
devcontainer up --workspace-folder . --remove-existing-container
````

**Rode sempre da raiz do repo que tem o `.devcontainer/`.** As funções usam o
diretório atual. Na variante multi-repo (C3-C), é o repo principal.

**Rode sempre de um terminal onde o `GH_TOKEN` existe.** O `${localEnv:GH_TOKEN}`
lê a variável do terminal que chamou o `devcontainer`. Se ela não estava lá,
chega vazia ao container.

---

# PARTE C — Setup por projeto

Exemplo de referência: Java 17 + Maven + Spring Boot + Postgres via compose.
Configurações de outras linguagens: Parte C-BIS.

## Qual variante usar

| Situação | Variante |
|---|---|
| Projeto sem banco nem serviços | C2 |
| Serviços num compose; o devcontainer entra no compose como serviço `app` | C3 |
| O projeto tem `Dockerfile` próprio e o compose sobe só os serviços | C3-B |
| Vários repositórios de um mesmo sistema, um Claude alcançando todos | C3-C |

## Etapa C1 — Descobrir o que o projeto pede

````bash
cd ~/caminho/do/projeto
ls -a                                    # confirma que tem .git
git branch --show-current                # confirma a branch
ls | grep -E "docker-compose|compose.yml|Dockerfile"
````

Por stack:

````bash
# Java
ls | grep -E "pom.xml|build.gradle"
grep -E "java.version|maven.compiler" pom.xml
# Node
cat .nvmrc 2>/dev/null; grep -A2 '"engines"' package.json
ls | grep -E "package-lock.json|pnpm-lock|yarn.lock"
# Python
ls | grep -E "requirements.txt|pyproject.toml"
cat .python-version 2>/dev/null
````

Anote:

- versão da linguagem
- se tem `docker-compose.yml` **na raiz** (muda a regra de caminho da Etapa C3)
- se tem `Dockerfile` com um estágio de build (candidato à C3-B)
- o nome do serviço do banco no compose (ex: `db`)
- para onde a config de banco aponta (ex: `localhost:5432`)

Por fim, **acrescente o repositório à lista do token** (runbook, seção B, passo
1). Não crie outro token.

---

## Etapa C2 — SEM banco (projeto simples)

````bash
mkdir -p .devcontainer
nano .devcontainer/devcontainer.json
````

````json
{
  "name": "nome-do-projeto",
  "image": "mcr.microsoft.com/devcontainers/java:17",
  "features": {
    "ghcr.io/devcontainers/features/java:1": {
      "version": "none",
      "installMaven": true
    },
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "ghcr.io/devcontainers/features/node:1": {},
    "ghcr.io/anthropics/devcontainer-features/claude-code:1": {}
  },
  "mounts": [
    "source=${localEnv:HOME}/.claude,target=/home/vscode/.claude,type=bind",
    "source=maven-repo,target=/home/vscode/.m2,type=volume"
  ],
  "containerEnv": {
    "CLAUDE_CONFIG_DIR": "/home/vscode/.claude"
  },
  "remoteEnv": {
    "GH_TOKEN": "${localEnv:GH_TOKEN}"
  },
  "remoteUser": "vscode",
  "updateRemoteUserUID": true,
  "postCreateCommand": "D=$(npm config get prefix)/lib/node_modules/@anthropic-ai; if [ -d \"$D\" ]; then sudo chmod -R g+w \"$D\"; sudo find \"$D\" -type d -exec chmod g+s {} +; fi; sudo chown -R vscode:vscode /home/vscode/.m2; if [ -n \"$GH_TOKEN\" ]; then gh auth setup-git; fi; mvn -q dependency:go-offline",
  "forwardPorts": [8080]
}
````

### Explicando cada campo

**`image`** — imagem base. Precisa bater com a versão do projeto.

**`features`** — instalações reaproveitáveis, executadas no build, em ordem.

- `java:1` com `"version": "none"` não instala outro JDK (a imagem já tem um);
  serve só para trazer o Maven.
- `github-cli:1` instala o `gh`. Ver Etapa C4.7.
- `node:1` é necessária quando a imagem não traz Node + npm. A feature do Claude
  Code depende deles; sem ela, o build quebra com
  `ERROR: Node.js and npm are required but could not be installed!`. Em
  `typescript-node` ela é dispensável.
- `claude-code:1` instala o Claude Code.

**`mounts`** — o que sobrevive a rebuilds.

- `type=bind` em `${localEnv:HOME}/.claude` aponta para a pasta `~/.claude` **da
  tua máquina**. Com ele, o login persiste, o `CLAUDE.md` de usuário é
  carregado, a config de MCP de escopo `user` vale em todos os projetos, e tudo é
  igual em todos eles.
- `type=volume` em `maven-repo` guarda o cache de dependências, para o Maven não
  rebaixar o Spring Boot inteiro a cada rebuild.
- **Não existe mais bind de `~/.config/gh`.** A autenticação do GitHub vem pelo
  `remoteEnv`.

**Pré-requisito do bind:** a pasta precisa existir no host antes de subir. Se não
existir, o Docker cria um diretório vazio e com dono root.

````bash
mkdir -p ~/.claude
touch ~/.claude/CLAUDE.md
````

**`containerEnv`** — variáveis fixas do container. `CLAUDE_CONFIG_DIR` diz ao
Claude onde ler e gravar a configuração, para coincidir com o mount. Inclui o
`.claude.json`, onde ficam os servidores MCP (Etapa C4.6).

**`remoteEnv`** — variáveis que chegam aos processos do usuário remoto: `exec`,
terminal e lifecycle commands como o `postCreateCommand`. O `GH_TOKEN` fica aqui,
e não em `containerEnv`, porque `containerEnv` é gravado na definição do
container: o valor ficaria visível em `docker inspect`.

**`remoteUser`** — o usuário dentro do container. **Muda conforme a imagem:**

| Imagem | Usuário | Caminho do home |
|---|---|---|
| `typescript-node` | `node` | `/home/node` |
| `java`, `python`, `ruby`, `rust` | `vscode` | `/home/vscode` |

Se errar aqui, os mounts vão para um caminho que não existe e o login não
persiste.

**`updateRemoteUserUID`** — remapeia o uid do usuário do container para o teu uid
do host, para os arquivos criados pelo bind não saírem com dono errado. Em Linux
com usuário não-root, o padrão já é `true`.

**`postCreateCommand`** — ver Etapa C7. A ordem e os separadores importam.

**`forwardPorts`** — portas acessíveis do host.

---

## Etapa C3 — COM banco (devcontainer como serviço do compose)

São **dois** arquivos.

### A regra do caminho (leia antes de escrever)

O Docker Compose resolve caminhos relativos a partir do **diretório do primeiro
arquivo da lista `dockerComposeFile`**. Esse diretório define também o nome do
projeto Compose e, portanto, o prefixo dos volumes e o nome da rede.

| Situação | Primeiro arquivo da lista | Volume do workspace |
|---|---|---|
| Existe `docker-compose.yml` na raiz (compose do time) | `../docker-compose.yml` | `.:/workspaces/nome-do-projeto` |
| Só existe o compose dentro de `.devcontainer/` | `docker-compose.dev.yml` | `..:/workspaces/nome-do-projeto` |

Erro nos dois sentidos:

- Com compose do time e `..`, você monta a pasta **acima** do projeto, ou seja,
  todos os teus repositórios dentro do container.
- Sem compose do time e `.`, você monta **só a `.devcontainer/`**, e o projeto
  aparece vazio.

### Arquivo 1 — caso com compose do time na raiz

````bash
mkdir -p .devcontainer
nano .devcontainer/docker-compose.dev.yml
````

````yaml
services:
  db:
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 3s
      retries: 10

  app:
    image: mcr.microsoft.com/devcontainers/java:17
    volumes:
      - .:/workspaces/nome-do-projeto
    command: sleep infinity
    depends_on:
      db:
        condition: service_healthy
````

- `app` é um serviço **novo**. O `docker-compose.yml` do time não é modificado; a
  CLI mescla os dois em memória.
- O bloco `db:` só **acrescenta** o healthcheck ao serviço existente. É merge,
  não substituição.
- `command: sleep infinity` mantém o container vivo.
- `healthcheck` + `condition: service_healthy`: o `depends_on` sozinho garante só
  a ordem de start, não que o banco aceite conexão. Sem isso, o primeiro run logo
  após o `up` toma `connection refused`.
- Se o banco não for Postgres: MySQL usa `mysqladmin ping -h localhost`; Redis
  usa `redis-cli ping`.

### Arquivo 1 — variante sem compose do time

Se o único compose do projeto é o teu, ele precisa declarar o banco inteiro, e o
volume usa `..`:

````yaml
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: app
    volumes:
      - db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 3s
      retries: 10

  app:
    image: mcr.microsoft.com/devcontainers/java:17
    volumes:
      - ..:/workspaces/nome-do-projeto
    command: sleep infinity
    depends_on:
      db:
        condition: service_healthy

volumes:
  db-data:
````

E no `devcontainer.json`, a lista tem um arquivo só:
`"dockerComposeFile": ["docker-compose.dev.yml"]`.

### Arquivo 2

````bash
nano .devcontainer/devcontainer.json
````

````json
{
  "name": "nome-do-projeto",
  "dockerComposeFile": [
    "../docker-compose.yml",
    "docker-compose.dev.yml"
  ],
  "service": "app",
  "workspaceFolder": "/workspaces/nome-do-projeto",
  "features": {
    "ghcr.io/devcontainers/features/java:1": {
      "version": "none",
      "installMaven": true
    },
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "ghcr.io/devcontainers/features/node:1": {},
    "ghcr.io/anthropics/devcontainer-features/claude-code:1": {}
  },
  "mounts": [
    "source=${localEnv:HOME}/.claude,target=/home/vscode/.claude,type=bind",
    "source=maven-repo,target=/home/vscode/.m2,type=volume"
  ],
  "containerEnv": {
    "CLAUDE_CONFIG_DIR": "/home/vscode/.claude",
    "SPRING_DATASOURCE_URL": "jdbc:postgresql://db:5432/postgresdb"
  },
  "remoteEnv": {
    "GH_TOKEN": "${localEnv:GH_TOKEN}"
  },
  "remoteUser": "vscode",
  "updateRemoteUserUID": true,
  "postCreateCommand": "D=$(npm config get prefix)/lib/node_modules/@anthropic-ai; if [ -d \"$D\" ]; then sudo chmod -R g+w \"$D\"; sudo find \"$D\" -type d -exec chmod g+s {} +; fi; sudo chown -R vscode:vscode /home/vscode/.m2; if [ -n \"$GH_TOKEN\" ]; then gh auth setup-git; fi; mvn -q dependency:go-offline",
  "forwardPorts": [8080]
}
````

**`dockerComposeFile`** — lista em ordem. Caminhos relativos à pasta
`.devcontainer/`. O segundo sobrescreve o primeiro em caso de conflito.

**`service`** — qual serviço vira o dev container: o `app`.

**`workspaceFolder`** — onde o Claude abre. Precisa ser **exatamente** o `target`
do volume no arquivo 1.

**`SPRING_DATASOURCE_URL`** — dentro do container, `localhost` é o próprio
container; o banco está em outro, com o nome do serviço (`db`). Como o
`application.properties` é versionado, não dá para editá-lo sem quebrar o
ambiente do time. A env var resolve porque o Spring Boot dá precedência a ela.

> Equivalente em outras stacks: `DATABASE_URL` (Node/Prisma, Django), `DB_HOST`
> (Laravel).

**Workspace: `/workspaces/<nome>` ou `/app`.** Os dois funcionam; o que não pode é
o `target` do volume e o `workspaceFolder` divergirem. Alguns projetos usam `/app`.
Para os novos, o padrão é `/workspaces/<nome>`, que é o que a CLI usa sozinha no
modo `image` e deixa o caminho autoexplicativo quando há vários containers de pé.

---

## Etapa C3-B — Variante: Dockerfile do projeto + rede do compose

O compose da raiz sobe **só os serviços** (Postgres,
Redis); o devcontainer é construído a partir do `Dockerfile` do próprio projeto e
**entra na rede** do compose, em vez de virar um serviço dele.

**Quando preferir:** o projeto já tem um `Dockerfile` multi-stage com um estágio
de build que serve de ambiente de desenvolvimento, e você quer que o banco viva
independente do container do Claude (derrubar e recriar o devcontainer não mexe
nos serviços).

````json
{
  "name": "nome-do-projeto",
  "build": {
    "context": "${localWorkspaceFolder}",
    "dockerfile": "${localWorkspaceFolder}/Dockerfile",
    "target": "build"
  },
  "workspaceFolder": "/app",
  "workspaceMount": "source=${localWorkspaceFolder},target=/app,type=bind,consistency=cached",
  "initializeCommand": "docker compose up -d",
  "runArgs": ["--network=nome-do-projeto_default"],
  "remoteUser": "node",
  "updateRemoteUserUID": true,
  "features": {
    "ghcr.io/devcontainers/features/common-utils:2": {},
    "ghcr.io/devcontainers/features/git:1": {},
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "ghcr.io/anthropics/devcontainer-features/claude-code:1": {}
  },
  "mounts": [
    "source=${localEnv:HOME}/.claude,target=/home/node/.claude,type=bind",
    "source=${localWorkspaceFolderBasename}-node-modules,target=/app/node_modules,type=volume"
  ],
  "containerEnv": {
    "NODE_ENV": "development",
    "POSTGRES_HOST": "postgres",
    "REDIS_HOST": "redis",
    "CLAUDE_CONFIG_DIR": "/home/node/.claude"
  },
  "remoteEnv": {
    "GH_TOKEN": "${localEnv:GH_TOKEN}"
  },
  "postCreateCommand": "D=$(npm config get prefix)/lib/node_modules/@anthropic-ai; if [ -d \"$D\" ]; then sudo chmod -R g+w \"$D\"; sudo find \"$D\" -type d -exec chmod g+s {} +; fi; sudo chown -R node:node /app/node_modules; if [ -n \"$GH_TOKEN\" ]; then gh auth setup-git; fi; npm ci",
  "forwardPorts": [3000]
}
````

**`build.target`** — usa um estágio específico do `Dockerfile`. O estágio precisa
ter o toolchain completo (compilador, devDependencies); o estágio final de
produção normalmente não tem. A imagem desse estágio **não é** uma imagem
`mcr.microsoft.com/devcontainers/*`: o usuário, o grupo do npm e o `sudo` dependem
do que o `Dockerfile` define. A feature `common-utils` é o que garante o usuário
não-root com sudo; confira o `remoteUser` com `id` dentro do container.

**`workspaceMount` + `workspaceFolder`** — no modo `build`, eles definem onde o
projeto é montado. Os dois precisam apontar para o mesmo caminho.

**`initializeCommand`** — roda **no host**, antes de criar ou iniciar o container,
a cada `devcontainer up`. Garante que os serviços e a rede existem. Sem ele, se
você rodar `dc` antes de `docker compose up -d`, a rede não existe e o container
nem sobe. Se os serviços já estão de pé, o comando não faz nada.

**`runArgs --network`** — conecta o devcontainer à rede do compose, onde os
serviços são alcançados pelo nome (`postgres`, `redis`). O nome da rede é
`<projeto-compose>_default`, e o nome do projeto vem, por padrão, **do nome da
pasta** onde está o compose. Renomeou a pasta, quebrou a rede. Para fixar,
declare o nome no topo do `docker-compose.yml`:

````yaml
name: nome-do-projeto
services:
  ...
````

Assim a rede passa a ser sempre `nome-do-projeto_default`, independente da
pasta.

**Volume em `node_modules`** — mesma razão da seção Node da Parte C-BIS: sem ele,
host e container brigam pelos binários nativos. O `chown` vem antes do `npm ci`
no `postCreateCommand`. Dispensável se você **só** roda npm dentro do container.

**Credenciais do banco no `containerEnv`** — aceitável para banco local de
desenvolvimento. Nunca coloque ali segredos reais (chave
de API de terceiros, token): o `containerEnv` fica visível em `docker inspect`.

---

## Etapa C3-C — Variante: vários repositórios, um Claude

Para um sistema dividido em repositórios separados (ex.: backend, frontend, IA).
O devcontainer fica em **um** dos repos (o "repo principal"), que abre
normalmente, e um bind extra monta a **pasta-mãe** com todos os repos. O Claude
roda a partir do repo principal e alcança os outros pela pasta-mãe; para mexer
em outro repo, basta pedir.

### Marcadores usados nesta seção

| Marcador | Significa | Exemplo |
|---|---|---|
| `<pasta-mae>` | pasta que contém todos os repos | `meu-sistema` |
| `<caminho-da-pasta-mae>` | caminho dela no host, a partir do home | `Projetos/meu-sistema` |
| `<repo-principal>` | repo onde fica o `.devcontainer/` | `meu-sistema-api` |
| `<repo-b>`, `<repo-c>` | os demais repos | `meu-sistema-web`, `meu-sistema-ia` |

### Estrutura

````
~/<caminho-da-pasta-mae>/
├── <repo-principal>/    ← .devcontainer/ fica aqui, rode dc daqui
├── <repo-b>/
└── <repo-c>/
````

Dentro do container:

| Caminho | O que é |
|---|---|
| `/workspaces/<repo-principal>` | workspace (onde o Claude abre) |
| `/workspaces/<pasta-mae>/` | pasta-mãe, com todos os repos |

### `devcontainer.json` (no repo principal)

````json
{
  "name": "<pasta-mae>",
  "image": "mcr.microsoft.com/devcontainers/typescript-node:22",
  "workspaceFolder": "/workspaces/<repo-principal>",
  "features": {
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "ghcr.io/anthropics/devcontainer-features/claude-code:1": {}
  },
  "mounts": [
    "source=${localEnv:HOME}/.claude,target=/home/node/.claude,type=bind",
    "source=${localEnv:HOME}/<caminho-da-pasta-mae>,target=/workspaces/<pasta-mae>,type=bind"
  ],
  "containerEnv": {
    "CLAUDE_CONFIG_DIR": "/home/node/.claude"
  },
  "remoteEnv": {
    "GH_TOKEN": "${localEnv:GH_TOKEN}"
  },
  "postCreateCommand": "D=$(npm config get prefix)/lib/node_modules/@anthropic-ai; if [ -d \"$D\" ]; then sudo chmod -R g+w \"$D\"; sudo find \"$D\" -type d -exec chmod g+s {} +; fi; if [ -n \"$GH_TOKEN\" ]; then gh auth setup-git; fi",
  "remoteUser": "node",
  "updateRemoteUserUID": true
}
````

- Versão mínima, sem install: serve para começar com repos vazios. Quando as
  stacks existirem, acrescente installs (Etapa C7), volumes e portas, e rode
  `dcr`.
- A imagem e o `remoteUser` seguem a stack principal (tabela da Parte D). Outra
  linguagem num dos repos: acrescente a feature, ver "Projeto poliglota" na
  Parte C-BIS.

### Esconder do git (no repo principal)

````bash
echo -e ".devcontainer/\n.claude/\nCLAUDE.md" >> .git/info/exclude
````

O `.devcontainer/` aponta para um caminho da tua máquina, então não serve para o
time. Lembre que o exclude não sobrevive a clone novo.

### Consequências do padrão

**O repo principal aparece em dois caminhos:** `/workspaces/<repo-principal>` e
`/workspaces/<pasta-mae>/<repo-principal>`. São os mesmos arquivos, então nada
quebra, mas o agente pode editar por um caminho e ler pelo outro.

**Permissões:** o Claude pede permissão ao editar fora do workspace. As
aprovações ficam gravadas em `.claude/settings.local.json` com o caminho
absoluto. Se o mount mudar, elas ficam órfãs e precisam ser refeitas.

**Credencial é global; identidade é por repo.** O `gh auth setup-git` vale para
todos. A identidade vai com `--local` em cada repo (ver a validação abaixo).

**O `gh` depende do diretório.** Ele descobre o repo pelo diretório atual; para
os outros, use `git -C <caminho>` / `cd <caminho>` ou `gh -R dono/repo`.

**Os installs caem nas pastas do host.** O `node_modules` que o Claude instala
aparece no VS Code. Instale sempre pelo container; misturar com npm no host dá
conflito em pacote nativo.

**`CLAUDE.md`:** cada repo pode ter o seu. Um na pasta-mãe é opcional; se criar,
use-o para explicar como os repos se conectam e as regras de escopo.

### Validar (dentro do `dcsh`)

````bash
for r in <repo-principal> <repo-b> <repo-c>; do
  git -C /workspaces/<pasta-mae>/$r config --local user.name "Seu Nome"
  git -C /workspaces/<pasta-mae>/$r config --local user.email "seu@email.com"
  git -C /workspaces/<pasta-mae>/$r ls-remote origin HEAD >/dev/null && echo "$r: ok" || echo "$r: FALHOU"
done
````

---

## Etapa C4 — Visibilidade para a equipe

**Esta é a decisão que você toma antes de subir.** Na variante multi-repo
(C3-C), o `.devcontainer/` é sempre pessoal (aponta para caminhos da tua
máquina); a decisão vale para o `CLAUDE.md` e o `.mcp.json` de cada repo.

### Opção 1 — Só para você (invisível ao time)

````bash
echo ".devcontainer/" >> .git/info/exclude
git status --short
````

O `git status` não pode listar `.devcontainer`.

`.git/info/exclude` tem a sintaxe do `.gitignore`, mas vive dentro de `.git/`: é
local à tua cópia e nunca vai para o repositório. Vale para qualquer branch.

**Não sobrevive a clone novo.** Reclonou, formatou ou mudou de máquina, a regra
some, e um `git add .` distraído commita o teu ambiente pessoal no repo do time.
Deixe um lembrete no `~/.claude/CLAUDE.md` global.

**Risco de colisão:** se o time criar um `.devcontainer/` depois, o pull conflita
com o teu. Se for provável, use outro nome:

````bash
mkdir .devcontainer-local
echo ".devcontainer-local/" >> .git/info/exclude
devcontainer up --workspace-folder . --config .devcontainer-local/devcontainer.json
````

Nesse caso, as funções `dc`/`dcr`/`dcsh` **não servem como estão**, porque não
passam `--config`.

### Opção 2 — Compartilhado com o time (versionado)

````bash
git add .devcontainer/
git commit -m "chore: adiciona devcontainer para ambiente de desenvolvimento"
````

**Antes de commitar, tire o que é pessoal:**

- a feature `claude-code`
- o mount de `~/.claude` e o `CLAUDE_CONFIG_DIR`
- o trecho do `@anthropic-ai` no `postCreateCommand`

Podem ficar: a feature `github-cli`, o `remoteEnv` com `GH_TOKEN` (quem não tiver
a variável recebe vazio e o `if` pula o `setup-git`) e o install de dependências.

### Opção 3 — Híbrido (base compartilhada + tua camada) — **recomendada em grupo**

O time commita `.devcontainer/` sem Claude Code. Você acrescenta um arquivo
local:

````bash
nano .devcontainer/devcontainer.local.json
echo ".devcontainer/devcontainer.local.json" >> .git/info/exclude
devcontainer up --workspace-folder . --config .devcontainer/devcontainer.local.json
````

A Opção 1 te coloca num ambiente que ninguém mais reproduz. Na primeira vez que
algo compilar para você e não para eles, você não tem como provar que não é o
teu setup. A Opção 3 dá o mesmo isolamento e ainda padroniza o time.

Assim como a variante `.devcontainer-local`, ela exige `--config`. Se for o
padrão, crie variantes das funções (ex.: `dcl`) em vez de editar as existentes.

Se o grupo tende a transformar qualquer proposta de infraestrutura em discussão
longa, a Opção 1 é defensável **enquanto você valida**. Só não deixe virar
permanente.

---

## Etapa C4.5 — Onde ficam as instruções (`CLAUDE.md`)

| Arquivo | Escopo | Chega ao container? |
|---|---|---|
| `~/.claude/CLAUDE.md` (host) | tuas preferências, todos os projetos | sim, pelo bind |
| `CLAUDE.md` na raiz do repo | este repositório | sempre, está na pasta montada |
| `CLAUDE.md` na pasta-mãe (C3-C, opcional) | o conjunto de repos | só se o Claude trabalhar a partir dela |

Preferências de estilo vão no global; fatos sobre o projeto vão no do repo. A
decisão de visibilidade é a mesma da Etapa C4. Como escrever: **Parte F**.

---

## Etapa C4.6 — Servidores MCP dentro do container

### O ponto que confunde

- `~/.claude/CLAUDE.md` fica dentro do **diretório** `~/.claude/`.
- `~/.claude.json` é um **arquivo solto** na raiz da home.

Com `CLAUDE_CONFIG_DIR` apontando para o `.claude` do container, o Claude Code lê
o `.claude.json` **de dentro** do diretório, ou seja, de `~/.claude/.claude.json`
no host, que está no bind. O `~/.claude.json` da raiz da home continua
irrelevante para o container. E o escopo `local` é indexado pelo caminho absoluto
do projeto, que difere entre host e container, então instalar MCP no host "por
fora" resulta em `No MCP servers configured`.

### O que fazer

**MCP pessoal, de uso geral** → escopo `user`, rodando **de dentro** do
container:

````bash
dcsh
claude mcp add --scope user --transport http sentry https://mcp.sentry.dev/mcp
````

**MCP do projeto** → `.mcp.json` na raiz do repositório:

````json
{
  "mcpServers": {
    "sentry": { "type": "http", "url": "https://mcp.sentry.dev/mcp" }
  }
}
````

### Alternativa: configurar pelo host

````bash
echo 'export CLAUDE_CONFIG_DIR="$HOME/.claude"' >> ~/.bashrc
source ~/.bashrc
cp ~/.claude.json ~/.claude/.claude.json   # leva o que já existia
````

O ganho real é o OAuth: você autentica no host, com navegador, e o token fica em
`~/.claude/`, que o container lê. **Não vale para `stdio`:** o comando gravado é
executado onde o Claude está rodando.

### Armadilhas específicas de container

- **Servidores `stdio` rodam dentro do container.** Playwright precisa do
  Chromium e de modo headless.
- **Servidores via `docker run`** exigem docker-in-docker ou socket montado.
  Prefira a variante HTTP.
- **OAuth não abre navegador no container.** Copie a URL do `/mcp` para o
  navegador do host, ou configure pelo host.

Em devcontainer, **prefira MCP HTTP com token estático a `stdio` e a OAuth.**

### Custo de contexto

Cada servidor conectado ocupa context window em **toda** sessão. Os conectores
ativados em claude.ai/customize/connectors carregam automaticamente no CLI
(prefixo `claude.ai` no `claude mcp list`) e não saem com `claude mcp remove`.
Desative na origem os que não têm função numa sessão de código.

---

## Etapa C4.7 — GitHub: `gh` + `GH_TOKEN`, não MCP

### Por que não MCP

O endpoint MCP oficial do GitHub (`https://api.githubcopilot.com/mcp`) exige
assinatura do **GitHub Copilot**. Sem ela, `✘ Failed to connect`,
independentemente das permissões do token. Não é problema de container nem de
git instalado.

O `gh` no PATH cobre issues, PRs, reviews e checks, não custa context window,
serve para você também e é reinstalado no build pela feature.

### Como a autenticação funciona

1. O fine-grained token vive no `~/.bashrc` do host (Etapa B5).
2. O `remoteEnv` repassa o `GH_TOKEN` ao container.
3. O `gh` lê o `GH_TOKEN` direto do ambiente; não precisa de `gh auth login`.
4. O `gh auth setup-git`, no `postCreateCommand`, registra o `gh` como credential
   helper do git, para o `git push` por HTTPS usar o mesmo token.

O passo 4 fica no `postCreateCommand` porque o `~/.gitconfig` do container não
está em bind: ele some a cada recriação e precisa ser refeito.

**`gh auth login` não é mais usado.** Se rodá-lo no container, ele grava um token
de escopo amplo em `~/.config/gh`, que é exatamente o que o desenho quer evitar.

### Remote em HTTPS

O credential helper vale para HTTPS. Se o repositório foi clonado por SSH, o push
tenta usar chave SSH, que não existe no container:

````bash
git remote -v                                                   # conferir
git remote set-url origin https://github.com/USUARIO/REPO.git   # se estiver em git@github.com:
````

### O que documentar no `CLAUDE.md`

Nada sobre o `gh` em si. O que o agente não adivinha são as regras do
repositório: branch base, o que nunca fazer. Ver Parte F.

---

## Etapa C5 — Derrubar containers conflitantes

````bash
docker compose down
````

Se o compose do time define `container_name` fixo, esse nome é único no Docker
inteiro, e a CLI falha se o banco já estiver de pé por um `docker compose up`
normal. Alternativa para manter os dois ambientes:

````yaml
services:
  db:
    container_name: nome-do-projeto-db-dev
````

Não se aplica à C3-B: nela, o devcontainer **usa** os serviços que o compose
subiu.

---

## Etapa C6 — Subir

Na **primeira vez**, sem o atalho, para ler o log:

````bash
devcontainer up --workspace-folder .
````

Baixa a imagem, roda as features, cria os volumes, sobe os serviços, espera o
healthcheck, sobe o devcontainer e executa o `postCreateCommand`.

**O `{"outcome":"success"}` no final não significa que o ambiente está pronto.**
Ele só diz que o container subiu. O `up` retorna sucesso mesmo quando o
`postCreateCommand` falha. Leia o log acima do JSON e siga para a Etapa C8, que é
o critério real.

### Confirmar o mount

Com `dockerComposeFile`, a saída do `up` **não** mostra a linha `source:`. O check
confiável, em qualquer variante, é:

````bash
devcontainer exec --workspace-folder . bash -c 'pwd; ls'
````

Tem que aparecer o `workspaceFolder` e os arquivos **deste** projeto. Se aparecer
vazio (só a `.devcontainer/` montada) ou uma lista de repositórios que não
deveriam estar ali (a pasta de cima montada), volte à regra do caminho da Etapa
C3.

Na C3-C, confira também a pasta-mãe:

````bash
devcontainer exec --workspace-folder . bash -c 'pwd; ls /workspaces/<pasta-mae>'
````

Esperado: o workspace do repo principal e, abaixo, as pastas dos repos.

---

## Etapa C7 — `postCreateCommand`: ordem e separadores

Ele concentra tudo que precisa ser refeito a cada criação do container: permissão
do auto-update, dono dos volumes, credential helper e install de dependências.
Três regras:

**1. Separe as etapas com `;`, não com `&&`.** Com `&&`, uma etapa que falha
cancela todas as seguintes, e o sintoma aparece longe da causa (ex.: lock
dessincronizado deixa o auto-update quebrado; token expirado deixa o install sem
rodar).

**2. Fixes de permissão primeiro.** Eles não dependem de rede nem do estado do
projeto, então quase nunca falham, e o install precisa deles (o volume de
dependências nasce com dono root).

**3. Install por último.** O código de saída do `postCreateCommand` é o do último
comando. Com o install no fim, uma falha dele é a que aparece no log. Qualquer
comando "inofensivo" depois dele esconderia o erro.

A estrutura, em qualquer stack:

````
<fix auto-update> ; <chown dos volumes> ; <gh auth setup-git> ; <install>
````

`&&` continua certo **dentro** de uma etapa, quando o segundo comando depende do
primeiro (ex.: `python -m venv .venv && .venv/bin/pip install ...`).

Na C3-C, com vários repos para instalar, rode cada install em subshell, separados
por `;`, para um repo com falha não impedir os outros:
`(cd /workspaces/<pasta-mae>/<repo-b> && npm ci); (cd /workspaces/<pasta-mae>/<repo-c> && npm ci)`.

### Fix do auto-update do Claude Code

````bash
D=$(npm config get prefix)/lib/node_modules/@anthropic-ai; if [ -d "$D" ]; then sudo chmod -R g+w "$D"; sudo find "$D" -type d -exec chmod g+s {} +; fi
````

**O sintoma que ele corrige:**

````
✘ Auto-update failed: no write permission to npm prefix · Run claude doctor
````

Nada quebra, mas o Claude Code nunca se atualiza sozinho.

**A causa:** as features rodam como root no build. A pasta do `@anthropic-ai` fica
com dono root, sem escrita de grupo, e o container roda como usuário não-root.

**A correção:** dar escrita ao **grupo dono do prefixo do npm**, do qual o usuário
remoto já faz parte, mais o bit setgid nos diretórios. O nome do grupo varia por
imagem (`nvm` em imagens com a feature `node:1`, `npm` em `typescript-node`), e o
comando não cita nenhum: o `g+w` vale para o grupo que for dono da pasta. Para
conferir:

````bash
ls -ld $(npm config get prefix)/lib/node_modules/@anthropic-ai
id    # o grupo acima tem que aparecer aqui
````

Em imagem própria (C3-B), se o usuário remoto **não** estiver nesse grupo, o
`g+w` não adianta: ajuste o `Dockerfile` ou a feature `common-utils`.

**Por que o setgid:** o update **cria** arquivos novos, e por padrão eles nascem no
grupo pessoal do usuário. Com setgid no diretório, herdam o grupo do diretório e
o ciclo se sustenta. Em `typescript-node` ele já vem aplicado de fábrica; o
comando é redundante ali, mas inofensivo, e cobre as imagens onde não vem.

O `if [ -d ... ]` evita falha em imagem sem a feature.

**Evite:** `chmod 777` (escrita para qualquer processo) e rodar o container como
root (todo arquivo criado pelo agente sai com dono root no teu host).

### Chown dos volumes

Volume nomeado nasce vazio e com dono root. Por stack:

| Stack | Comando |
|---|---|
| Java/Maven | `sudo chown -R vscode:vscode /home/vscode/.m2` |
| Node | `sudo chown -R node:node <workspaceFolder>/node_modules` |
| Ruby | `sudo chown -R vscode:vscode /usr/local/bundle` |
| Rust | `sudo chown -R vscode:vscode /usr/local/cargo/registry` |

Ficando no `postCreateCommand`, ele é reaplicado sozinho e roda **antes** do
install, que é quem precisa dele.

### Credential helper

````bash
if [ -n "$GH_TOKEN" ]; then gh auth setup-git; fi
````

O `if` evita falha quando o terminal não tinha o token.

---

## Etapa C8 — Validar (o critério real de "pronto")

````bash
dcsh
````

### Ambiente

````bash
pwd; ls                           # workspaceFolder, com os arquivos DESTE projeto
claude --version
java -version                     # ou node -v, python --version...
echo $SPRING_DATASOURCE_URL       # aponta para o serviço, não para localhost
ls -ld $(npm config get prefix)/lib/node_modules/@anthropic-ai   # grupo com rws
mvn -q compile                    # saída vazia = sucesso (Node: npm run build / npm test)
````

### GitHub (runbook, seção A)

````bash
echo ${#GH_TOKEN}                    # 93 — a variável CHEGOU (não prova validade)
ls ~/.config/gh                      # ERRO esperado — o bind não existe mais
git config --get-regexp credential   # helper apontando para o gh
gh auth status                       # autenticado via GH_TOKEN — prova validade
git ls-remote origin HEAD            # um SHA — prova leitura; escrita só num push real
````

Na C3-C, a leitura e a identidade dos outros repos são validadas pelo loop da
própria Etapa C3-C.

### Identidade do git (uma vez por repositório)

````bash
git config --local user.name "Seu Nome"
git config --local user.email "seu@email.com"
````

Por que `--local`: o `.git/config` fica no workspace, que é bind mount, e
sobrevive ao `dcr`. O `~/.gitconfig` do container não sobrevive, e o
`gh auth setup-git` grava só o credential helper, não a identidade.

````bash
exit
````

---

## Etapa C9 — Usar

````bash
dc
````

Na primeira execução, o Claude pede login: imprime uma URL, você abre no navegador
do host, autoriza e cola o código de volta. Como o `~/.claude` é bind, isso
acontece uma vez só, para todos os projetos.

No dia a dia: `cd` na raiz do repo que tem o `.devcontainer/`, `dc`. Mudou o
`devcontainer.json`: `dcr`.

---

## Etapa C10 — Opcional: git configurado só por ambiente

Alternativa **não testada** ao `gh auth setup-git` + `git config --local`.
Configura credencial e identidade por variáveis de ambiente, sem depender do
`postCreateCommand` nem de nada gravado no container:

````json
"remoteEnv": {
  "GH_TOKEN": "${localEnv:GH_TOKEN}",
  "GIT_CONFIG_COUNT": "1",
  "GIT_CONFIG_KEY_0": "credential.https://github.com.helper",
  "GIT_CONFIG_VALUE_0": "!gh auth git-credential",
  "GIT_AUTHOR_NAME": "${localEnv:GIT_AUTHOR_NAME}",
  "GIT_AUTHOR_EMAIL": "${localEnv:GIT_AUTHOR_EMAIL}",
  "GIT_COMMITTER_NAME": "${localEnv:GIT_AUTHOR_NAME}",
  "GIT_COMMITTER_EMAIL": "${localEnv:GIT_AUTHOR_EMAIL}"
}
````

Exige git 2.31+ e dois `export` no `~/.bashrc` do host (`GIT_AUTHOR_NAME`,
`GIT_AUTHOR_EMAIL`).

- **Ganho:** some a classe inteira de "push pede senha" e "Author identity
  unknown" depois de container reaproveitado, e o `setup-git` sai do
  `postCreateCommand`. Na C3-C, dispensa o loop de identidade.
- **Custo:** o `git config --get-regexp credential` deixa de mostrar o helper; o
  check vira `git config --show-origin -l | grep credential`. E o runbook teria
  que ser atualizado junto.

Valide em um repositório antes de adotar nos outros.

---

# PARTE C-BIS — Configurações completas por linguagem

Versões **sem banco** (Etapa C2). Para **com banco**, adapte pela C3 ou C3-B.

Em todas: sem bind de `~/.config/gh`, com `remoteEnv` do `GH_TOKEN`, e o
`postCreateCommand` na ordem da Etapa C7.

---

## Node / TypeScript

Usuário: **`node`** (o único que não é `vscode`).

````json
{
  "name": "nome-do-projeto",
  "image": "mcr.microsoft.com/devcontainers/typescript-node:22",
  "features": {
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "ghcr.io/anthropics/devcontainer-features/claude-code:1": {}
  },
  "mounts": [
    "source=${localEnv:HOME}/.claude,target=/home/node/.claude,type=bind",
    "source=${localWorkspaceFolderBasename}-node-modules,target=/workspaces/${localWorkspaceFolderBasename}/node_modules,type=volume"
  ],
  "containerEnv": {
    "CLAUDE_CONFIG_DIR": "/home/node/.claude"
  },
  "remoteEnv": {
    "GH_TOKEN": "${localEnv:GH_TOKEN}"
  },
  "remoteUser": "node",
  "updateRemoteUserUID": true,
  "postCreateCommand": "D=$(npm config get prefix)/lib/node_modules/@anthropic-ai; if [ -d \"$D\" ]; then sudo chmod -R g+w \"$D\"; sudo find \"$D\" -type d -exec chmod g+s {} +; fi; sudo chown -R node:node node_modules; if [ -n \"$GH_TOKEN\" ]; then gh auth setup-git; fi; npm ci",
  "forwardPorts": [3000]
}
````

- A feature `node:1` é dispensável: a imagem já traz Node e npm.
- Grupo do prefixo do npm nesta imagem: `npm`. O setgid já vem de fábrica.
- Todos os caminhos usam `/home/node`.
- **O volume sobre `node_modules` é obrigatório se você também roda o projeto no
  host.** Pacotes com binário nativo (`bcrypt`, `sharp`, `esbuild`) são
  compilados para o ambiente onde o install rodou; sem o volume, os dois lados
  alternam `invalid ELF header`.
- O `chown` usa caminho relativo (`node_modules`) porque o `postCreateCommand`
  roda no `workspaceFolder`.
- `npm ci`, não `npm install`: respeita o lock e não puxa versão nova sem pedido.
  Com lock dessincronizado ele falha, e é por isso que fica por último.
- pnpm ou yarn: troque por `pnpm install --frozen-lockfile` ou
  `yarn install --frozen-lockfile`.
- Variável de conexão típica: `DATABASE_URL`.

---

## Python

Usuário: **`vscode`**.

````json
{
  "name": "nome-do-projeto",
  "image": "mcr.microsoft.com/devcontainers/python:3.12",
  "features": {
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "ghcr.io/devcontainers/features/node:1": {},
    "ghcr.io/anthropics/devcontainer-features/claude-code:1": {}
  },
  "mounts": [
    "source=${localEnv:HOME}/.claude,target=/home/vscode/.claude,type=bind"
  ],
  "containerEnv": {
    "CLAUDE_CONFIG_DIR": "/home/vscode/.claude"
  },
  "remoteEnv": {
    "GH_TOKEN": "${localEnv:GH_TOKEN}"
  },
  "remoteUser": "vscode",
  "updateRemoteUserUID": true,
  "postCreateCommand": "D=$(npm config get prefix)/lib/node_modules/@anthropic-ai; if [ -d \"$D\" ]; then sudo chmod -R g+w \"$D\"; sudo find \"$D\" -type d -exec chmod g+s {} +; fi; if [ -n \"$GH_TOKEN\" ]; then gh auth setup-git; fi; python -m venv .venv && .venv/bin/pip install -r requirements.txt",
  "forwardPorts": [8000]
}
````

- Com Poetry: troque a última etapa por `pipx install poetry && poetry install`.
- Adicione `.venv/` ao `.gitignore`.
- Se também roda Python no host, use um venv fora do workspace:
  `python -m venv /home/vscode/.venv-container`.

---

## Ruby

Usuário: **`vscode`**.

````json
{
  "name": "nome-do-projeto",
  "image": "mcr.microsoft.com/devcontainers/ruby:3.3",
  "features": {
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "ghcr.io/devcontainers/features/node:1": {},
    "ghcr.io/anthropics/devcontainer-features/claude-code:1": {}
  },
  "mounts": [
    "source=${localEnv:HOME}/.claude,target=/home/vscode/.claude,type=bind",
    "source=bundle-cache,target=/usr/local/bundle,type=volume"
  ],
  "containerEnv": {
    "CLAUDE_CONFIG_DIR": "/home/vscode/.claude"
  },
  "remoteEnv": {
    "GH_TOKEN": "${localEnv:GH_TOKEN}"
  },
  "remoteUser": "vscode",
  "updateRemoteUserUID": true,
  "postCreateCommand": "D=$(npm config get prefix)/lib/node_modules/@anthropic-ai; if [ -d \"$D\" ]; then sudo chmod -R g+w \"$D\"; sudo find \"$D\" -type d -exec chmod g+s {} +; fi; sudo chown -R vscode:vscode /usr/local/bundle; if [ -n \"$GH_TOKEN\" ]; then gh auth setup-git; fi; bundle install",
  "forwardPorts": [3000]
}
````

---

## Rust

Usuário: **`vscode`**.

````json
{
  "name": "nome-do-projeto",
  "image": "mcr.microsoft.com/devcontainers/rust:1",
  "features": {
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "ghcr.io/devcontainers/features/node:1": {},
    "ghcr.io/anthropics/devcontainer-features/claude-code:1": {}
  },
  "mounts": [
    "source=${localEnv:HOME}/.claude,target=/home/vscode/.claude,type=bind",
    "source=cargo-registry,target=/usr/local/cargo/registry,type=volume"
  ],
  "containerEnv": {
    "CLAUDE_CONFIG_DIR": "/home/vscode/.claude"
  },
  "remoteEnv": {
    "GH_TOKEN": "${localEnv:GH_TOKEN}"
  },
  "remoteUser": "vscode",
  "updateRemoteUserUID": true,
  "postCreateCommand": "D=$(npm config get prefix)/lib/node_modules/@anthropic-ai; if [ -d \"$D\" ]; then sudo chmod -R g+w \"$D\"; sudo find \"$D\" -type d -exec chmod g+s {} +; fi; sudo chown -R vscode:vscode /usr/local/cargo/registry; if [ -n \"$GH_TOKEN\" ]; then gh auth setup-git; fi; cargo fetch",
  "forwardPorts": [8080]
}
````

---

## Java

Ver Etapas C2 e C3. Com Gradle, use o `./gradlew` do projeto; sem wrapper,
acrescente `"installGradle": true` na feature.

---

## Projeto poliglota

Escolha a imagem da linguagem **principal** e acrescente a outra por feature:

````json
"image": "mcr.microsoft.com/devcontainers/typescript-node:22",
"features": {
  "ghcr.io/devcontainers/features/python:1": { "version": "3.12" },
  "ghcr.io/devcontainers/features/github-cli:1": {},
  "ghcr.io/anthropics/devcontainer-features/claude-code:1": {}
}
````

Features existem para Java, Python, Ruby, Go, .NET e outras
(`ghcr.io/devcontainers/features/<linguagem>:1`). Adicione a segunda linguagem
quando o projeto precisar dela, não por precaução.

---

# PARTE D — Referência rápida

## Comandos

| Situação | Comando |
|---|---|
| Abrir o Claude | `dc` |
| Recriar o container e abrir o Claude | `dcr` |
| Shell no container | `dcsh` |
| Subir vendo o log completo | `devcontainer up --workspace-folder . --remove-existing-container` |
| Conferir o mount | `devcontainer exec --workspace-folder . bash -c 'pwd; ls'` |
| Conferir autenticação do GitHub | `gh auth status` (dentro do container) |
| Ver volumes / containers / redes | `docker volume ls` / `docker ps` / `docker network ls` |
| Listar servidores MCP | `claude mcp list` |

## Imagens por linguagem

| Linguagem | Imagem | `remoteUser` | Precisa de `node:1`? |
|---|---|---|---|
| Node/TS | `mcr.microsoft.com/devcontainers/typescript-node:22` | `node` | não |
| Java | `mcr.microsoft.com/devcontainers/java:17` (ou `:21`) | `vscode` | sim |
| Python | `mcr.microsoft.com/devcontainers/python:3.12` | `vscode` | sim |
| Ruby | `mcr.microsoft.com/devcontainers/ruby:3.3` | `vscode` | sim |
| Rust | `mcr.microsoft.com/devcontainers/rust:1` | `vscode` | sim |
| Dockerfile próprio (C3-B) | `build.target` | conferir com `id` | depende da imagem |

Quando necessária, `node:1` vem antes de `claude-code:1`.

## Erros e causas

| Erro | Causa | Solução |
|---|---|---|
| `Node.js and npm are required but could not be installed!` | imagem sem Node e sem a feature | adicionar `"ghcr.io/devcontainers/features/node:1": {}` |
| Projeto aparece vazio no container | sem compose na raiz, volume com `.` | usar `..` (Etapa C3) |
| Aparecem repositórios que não deveriam | compose do time na raiz, volume com `..` | usar `.` (Etapa C3) |
| `network ... not found` ao subir (C3-B) | compose não estava de pé, ou pasta renomeada | `initializeCommand` + `name:` fixo no compose |
| `success` no `up`, mas ambiente incompleto | `postCreateCommand` falhou | ler o log do `up` sem `>/dev/null`; Etapa C8 |
| Uma etapa do `postCreateCommand` não rodou | encadeamento com `&&` | separar com `;` (Etapa C7) |
| `Could not create local repository` / `EACCES` no install | volume com dono root | chown no `postCreateCommand`, antes do install |
| `container_name` já em uso | banco já rodando | `docker compose down` |
| Pede login do Claude toda vez | mount do `.claude` no caminho errado | conferir `remoteUser` vs. caminho do home |
| App não conecta no banco | aponta para `localhost` | env var com o nome do serviço |
| `connection refused` no primeiro run | banco ainda não aceitava conexão | `healthcheck` + `condition: service_healthy` |
| `git commit`: "Author identity unknown" | container não herda `.gitconfig` | `git config --local user.name/user.email` |
| `gh auth status` ok, mas `git push` pede senha | container reaproveitado sem credential helper | `gh auth setup-git` na mão; durável: `dcr` |
| `git push` pede senha, helper configurado | remote em SSH | `git remote set-url origin https://...` |
| `gh` age no repo errado (C3-C) | `gh` usa o repo do diretório atual | `cd <repo>` ou `gh -R dono/repo` |
| Permissões aprovadas somem (C3-C) | caminhos absolutos de um mount antigo | reaprovar; limpar `.claude/settings.local.json` |
| `echo ${#GH_TOKEN}` dá 0 no container | terminal do host sem a variável | terminal novo, conferir no host, subir de novo |
| `gh` com erro de autenticação | token expirado | runbook, seção C |
| Push recusado em `.github/workflows/` | falta *Workflows: RW* no token | editar permissões do token |
| Push recusado em repo que funcionava | repo fora da lista do token | acrescentar no token |
| `✘ Failed to connect` no MCP do GitHub | endpoint exige Copilot | usar `gh` (Etapa C4.7) |
| `CLAUDE.md` de usuário ignorado | mount `type=volume` em vez de bind | trocar por bind de `~/.claude` |
| `~/.claude` vazio no container | a pasta não existia no host | `mkdir -p ~/.claude` antes de subir |
| Permission denied no `~/.claude` | uid do host ≠ 1000 e remapeamento desligado | `updateRemoteUserUID: true` |
| `No MCP servers configured` | MCP instalado no host, não no container | `claude mcp add --scope user` de dentro |
| `invalid ELF header` em pacote nativo | `node_modules` compartilhado host/container | volume sobre `node_modules`, ou instalar só pelo container |
| Dezenas de MCPs impossíveis de remover | conectores do claude.ai | desativar em claude.ai/customize/connectors |
| `Auto-update failed: no write permission` | feature instalou como root | fix de `g+w` + setgid (Etapa C7) |
| `nc: command not found` | ferramenta não existe na imagem | não é erro de rede; testar com o build real |

---

# PARTE E — Limitações e cuidados

**O container isola o filesystem, não a rede.** O agente ainda pode fazer
`git push`, `curl` para qualquer endereço e usar as credenciais disponíveis. Se
for usar `--dangerously-skip-permissions`, veja o devcontainer de referência da
Anthropic (`anthropics/claude-code/.devcontainer`), com firewall default-deny.

**Credenciais que o container enxerga:**

| Credencial | Como chega | Alcance | Mitigação |
|---|---|---|---|
| Token da Anthropic | bind de `~/.claude` | tua conta Anthropic | consciente: é o preço do login único |
| `GH_TOKEN` | `remoteEnv` | só os repos da lista, 4 permissões | fine-grained + expiração de 90 dias |
| Histórico e transcrições (`history.jsonl`, `projects/`) | bind de `~/.claude` | conversas e trechos de código de **todos** os seus projetos | não rodar `dc` em repositório de terceiros; `type=volume` quando precisar de isolamento estrito |

O `GH_TOKEN` é legível por **qualquer** processo do container, inclusive os
scripts de `postinstall` executados pelo `npm ci`. A troca do bind pelo token
fine-grained reduz o **estrago** de um vazamento, não a **chance** dele. Na C3-C,
os installs de todos os repos somam as dependências deles nessa superfície.

**Regras que decorrem disso:**

- **Não rodar `dc` em repositório de terceiros.** O `~/.claude` é montado em
  qualquer projeto, o `GH_TOKEN` chega em qualquer projeto, e o install executa
  scripts escritos por outra pessoa.
- **`npm ci` em vez de `npm install`** no dia a dia.
- **Dependência nova merece desconfiança.** É o vetor realista de vazamento do
  token, não uma invasão da máquina. Em projeto de grupo, isso inclui
  dependência que um colega adicionou.
- **Não usar `gh auth login` no container.** Recria o token de escopo amplo que o
  desenho removeu.

**Volumes com Compose ganham prefixo; binds não.** Um volume `claude-code-config`
vira `nome-do-projeto_claude-code-config`, um por projeto. O bind de `~/.claude` é
o mesmo caminho real em todos, e é por isso que o guia o usa.

**O outro preço do bind:** o container escreve direto no teu host. Para isolamento
estrito por projeto, use `type=volume`, abrindo mão do `CLAUDE.md` global, do MCP
compartilhado e do login único.

**Reboot não quebra nada.** Os containers param; `dc` os reinicia em segundos.

**Não rode `docker system prune -a`.** Remove imagens de devcontainers de outros
projetos.

---

# PARTE F — Criando o `CLAUDE.md` do projeto

## F1 — Como os arquivos convivem

Todos carregam juntos e se somam; em conflito, o mais específico vence.

| Arquivo | Caminho no container | Escopo |
|---|---|---|
| Global (seu) | `/home/<usuário>/.claude/CLAUDE.md` | todos os projetos |
| Do repo | `<workspaceFolder>/CLAUDE.md` | só este repositório |
| Da pasta-mãe (C3-C, opcional) | `/workspaces/<pasta-mãe>/CLAUDE.md` | o conjunto de repos |

## F2 — O que vai em cada um

O global descreve **você**; o do repo descreve **o repositório**. Na C3-C, um
eventual `CLAUDE.md` da pasta-mãe descreve **como os repositórios se conectam** e
as regras de escopo (ex.: "só edite o repo que a tarefa pede; se precisar mexer
em outro, avise antes").

| Global | Do projeto |
|---|---|
| tom e estilo de resposta | stack e versões |
| limites de segurança | arquitetura e convenções |
| fluxo de trabalho pessoal | comandos para validar |
| preferências de código | armadilhas conhecidas do repo |

**Não duplique.** Duas cópias de uma regra acabam se contradizendo.

**Documente o que ele não adivinha.** Não explique que `gh` ou `mvn` existem; o
valor está nas regras do repositório.

## F3 — Modelo (exemplo: Java + Spring Modulith + Postgres)

````markdown
# exemplo-api

Projeto em grupo. API Spring Boot com arquitetura modular.

## Stack

- Java 17, Maven (sem wrapper — use `mvn`)
- Spring Boot 3.4.1, Spring Modulith 1.3.0
- PostgreSQL 16 via `docker-compose.yml`
- Spring Security + JJWT, springdoc-openapi, Lombok

## Ambiente

O banco sobe pelo `docker-compose.yml` na raiz (serviço `db`, base `postgresdb`).
Dentro do devcontainer, o host do banco é `db`, não `localhost` — já configurado
via `SPRING_DATASOURCE_URL`.

## Como validar

Antes de considerar qualquer task pronta:

```bash
mvn -q compile     # saída vazia = sucesso
mvn test           # inclui os testes de modularidade do Modulith
```

## Arquitetura

Cada módulo é um pacote de primeiro nível sob o pacote raiz. Comunicação entre
módulos pela API pública do módulo ou por eventos — nunca importando classe
interna de outro módulo. Não desative os testes de modularidade para o build
passar.

## Git e GitHub

Use o `gh` para issues, PRs e checks em vez de pedir ao usuário. Não rode
`gh auth login`: a autenticação vem do ambiente.

- Branch de trabalho é `dev`. Nunca commite nem abra PR direto para `main`.
- PR sempre com base em `dev`: `gh pr create --base dev`.
- Nunca use `push --force` em branch compartilhada.
- Commits seguem Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`).
- Não reescreva histórico nem faça rebase de branch já enviada.

## Armadilhas conhecidas

- **Flyway e `ddl-auto=update` convivem hoje.** Não "resolva" sozinho — é decisão
  do grupo.
- **O serviço `db` não tem volume.** `docker compose down` apaga os dados.
````

> Confira as regras de branch e commit contra o combinado do grupo antes de
> commitar. Instrução errada é pior que instrução ausente.

## F4 — Visibilidade

Mesma escolha da Etapa C4.

**Pessoal:**

````bash
echo "CLAUDE.md" >> .git/info/exclude
git status --short
````

**Compartilhado (recomendado quando o conteúdo é sobre o projeto):**

````bash
git add CLAUDE.md
git commit -m "docs: adiciona CLAUDE.md com convenções do projeto"
````

É bem mais fácil de propor ao grupo do que o devcontainer, porque não exige que
ninguém mude o próprio ambiente.

## F5 — `CLAUDE.md` em subpastas (opcional)

Carrega quando o Claude toca arquivos daquela pasta. Use só quando as regras
realmente divergirem entre pastas.

## F6 — Manter atualizado

Instrução desatualizada é pior que ausente: o agente segue com confiança. Revise
quando mudar uma dependência principal, um comando de build ou teste, uma
armadilha for resolvida ou o time combinar uma convenção nova.
