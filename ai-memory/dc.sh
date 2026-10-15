AI_MEMORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AI_MEMORY_KEY_FILE="$HOME/.config/ai-memory/chave"
AI_MEMORY_URL_IN_CONTAINER="http://ai-memory:49374"

_dc_up() {
  local out id
  out=$(devcontainer up --workspace-folder . "$@") || return 1
  id=$(printf '%s\n' "$out" | tail -n 1 | python3 -c 'import json, sys; print(json.load(sys.stdin)["containerId"])') || return 1

  if ! docker network inspect ai-memory >/dev/null 2>&1; then
    echo "ai-memory: servidor desligado, seguindo sem memória (cd $AI_MEMORY_DIR && docker compose up -d)" >&2
    return 0
  fi
  if [ -z "$(docker inspect -f '{{if index .NetworkSettings.Networks "ai-memory"}}sim{{end}}' "$id")" ]; then
    docker network connect ai-memory "$id" || echo "ai-memory: não consegui ligar o container à rede, seguindo sem memória" >&2
  fi
}

_dc_env() {
  _DC_ENV=()
  [ -r "$AI_MEMORY_KEY_FILE" ] || return 0
  _DC_ENV=(
    --remote-env "AI_MEMORY_HOOK_URL=$AI_MEMORY_URL_IN_CONTAINER"
    --remote-env "AI_MEMORY_AUTH_TOKEN=$(cat "$AI_MEMORY_KEY_FILE")"
  )
}

dc() {
  _dc_up && _dc_env && devcontainer exec --workspace-folder . "${_DC_ENV[@]}" claude "$@"
}

dcr() {
  _dc_up --remove-existing-container && _dc_env && devcontainer exec --workspace-folder . "${_DC_ENV[@]}" claude "$@"
}

dcsh() {
  _dc_up && _dc_env && devcontainer exec --workspace-folder . "${_DC_ENV[@]}" bash
}
