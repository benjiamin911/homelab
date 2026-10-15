#!/usr/bin/env bash
# One-click deploy for homelab services.
#   ./deploy.sh up [svc...]     # start/update (default: all). idempotent.
#   ./deploy.sh update [svc...] # pull latest images, then up -d
#   ./deploy.sh down [svc...]
#   ./deploy.sh pull [svc...]
#   ./deploy.sh restart [svc...]
#   ./deploy.sh logs <svc>
#   ./deploy.sh ps                # status of all services
#   ./deploy.sh list              # list known services
# Add a service: create services/<name>/compose.yml, then ./deploy.sh up <name>
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT/.env"
SERVICES_DIR="$ROOT/services"
[ -f "$ENV_FILE" ] || { echo "ERROR: $ENV_FILE missing. Copy .env.example to .env."; exit 1; }
set -a; . "$ENV_FILE"; set +a
: "${DATA_ROOT:=$ROOT/data}"

list_services(){ for d in "$SERVICES_DIR"/*/; do n="$(basename "$d")"; case "$n" in _*) continue;; esac; [ -f "$d/compose.yml" ] && echo "$n"; done; }
dc(){ local s="$1"; shift; docker compose --project-name "$s" --env-file "$ENV_FILE" -f "$SERVICES_DIR/$s/compose.yml" "$@"; }
targets(){ if [ "$#" -gt 0 ]; then printf '%s\n' "$@"; else list_services; fi; }

cmd="${1:-up}"; shift || true
case "$cmd" in
  up|deploy)  for s in $(targets "$@"); do echo "== up $s =="; mkdir -p "$DATA_ROOT/$s"; dc "$s" up -d; done ;;
  update)     for s in $(targets "$@"); do echo "== update $s =="; dc "$s" pull; mkdir -p "$DATA_ROOT/$s"; dc "$s" up -d; done ;;
  down)       for s in $(targets "$@"); do echo "== down $s =="; dc "$s" down; done ;;
  pull)       for s in $(targets "$@"); do echo "== pull $s =="; dc "$s" pull; done ;;
  restart)    for s in $(targets "$@"); do echo "== restart $s =="; dc "$s" restart; done ;;
  logs)       [ "$#" -ge 1 ] || { echo "usage: deploy.sh logs <svc>"; exit 1; }; dc "$1" logs -f --tail=100 ;;
  ps|status)  for s in $(list_services); do echo "== $s =="; dc "$s" ps; done ;;
  list|ls)    list_services ;;
  *) echo "usage: deploy.sh {up|update|down|pull|restart|logs <svc>|ps|list} [services...]"; exit 1 ;;
esac
