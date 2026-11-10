# Antigravity CLI (`agy`) com o toolkit

Como o `agy` usa as mesmas regras, skills, hooks e memória do Claude Code, no host e no
devcontainer.

## O que já vem do Claude

| Peça | Onde fica no `agy` | Como |
|---|---|---|
| `CLAUDE.md` global | `~/.gemini/GEMINI.md` | symlink relativo: `ln -sfn ../.claude/CLAUDE.md ~/.gemini/GEMINI.md` |
| Skills | plugin em `~/.gemini/config/plugins/<nome>/skills/` | um symlink relativo por skill, para `../../../../../.claude/toolkit/skills/<skill>` |
| Hooks do toolkit e do ai-memory | plugin `toolkit-hooks` | ver [Hooks](#hooks) |
| MCP do ai-memory | `~/.gemini/config/mcp_config.json` | ver [Limitações](#limitações) |

**Todo symlink é relativo.** O devcontainer monta `~/.claude` e `~/.gemini` em
`/home/node/`, e um link absoluto para `/home/<você>/...` não existe lá dentro: o
arquivo some sem aviso, pelo mesmo motivo das skills do Claude no README.

## Hooks

O plugin está em [`antigravity/plugin/`](../antigravity/plugin/). Instalação e o que cada
evento faz: seção "Antigravity CLI" do [README](../README.md).

O que mudou em relação ao Claude, medido no `agy` 1.5.4:

- Ferramentas: `read_file`, `write_file` e `edit_file` levam o caminho em `Path`;
  `run_command` leva o comando em `CommandLine`. Payload em camelCase, com
  `lastUserInput` em todo evento.
- **`PreToolUse` sem `decision` nega a ferramenta.** O neutro é `ask`, que devolve a
  decisão às permissões do `agy`. `allow` aprova a ferramenta, e o hook do ai-memory
  responde `allow` em tudo: o adaptador descarta essa resposta.
- Prompt barrado no `PreInvocation` com `terminationBehavior: "terminate"` e um
  `errorMessage` encerra o turno antes do modelo; no `-p`, o `agy` sai com código 3.
- Os quatro hooks do ai-memory mandam o payload inteiro, `lastUserInput` incluído, e o
  `Stop` dispara mesmo depois de um prompt barrado. Por isso o adaptador só repassa ao
  ai-memory quando o `lastUserInput` passa no filtro de segredo, e não repassa nada se o
  filtro faltar.
- Ferramenta que o adaptador não conhece passa pela trava do arquivo de segredos com
  todos os argumentos de texto juntos. Argumento que só cita o nome do arquivo também é
  barrado.

## No devcontainer: `dca`

O `dca`, do [`ai-memory/dc.sh`](../ai-memory/dc.sh), é o `dc` abrindo o `agy`. Não há
feature de devcontainer para o `agy`, então o serviço do container monta o binário e a
configuração do host:

````yaml
    volumes:
      - ${HOME}/.gemini:/home/node/.gemini
      - ${HOME}/.config/antigravity:/home/node/.config/antigravity
      - ${HOME}/.local/bin/agy:/usr/local/bin/agy:ro
````

O `~/.config/antigravity` guarda as credenciais dos MCPs de plugin (Figma, Linear, Trello,
Supabase, Vercel e outros) em `plugin-secrets.json`, no host e no container: o log mostra
`Using file-based secret storage at .../.config/antigravity/plugin-secrets.json`. Sem esse bind,
nenhum MCP de plugin funciona no container, e o que for autorizado lá dentro some no `dcr`. É o
mesmo trato do `~/.claude`, que leva as credenciais do Claude Code para o container.

Os hooks do plugin precisam de `python3` e `node` no container; a imagem
`typescript-node` tem os dois. Uso simultâneo com o `dc`, `dca -c` e o `dcr`: Etapa B6
do [guia de devcontainer](devcontainer.md).

## Login

No host, o `agy` guarda o login no keyring do sistema (Secret Service), que o container
não enxerga. No primeiro `dca` ele abre "You are currently not signed in": escolha
**Google OAuth**, abra a URL no navegador e cole o código.

O login feito no container vai para `~/.gemini/antigravity-cli/antigravity-oauth-token`
(`0600`). Como o `~/.gemini` é bind do host, ele sobrevive ao `dcr` e vale para todos os
devcontainers.

**Risco:** esse token tem escopo `cloud-platform`, que dá acesso amplo ao Google Cloud da
conta, e fica legível por qualquer processo de qualquer devcontainer que monte o
`~/.gemini`, inclusive os scripts do `npm ci`, e não só nas sessões abertas pelo `dca`. Ao
contrário do `GH_TOKEN`, não dá para restringir o alcance. O mesmo vale para o
`plugin-secrets.json`: os tokens OAuth de todos os MCPs de plugin ficam ao alcance de qualquer
processo do container, e os de Supabase e Vercel rodam SQL em banco remoto e mexem em deploy. A
regra de não rodar `dc` em repositório de terceiro vale em dobro aqui.

## Limitações

- O `mcp_config.json` é o mesmo no host e no container, e o endereço do ai-memory muda
  entre os dois: `127.0.0.1:49374` no host, `ai-memory:49374` na rede Docker. A saída é
  usar o nome nos dois lados:

  ````bash
  echo '127.0.0.1 ai-memory' | sudo tee -a /etc/hosts
  ````

  e `"serverUrl": "http://ai-memory:49374/mcp"` na entrada `ai-memory` do
  `~/.gemini/config/mcp_config.json`. O servidor aceita o nome porque `ai-memory` está no
  `AI_MEMORY_ALLOWED_HOSTS` do `compose.yml`. Sem isso, a pesquisa por MCP falha no
  container; os hooks funcionam de qualquer jeito, porque usam o `AI_MEMORY_HOOK_URL` que o
  `dc.sh` passa.
- O `mcp_config.json` guarda a chave do ai-memory escrita no arquivo (`0600`), não por
  variável de ambiente.
- O `agy` dentro do container não se atualiza sozinho: o binário é montado só leitura.
  Atualize no host.
