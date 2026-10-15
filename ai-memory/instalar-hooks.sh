#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
settings="$config_dir/settings.json"
image="$(sed -n 's/^\s*image:\s*\(akitaonrails\/ai-memory:.*\)$/\1/p' compose.yml)"
[ -n "$image" ] || { echo "não achei a imagem do ai-memory no compose.yml" >&2; exit 1; }
[ -f "$settings" ] || { echo "não achei $settings" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "extraindo hooks de $image"
docker run --rm --user "$(id -u):$(id -g)" --network none -v "$work:/out" \
  --entrypoint /usr/local/bin/ai-memory "$image" \
  setup-agent --agent claude-code --to /out >"$work/snippet.txt" 2>/dev/null

hooks_dir="$config_dir/ai-memory/hooks"
rm -rf "$hooks_dir.novo"
mkdir -p "$hooks_dir.novo/claude-code"
install -m 0644 "$work/_lib.sh" "$hooks_dir.novo/_lib.sh"
for f in "$work"/claude-code/*.sh; do
  install -m 0755 "$f" "$hooks_dir.novo/claude-code/"
done
rm -rf "$hooks_dir"
mv "$hooks_dir.novo" "$hooks_dir"

mkdir -p "$config_dir/hooks"
cat >"$config_dir/hooks/ai-memory-prompt.sh" <<'EOF'
#!/bin/sh
payload=$(cat)
printf '%s' "$payload" | python3 "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/block-secrets-in-prompt.py" 2>/dev/null || { printf '{}\n'; exit 0; }
printf '%s' "$payload" | sh "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/ai-memory/hooks/claude-code/user-prompt-submit.sh"
EOF
chmod 0755 "$config_dir/hooks/ai-memory-prompt.sh"

cp -p "$settings" "$settings.bak-ai-memory-$(date +%Y%m%d-%H%M%S)"

python3 - "$settings" "$work/snippet.txt" <<'EOF'
import json
import os
import sys

settings_path, snippet_path = sys.argv[1], sys.argv[2]
raw = open(snippet_path, encoding="utf-8").read()
snippet = json.loads(raw[raw.index("\n{") + 1:])

base = "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"


def is_ai_memory(command):
    return "ai-memory/hooks/claude-code/" in command or "ai-memory-prompt.sh" in command


def command_for(event, original):
    if event == "UserPromptSubmit":
        return f'sh "{base}/hooks/ai-memory-prompt.sh"'
    script = original.rsplit("/", 1)[1]
    return f'sh "{base}/ai-memory/hooks/claude-code/{script}"'


with open(settings_path, encoding="utf-8") as f:
    settings = json.load(f)
hooks = settings.setdefault("hooks", {})

before = set()
for event in list(hooks):
    groups = []
    for group in hooks[event]:
        entries = [h for h in group.get("hooks", []) if not is_ai_memory(h.get("command", ""))]
        if len(entries) < len(group.get("hooks", [])):
            before.add(event)
        if entries:
            groups.append({**group, "hooks": entries})
    if groups:
        hooks[event] = groups
    else:
        del hooks[event]

after = set()
for event, groups in snippet["hooks"].items():
    for group in groups:
        entries = [
            {"type": "command", "command": command_for(event, h["command"])}
            for h in group["hooks"]
        ]
        hooks.setdefault(event, []).append({"matcher": group.get("matcher", ""), "hooks": entries})
    after.add(event)

tmp = settings_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, settings_path)

if before:
    for event in sorted(after - before):
        print(f"evento novo adicionado: {event}")
    for event in sorted(before - after):
        print(f"evento removido (não existe mais nesta versão): {event}")
print(f"hooks do ai-memory instalados em {len(after)} eventos")
EOF

echo "reinicie as sessões do Claude Code para os hooks valerem"
