#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

version="${1:-}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "uso: ./atualizar.sh 3.1.0" >&2; exit 1; }

current="$(sed -n 's/^\s*image:\s*akitaonrails\/ai-memory:\(.*\)$/\1/p' compose.yml)"
echo "versão atual: $current -> nova: $version"

docker pull "akitaonrails/ai-memory:$version"

backup="/data/backups/antes-de-$version-$(date +%Y%m%d-%H%M%S).tar.gz"
docker exec ai-memory ai-memory backup --to "$backup"
echo "backup em data/${backup#/data/}"

sed -i "s|akitaonrails/ai-memory:$current|akitaonrails/ai-memory:$version|" compose.yml
docker compose up -d

for _ in $(seq 1 30); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' ai-memory)" = healthy ] && break
  sleep 2
done
status="$(docker inspect -f '{{.State.Health.Status}}' ai-memory)"
if [ "$status" != healthy ]; then
  echo "o servidor não ficou saudável ($status); veja: docker logs ai-memory" >&2
  echo "para voltar: troque a versão no compose.yml para $current e rode docker compose up -d" >&2
  exit 1
fi
echo "servidor $version no ar"

./instalar-hooks.sh
