# ai-memory em devcontainers

Memória de longo prazo para o Claude Code rodando em devcontainers, usando o
[ai-memory](https://github.com/akitaonrails/ai-memory), de [Fabio Akita](https://github.com/akitaonrails).
Esta pasta não contém código do ai-memory: só a forma de rodá-lo e ligá-lo aos containers. Os
scripts de hook são extraídos da imagem oficial na hora da instalação.

O que o ai-memory faz, em resumo: hooks do Claude Code registram prompts e uso de ferramentas, o
servidor consolida cada sessão numa página markdown, e a sessão seguinte recebe um resumo do que
ficou em aberto. Com o MCP, o agente também pesquisa a memória quando precisa. A documentação
completa está no repositório dele.

## Desenho

```
 [container ai-memory] ──rede ai-memory── [devcontainer do projeto A]
          │                    └───────── [devcontainer do projeto B]
       ./data (markdown + SQLite)
```

- O servidor roda num container próprio (`compose.yml`), com a versão da imagem fixada.
- Os devcontainers entram na rede Docker `ai-memory` e falam com ele em `http://ai-memory:49374`.
  A porta publicada no host escuta só em `127.0.0.1`.
- Os hooks ficam em `~/.claude`, que os devcontainers já montam. O caminho usa
  `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, então funciona com qualquer usuário de container e no host.
- `dc.sh` substitui os atalhos `dc`/`dcr`/`dcsh` do [guia de devcontainer](../docs/devcontainer.md):
  a cada execução, liga o container à rede e passa a chave para a sessão. Projeto novo não precisa
  de configuração extra.
- Modo zero-LLM: nenhuma chave de API, nada sai da máquina.

## Pré-requisitos

- Docker e a CLI `devcontainer`.
- Devcontainers que montam `~/.claude` no home do usuário e definem `CLAUDE_CONFIG_DIR`, como no
  guia de devcontainer.
- `curl` na imagem do devcontainer. As imagens `mcr.microsoft.com/devcontainers/*` já têm; em
  imagens `-slim`, use a feature `common-utils`.
- O hook `block-secrets-in-prompt.py` instalado em `~/.claude/hooks/`: o filtro de prompts depende
  dele.

## Instalação

```bash
cd ai-memory

mkdir -p data
docker compose run --rm --no-deps ai-memory init

read -rs -p "senha root (12+ caracteres): " AI_MEMORY_AUTH__INITIAL_ROOT_PASSWORD; echo
export AI_MEMORY_AUTH__INITIAL_ROOT_PASSWORD
docker compose up -d
unset AI_MEMORY_AUTH__INITIAL_ROOT_PASSWORD
docker compose up -d --force-recreate

docker exec ai-memory ai-memory user add-human --username claude --json >/dev/null
docker exec ai-memory ai-memory user disable claude --yes
mkdir -p ~/.config/ai-memory && chmod 700 ~/.config/ai-memory
(umask 077; docker exec ai-memory ai-memory api-key add --username claude --label devcontainers --json \
  | python3 -c 'import json, sys; print(json.load(sys.stdin)["token"])' > ~/.config/ai-memory/chave)

./instalar-hooks.sh

claude mcp add-json --scope user ai-memory '{"type":"http","url":"${AI_MEMORY_HOOK_URL:-http://127.0.0.1:49374}/mcp","headers":{"Authorization":"Bearer ${AI_MEMORY_AUTH_TOKEN:-}"}}'

echo "source $(pwd)/dc.sh" >> ~/.bashrc
```

Em ordem:

1. `init` cria `data/` com a configuração e o bearer root. O bearer nunca sai de `data/`, que está
   no `.gitignore`.
2. A primeira partida cria o usuário humano `root` com a senha digitada. O `read -s` não mostra a
   senha nem a grava no histórico. Ela só vale nessa partida: o servidor ignora a variável depois,
   e o segundo `up` recria o container sem ela no ambiente. Guarde a senha num gerenciador de
   senhas; ela não é usada no dia a dia. Por que esse passo existe: ver [Root obrigatório](#root-obrigatório).
3. Cria o usuário `claude`, com login web desligado, e uma chave `aim_` para ele, salva em
   `~/.config/ai-memory/chave` com permissão `0600`. A chave lê e escreve memória, mas não acessa
   `/admin`.
4. `instalar-hooks.sh` copia os hooks da imagem para `~/.claude/ai-memory/hooks/` e adiciona uma
   entrada por evento ao `settings.json`, sem tocar nos outros hooks. Antes, salva uma cópia do
   arquivo.
5. Registra o MCP. As aspas simples guardam o texto `${...}`: o Claude Code troca pelos valores que
   o `dc` passa, então a chave nunca fica escrita na configuração.
6. Carrega o `dc.sh` no shell. Se o `~/.bashrc` já define `dc`/`dcr`/`dcsh`, remova as definições
   antigas.

Abra um terminal novo e use `dc` como sempre.

## Root obrigatório

O `user add-human` sempre grava uma senha, mesmo para o `claude`, que fica com login desligado.
Existir qualquer senha liga o modo humano do ai-memory 3.x, e nesse modo o `serve` só parte se
houver um `root` com senha e ativo. A checagem acontece só na partida: sem o root, o servidor que
já está de pé segue funcionando e o defeito aparece no primeiro reboot, com o container em loop:

```
Error: human authentication is enabled but no recoverable root user exists
```

O modo humano também recusa partir em endereço não-loopback com HTTP puro, e dentro do container o
servidor escuta em `0.0.0.0`. O `AI_MEMORY_AUTH__SECURE_COOKIE: "true"` do `compose.yml` atende essa
exigência: marca o cookie de sessão como `Secure`. Não afeta hooks nem MCP, que usam bearer. O login
web por `http://127.0.0.1` não foi testado com essa configuração.

As duas variáveis de senha ficam no `compose.yml` como referência ao ambiente do terminal. No boot
normal chegam vazias e o servidor as ignora.

### Recuperar uma instalação em loop

Para quem instalou pela versão anterior deste README, sem o passo do root. A memória em `data/` não
é perdida.

```bash
cd ai-memory
export AI_MEMORY_AUTH__RECOVERY_TOKEN="$(openssl rand -hex 32)"
docker compose up -d --force-recreate

read -rs -p "nova senha root (12+ caracteres): " P; echo
P_JSON=${P//\\/\\\\}; P_JSON=${P_JSON//\"/\\\"}
curl -sS -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:49374/auth/recovery \
  -H 'content-type: application/json' --data-binary @- <<EOF
{"recovery_token":"$AI_MEMORY_AUTH__RECOVERY_TOKEN","new_password":"$P_JSON","new_password_confirmation":"$P_JSON"}
EOF
unset P P_JSON AI_MEMORY_AUTH__RECOVERY_TOKEN
docker compose up -d --force-recreate
```

O `curl` precisa responder `204`. O token de recuperação só existe nesse terminal: com ele, o
servidor aceita partir sem root e o `POST /auth/recovery` cria o root com a senha nova. O último
`up` recria o container sem o token.

O corpo vai pela entrada padrão (`--data-binary @-` com heredoc), não como argumento: a senha e o
token não aparecem na lista de processos (`ps`). A linha do `P_JSON` escapa `\` e `"`, para que
esses caracteres na senha não quebrem o JSON.

O que os hooks não conseguiram entregar durante o loop fica em `~/.local/share/ai-memory/hook-spool/`
do lado de quem rodou o hook, e é reenviado sozinho na próxima entrega bem-sucedida. O spool de um
devcontainer fica dentro dele e se perde no `dcr`.

## Filtro de segredos

O Claude Code roda em paralelo todos os hooks de um mesmo evento. Sem cuidado, o
`block-secrets-in-prompt.py` barra o prompt, mas o hook do ai-memory já gravou o texto com o
segredo. Por isso o `UserPromptSubmit` do ai-memory passa por `~/.claude/hooks/ai-memory-prompt.sh`:
ele roda a mesma verificação antes e só encaminha o prompt se ela passar. Se o script de verificação
não existir, nada é gravado.

## Riscos

- **Uma chave para todos os projetos.** Qualquer processo dentro de qualquer devcontainer aberto
  pelo `dc` (inclusive um script de instalação de pacote) pode ler e escrever a memória de todos os
  projetos. A alternativa é uma chave por projeto, com `AI_MEMORY_AUTH__NEW_PROJECTS_RESTRICTED`, mas
  aí o perfil entre projetos do ai-memory deixa de aprender: perfil compartilhado nunca lê projeto
  restrito.
- **Memória envenenada.** Quem escreve na memória pode plantar uma "lembrança" falsa que o agente
  lerá na sessão seguinte.
- **Sem criptografia em repouso.** Prompts ficam em texto em `data/`. O sanitizador do ai-memory é
  de melhor esforço; o filtro acima cobre os padrões do `block-secrets-in-prompt.py`.
- O HTTP sem TLS trafega só no loopback e na rede Docker interna; não exponha a porta fora do host
  sem um proxy com TLS.

## Dia a dia

```bash
docker compose up -d            # liga (volta sozinho no boot)
docker compose down             # desliga; a memória continua em data/
docker logs -f ai-memory
docker exec ai-memory ai-memory status
docker exec ai-memory ai-memory list-projects
docker exec ai-memory ai-memory search --project <projeto> "termo"
```

Interface web: http://127.0.0.1:49374/web. As páginas também ficam em `data/wiki/` como markdown.

## Atualizar

```bash
./atualizar.sh 3.1.0
```

Baixa a imagem, faz backup em `data/backups/`, troca a versão no `compose.yml`, reinicia, espera o
health check e roda o `instalar-hooks.sh`, que ajusta o `settings.json` se a lista de eventos mudar.

Para voltar um backup:

```bash
docker compose stop
docker compose run --rm --no-deps ai-memory restore --from /data/backups/<arquivo>.tar.gz --force
docker compose up -d
```

Se a atualização falhou, volte também a versão anterior no `compose.yml` antes do `up -d`.

## Onde funciona

Funciona em qualquer projeto aberto com `dc`/`dcr`/`dcsh` que cumpra os pré-requisitos. Não funciona
se o devcontainer usa `--network=host` ou `--network=none`, se o Claude for aberto por outro caminho
(o servidor recusa os eventos sem chave) ou se dois projetos tiverem o mesmo nome. O ai-memory nomeia
o projeto pelo remoto do git; sem remoto, pela pasta. Um `.ai-memory.toml` na raiz do repositório
define o nome explicitamente.
