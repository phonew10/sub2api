#!/usr/bin/env bash
# Manage the sub2api deployment on 139.185.37.130.
#
#   ./ops/deploy-update.sh status          show running image/version vs latest release
#   ./ops/deploy-update.sh update [TAG]    back up .env, pull image (latest or TAG), restart
#   ./ops/deploy-update.sh logs            tail sub2api container logs
#   ./ops/deploy-update.sh ssh             open an interactive shell on the server
#
# SSH key lookup order: $SUB2API_SSH_KEY, ~/.ssh/dubai.key, ./ops/dubai.key
set -euo pipefail

HOST="139.185.37.130"
USER_="ubuntu"
DEPLOY_DIR="~/sub2api-deploy"
IMAGE_REPO="weishaw/sub2api"

find_key() {
  for k in "${SUB2API_SSH_KEY:-}" "$HOME/.ssh/dubai.key" "$(dirname "$0")/dubai.key"; do
    [[ -n "$k" && -f "$k" ]] && { echo "$k"; return; }
  done
  echo "error: dubai.key not found. Put it at ~/.ssh/dubai.key or set SUB2API_SSH_KEY." >&2
  exit 1
}

KEY=$(find_key)
SSH=(ssh -i "$KEY" -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new "${USER_}@${HOST}")

remote() { "${SSH[@]}" "cd ${DEPLOY_DIR} && $*"; }

latest_release() {
  curl -fsSL https://api.github.com/repos/Wei-Shaw/sub2api/releases/latest \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p'
}

cmd=${1:-status}
case "$cmd" in
  status)
    echo "==> latest upstream release: $(latest_release || echo unknown)"
    echo "==> server containers:"
    remote "sudo docker compose ps --format 'table {{.Name}}\t{{.Image}}\t{{.Status}}'"
    echo "==> sub2api image on server:"
    remote "sudo docker image inspect ${IMAGE_REPO}:latest --format '{{index .RepoDigests 0}}  created={{.Created}}' 2>/dev/null || true"
    echo "==> running app version:"
    remote "sudo docker exec sub2api /app/sub2api --version 2>&1 | grep -oE 'Sub2API [^{]*' | tail -1"
    echo "==> image configured in docker-compose.yml:"
    remote "grep -nE 'image: *${IMAGE_REPO//\//\\/}' docker-compose.yml"
    ;;
  update)
    tag=${2:-}
    echo "==> backing up .env"
    remote "cp .env .env.bak.\$(date +%Y%m%d-%H%M%S)"
    if [[ -n "$tag" ]]; then
      echo "==> pinning image to ${IMAGE_REPO}:${tag}"
      remote "sudo sed -i -E 's#image: *${IMAGE_REPO//\//\\/}:.*#image: ${IMAGE_REPO}:${tag}#' docker-compose.yml"
    fi
    echo "==> pulling image"
    remote "sudo docker compose pull sub2api"
    echo "==> restarting"
    remote "sudo docker compose up -d"
    sleep 5
    remote "sudo docker compose ps"
    echo "==> recent logs:"
    remote "sudo docker compose logs --tail=40 sub2api"
    ;;
  logs)
    remote "sudo docker compose logs -f --tail=100 sub2api"
    ;;
  ssh)
    "${SSH[@]}"
    ;;
  *)
    sed -n '2,10p' "$0"; exit 1
    ;;
esac
