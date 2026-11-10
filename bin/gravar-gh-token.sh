#!/usr/bin/env bash
set -euo pipefail

destino="$HOME/.config/gh-devcontainer/token"

read -rs -p "fine-grained token (github_pat_...): " token; echo
case "$token" in
  github_pat_*) ;;
  *) echo "não começa com github_pat_: não é um fine-grained token" >&2; exit 1 ;;
esac

cabecalhos="$(GH_TOKEN="$token" gh api -i user 2>/dev/null)" || { echo "o GitHub recusou o token" >&2; exit 1; }
login="$(printf '%s' "$cabecalhos" | sed -n 's/^.*"login":"\([^"]*\)".*$/\1/p' | head -n 1)"
expira="$(printf '%s' "$cabecalhos" | sed -n 's/^github-authentication-token-expiration: *//Ip' | tr -d '\r')"

echo "login: $login"
echo "expira: ${expira:-sem data de expiração}"
echo "repositórios privados que o token alcança (público qualquer token lê):"
GH_TOKEN="$token" gh api --paginate user/repos --jq '.[] | select(.private) | .full_name' | sed 's/^/  /'

mkdir -p "$(dirname "$destino")"
chmod 700 "$(dirname "$destino")"
(umask 077; printf '%s\n' "$token" > "$destino")
echo "gravado em $destino"
