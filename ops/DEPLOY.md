# sub2api — Our Deployment & Upstream Sync Guide

This fork (`phonew10/sub2api`) tracks upstream `Wei-Shaw/sub2api`. Everything specific to
**our** deployment lives in `ops/` so upstream merges never conflict with it.

## Server

| Item | Value |
| :--- | :--- |
| Public URL | https://sub2api.sellersheetai.com (Cloudflare in front) |
| Host | `139.185.37.130` |
| User | `ubuntu` |
| SSH key | `dubai.key` (keep at `~/.ssh/dubai.key`, never commit it) |
| SSH | `ssh -i ~/.ssh/dubai.key ubuntu@139.185.37.130` |
| Deploy dir | `~/sub2api-deploy` |
| Nginx config | `/etc/nginx/sites-available/sub2api` (symlinked into `sites-enabled`) |
| SSL cert / key | `/etc/nginx/ssl/nginx.pem` + `/etc/nginx/ssl/nginx.key` (Cloudflare Origin Cert) |
| Nginx conf copy | `ops/nginx/sub2api.conf` in this repo (proxies 443 → `127.0.0.1:8080`) |
| Env file | `~/sub2api-deploy/.env` |
| Postgres data | `~/sub2api-deploy/postgres_data` |
| Redis data | `~/sub2api-deploy/redis_data` |

## How the deployment gets its code

The server runs the **prebuilt upstream image** `weishaw/sub2api:latest` from Docker Hub via
`docker compose` (see `deploy/docker-compose.yml`). It does **not** build from this repo.
So "keeping the deploy up to date" means pulling a newer image, and "keeping the fork up to
date" means fast-forwarding `main` to upstream. The two are independent and both are scripted:

| Goal | Command (run from repo root) |
| :--- | :--- |
| Sync fork `main` with upstream | `./ops/sync-upstream.sh` |
| Check what version the server runs vs. latest release | `./ops/deploy-update.sh status` |
| Update the server to the latest image | `./ops/deploy-update.sh update` |
| Roll the server back to a pinned tag | `./ops/deploy-update.sh update 0.2.2` |

Upstream releases every few days (v0.1.183 → v0.2.3 between 2026-08-25 and 2026-09-08), and
Docker Hub publishes `latest`, `0`, `0.2`, `0.2.3`, plus `-amd64`/`-arm64` variants for each
tag. Release notes: https://github.com/Wei-Shaw/sub2api/releases

## Service management (Docker Compose)

All commands run on the server inside `~/sub2api-deploy`:

| Action | Command |
| :--- | :--- |
| Start | `sudo docker compose up -d` |
| Stop | `sudo docker compose down` |
| Restart | `sudo docker compose restart` |
| Logs | `sudo docker compose logs -f sub2api` |
| Status | `sudo docker compose ps` |

## Manual update (what `deploy-update.sh update` does)

```bash
ssh -i ~/.ssh/dubai.key ubuntu@139.185.37.130
cd ~/sub2api-deploy
cp .env .env.bak.$(date +%Y%m%d-%H%M%S)      # back up config first
sudo docker compose pull
sudo docker compose up -d
sudo docker compose ps
sudo docker compose logs --tail=50 sub2api
```

> **Before any major change** back up `.env`, `postgres_data/` and `redis_data/`.
> Rollback: set `image: weishaw/sub2api:<previous tag>` in `docker-compose.yml`, then
> `sudo docker compose up -d`. Note that upstream runs DB migrations on start; check the
> release notes for a version before rolling back across it.

## Nginx

| Action | Command |
| :--- | :--- |
| Check syntax | `sudo nginx -t` |
| Apply changes | `sudo systemctl reload nginx` |
| Access log | `sudo tail -f /var/log/nginx/sub2api-access.log` |
| Error log | `sudo tail -f /var/log/nginx/error.log` |

## Troubleshooting

1. **Service not responding** — `sudo docker compose ps`; if a container is restarting,
   `sudo docker compose logs --tail=200 sub2api`.
2. **Nginx error** — `sudo tail -f /var/log/nginx/error.log`, then `sudo nginx -t`.
3. **Database issues** — `sudo docker compose logs postgres`.
4. **After an update the app won't start** — compare `deploy/.env.example` at the new tag
   with the server's `.env`; new required variables are the usual cause.

## Known drift from upstream (as of 2026-09-09)

- **docker-compose.yml on the server is an older layout** (dated 2026-03-12). It uses bind
  mounts `./postgres_data`, `./redis_data`, `./data`, while upstream's current
  `deploy/docker-compose.yml` uses named Docker volumes and adds a Postgres tuning `command`.
  **Do not copy upstream's compose file over the server's one blindly** – the data would
  end up in new empty volumes. If we ever adopt the new layout, migrate data explicitly.
  The old layout still works with the latest image; `docker compose pull && up -d` is enough.
- **Server `.env` is missing ~27 newer optional keys** (image-gen concurrency,
  OpenAI HTTP/2 fallback, `REDIS_USERNAME`, `SETUP_MIGRATION_TIMEOUT_SECONDS`,
  `UPDATE_GITHUB_TOKEN`, `APPLE_CONTAINER_*`). All have defaults; add them only when needed.
  Compare with: `comm -13 <(server keys) <(grep -v '^#' deploy/.env.example | cut -d= -f1 | sort)`.
- **Disk was 93 % full on 2026-09-09; now 81 % (8.9 GB free of 45 GB)** after
  `journalctl --vacuum-size=500M` (freed 3.5 GB, `SystemMaxUse=500M` now set in
  `/etc/systemd/journald.conf`) and `docker image prune -f` (freed 0.5 GB). sub2api itself
  uses ~1 GB. Remaining big items, all unrelated to sub2api: a 16 GB `/swapfile`,
  nacos (`/opt/nacos` 4.3 GB + 4.4 GB of old logs in `~/logs/nacos`), the dormant wimoor
  stack (`/opt/wimoor` 1.9 GB, not running, port 8099 dead), old snap revisions (~1 GB).
  Run `sudo docker image prune -f` after each sub2api update to drop the previous image.
- Memory is 1 GB total with ~75 MB free; Postgres + Redis + app fit, but don't add services.

## Keeping the fork in sync with upstream

`main` = upstream `main` + our `ops/` directory (plus the `dubai.key` line in `.gitignore`).
Keep our own changes under `ops/` so merges stay conflict-free. Run `./ops/sync-upstream.sh`
regularly; it fetches upstream, merges it into `main`, pushes to `origin`, and prints the
latest upstream tag. Merging the fork does **not** update the server; use
`./ops/deploy-update.sh update` for that (the server pulls the upstream Docker image).

Remotes expected in the local clone:

```
origin    https://github.com/phonew10/sub2api.git
upstream  https://github.com/Wei-Shaw/sub2api.git
```

## Change log (ours)

- 2026-09-09: Server verified running Sub2API 0.2.3 (= latest release), all 3 containers
  healthy, `/health` OK, nginx config test OK.
- 2026-09-09: Cloned fork to `~/Documents/workspace-coder/sub2api`, added `upstream` remote,
  added `ops/` with this guide and the two scripts. Fork was identical to upstream `main`
  (latest release v0.2.3, published 2026-09-08).
