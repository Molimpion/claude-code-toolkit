# Antigravity no claude-code-toolkit

Adaptação do toolkit para o **Antigravity** (app e CLI `agy`), reaproveitando o `CLAUDE.md`, as skills, os hooks e o `ai-memory` do Claude Code sem duplicar regras.

## Estrutura desta pasta

```text
antigravity/
├── README.md        # este guia
└── plugin/          # plugin toolkit-hooks (adaptador de hooks + excedente de 24 KB)
    ├── plugin.json
    ├── hooks.json
    └── adaptar.py
```

## Como a adaptação funciona

O mapa de onde cada peça do Claude entra no Antigravity está em [`docs/antigravity.md`](../docs/antigravity.md#o-que-já-vem-do-claude). O comportamento específico de cada parte:

- **Regras globais (`~/.gemini/GEMINI.md`):** symlink relativo para `~/.claude/CLAUDE.md`. Como o `CLAUDE.md` cabe com folga no limite de 24.000 bytes por arquivo de regra do Antigravity, ele é carregado inteiro — não há espelhos globais separados.
- **Skills (`claude-toolkit`):** symlinks relativos em `~/.gemini/config/plugins/claude-toolkit/skills/` apontando para `../../../../../.claude/toolkit/skills/<skill>`. Skills com `disable-model-invocation: true` no frontmatter ficam ocultas da invocação automática e só entram quando você chama `/nome`.
- **Regras locais por projeto (`.agents/rules/*.md`):** para repositórios cujo `AGENTS.md` passa dos 24.000 bytes e tem documentação densa (como `docs/testes.md`), vale manter um resumo focado com `trigger: glob` (ex.: `**/tests/**, **/src/features/**`) em `<repo>/.agents/rules/`. Coloque `.agents/` no `.git/info/exclude` para manter local e anote no topo do arquivo de qual commit da fonte ele foi extraído para detectar drift.

## Adaptador de hooks (`plugin/adaptar.py`)

O plugin `toolkit-hooks` intercepta cinco eventos do Antigravity e traduz o payload para os scripts em `~/.claude/hooks/` (symlinks para `toolkit/hooks/`) e do `ai-memory`:

1. **`SessionStart` (limite de 24 KB do `AGENTS.md`):** o Antigravity trunca cada arquivo de regra em 24.000 bytes. Quando o `AGENTS.md` na raiz de um workspace passa disso, o `adaptar.py` lê o restante a partir da linha de corte e injeta na conversa como `systemMessage`.
2. **`PreInvocation` (segredos no prompt):** roda `~/.claude/hooks/block-secrets-in-prompt.py` sobre `lastUserInput`. Se barrar (código 2), retorna `terminationBehavior: "terminate"` e encerra o turno antes do modelo.
3. **`PreToolUse` (trava de `.env`):** converte a chamada do Antigravity (`read_file`/`write_file`/`edit_file` com `Path`, `run_command` com `CommandLine`; ferramentas desconhecidas têm todos os argumentos de texto concatenados) para o formato do Claude Code e roda `~/.claude/hooks/bloquear-env.mjs`.
   - Bloqueado → retorna `decision: "deny"`.
   - Liberado → retorna `decision: "ask"` (no Antigravity, omitir `decision` nega a ferramenta; `ask` devolve a decisão às permissões normais).
4. **`PostToolUse` (log de escrita):** em `write_file` e `edit_file`, registra o caminho via `~/.claude/hooks/log-writes.py` marcando a ferramenta como `agy:<nome>`.
5. **Repasse ao `ai-memory` (quatro eventos):** o `adaptar.py` repassa `PreInvocation` (como `session-start`), `PreToolUse`, `PostToolUse` e `Stop` aos scripts em `~/.claude/ai-memory/hooks/antigravity-cli/` **apenas** quando `lastUserInput` passa no filtro de segredos. A resposta `allow` dos hooks do `ai-memory` é descartada para não sobrescrever as permissões.

## Instalação do zero

Todos os symlinks abaixo são **relativos** para funcionarem tanto no host quanto nos devcontainers (que montam `~/.claude` e `~/.gemini` em `/home/node/`).

```bash
# 1. Regras globais (CLAUDE.md -> GEMINI.md)
ln -sfn ../.claude/CLAUDE.md ~/.gemini/GEMINI.md

# 2. Plugin de skills (claude-toolkit)
mkdir -p ~/.gemini/config/plugins/claude-toolkit/skills

cat > ~/.gemini/config/plugins/claude-toolkit/plugin.json <<'EOF'
{
  "name": "claude-toolkit",
  "displayName": "Claude toolkit",
  "version": "1.0.0",
  "description": "Skills do ~/.claude/toolkit, via symlink."
}
EOF

cd ~/.gemini/config/plugins/claude-toolkit/skills
for s in ../../../../../.claude/toolkit/skills/*/; do
  n=$(basename "$s")
  ln -sfn "../../../../../.claude/toolkit/skills/$n" "$n"
done

# 3. Hooks do toolkit (~/.claude/hooks/) e do ai-memory (toolkit-hooks)
mkdir -p ~/.claude/hooks
cd ~/.claude/hooks
for h in ../toolkit/hooks/*; do
  n=$(basename "$h")
  ln -sfn "../toolkit/hooks/$n" "$n"
done

~/.claude/toolkit/ai-memory/instalar-hooks.sh
ln -sfn ../../../.claude/toolkit/antigravity/plugin ~/.gemini/config/plugins/toolkit-hooks

# 4. Validação
agy plugin validate ~/.gemini/config/plugins/claude-toolkit
agy plugin validate ~/.gemini/config/plugins/toolkit-hooks
```

## Devcontainer, login e limitações

Detalhes de uso em devcontainer (`dca`), armazenamento do token OAuth (`plugin-secrets.json` e `antigravity-oauth-token`), riscos de escopo e configuração do `mcp_config.json` do `ai-memory` estão em [`docs/antigravity.md`](../docs/antigravity.md).
