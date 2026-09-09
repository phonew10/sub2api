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
- **Disk was 93 % full on 2026-09-09; now 70 % (14 GB free of 45 GB)** after
  `journalctl --vacuum-size=500M` (freed 3.5 GB, `SystemMaxUse=500M` now set in
  `/etc/systemd/journald.conf`) and `docker image prune -f` (0.5 GB), old nacos logs (5 GB), disabled snap revisions (1 GB) and apt cache. sub2api itself
  uses ~1 GB. Remaining big items, all unrelated to sub2api: a 16 GB `/swapfile`,
  nacos (`/opt/nacos` 3.6 GB, mostly raft data), the dormant wimoor
  stack (`/opt/wimoor` 1.9 GB, not running, port 8099 dead), old snap revisions (~1 GB).
  Run `sudo docker image prune -f` after each sub2api update to drop the previous image.
- Memory is 1 GB total with ~75 MB free; Postgres + Redis + app fit, but don't add services.

## Image generation status (tested 2026-09-09)

API key used for tests: the `sub2api-test` key in group `OpenClaw专用` (group 3), which
holds the three **free-plan** ChatGPT OAuth accounts. No API-key (platform key) accounts exist.

**Relay side.** `/v1/images/generations` and `/v1/images/edits` parse and forward `size`,
`output_format`, `output_compression`, `mask` (as `input_image_mask`), `quality`,
`background`, `input_fidelity`, `n`, `partial_images` and `stream`. Any of `size`, `mask`,
`output_format`, `output_compression` marks the request "images-native"; OAuth accounts
qualify for that, so nothing is blocked by the relay itself.

**Upstream side, free ChatGPT accounts.** Image generation does not work, for two
independent reasons:

1. v0.2.3 wraps every `/v1/images/*` call in a hidden Responses call using the hard-coded
   carrier model `gpt-5.4-mini`, which OpenAI has retired. Every call fails with
   `The 'gpt-5.4-mini' model is not supported when using Codex with a ChatGPT account`
   (upstream issue #6855; fix PR #6858 switches to `gpt-5.6-luna` and adds a
   `SUB2API_IMAGES_MAIN_MODEL` override; not merged or released as of 2026-09-09).
2. Even with a working carrier (`gpt-5.6-luna` does work for chat on these accounts),
   OpenAI's Codex backend silently drops the `image_generation` tool for free-plan
   accounts: a forced `tool_choice` returns `Tool choice 'image_generation' not found in
   'tools' parameter`, and an unforced one returns text only. Upstream issues #3403 and
   #1849 confirm free accounts lost image generation when upstream moved to the new
   Codex image path in v0.1.116. A Plus/Pro OAuth account or an OpenAI API-key account is
   required.

So `mask`, `output_format=jpeg`, `output_compression` and `size` could **not** be
verified end to end on this deployment. To finish the test add a paid OAuth account or an
API-key account to group 3, wait for the PR #6858 fix to ship (or run a fork build with
`SUB2API_IMAGES_MAIN_MODEL=gpt-5.6-luna`), then rerun the calls in
`ops/e2e/image-params.sh` (it reads the test key from the gitignored `ops/.env`).

**Model whitelist.** Each OpenAI OAuth account carries a whitelist stored in the database
(`accounts.credentials->'model_mapping'`), not in source code. It is set from the admin UI
(account form → **Model Restriction (Optional)** → **Model Whitelist**) and is only as fresh
as the last time someone pressed **Sync upstream models** there. Nothing refreshes it
automatically, so when OpenAI ships a new id it is rejected by the relay with
`model_not_supported` until the list is synced again.

History:
- March 2026: accounts added, whitelist synced → 54 ids. Every one of them later became
  plan-gated or retired for free accounts, so the relay returned 400/404 for everything.
- 2026-09-09 early: `gpt-5.6-luna`, `gpt-5.5`, `gpt-6-astra`, `gpt-image-1`, `gpt-image-2`
  added by SQL during testing; `gpt-5.6-luna` was the only id that worked.
- 2026-09-09 10:04: whitelist re-synced from upstream through the admin UI on all three
  accounts → **62 ids**, now including `gpt-5.6-luna`, `gpt-5.6-terra`, `gpt-6-astra`,
  `gpt-5.5`, `gpt-image-1`, `gpt-image-2`, `gpt-reserve`, `codex-auto-review`.
  The UI sync is the supported way to keep this current; do it after each upstream release.

Of the whole list, on **free** accounts only `gpt-5.6-luna` has answered successfully
(`gpt-5.6-terra` untested); older ids return `not supported when using Codex with a ChatGPT
account` and the relay parks them for 30 min (`upstream_400_codex_plan_gated_model`).

Alternative: clearing the whitelist (empty mapping) makes an OAuth account accept any model
id and lets OpenAI decide, which removes the need to re-sync. `usage_logs` had zero rows
before 2026-09-09, so the deployment had never served a successful request before then.

## Third-party relay test (xxcapi.top), 2026-09-09

While our own deployment cannot generate images, a paid third-party relay was tested for
gpt-image-2 with the same Amazon infographic. Full write-up, prompts, mask, request bodies
and jpeg samples are in `ops/e2e/xxcapi/` (`RESULTS.md`, `run.sh`; key lives in `ops/.env`
as `XXCAPI_KEY`). Summary with `gpt-image-2-medium`:

| Parameter | Honored |
| :--- | :--- |
| prompt, text rendering | yes |
| size, incl. arbitrary 1536x864 and 2048x2048 | yes, exact |
| edits with reference image | yes |
| edits with `mask` | **no**, mask field dropped (decisive probe 2026-09-10: `ops/e2e/xxcapi/mask-probe.sh`) |
| response_format b64_json | yes (default is a hosted PNG URL + task_id) |
| output_format jpeg, output_compression | **no**, always PNG |
| high tier / quality=high | no channel available during test |

Output carries an OpenAI-signed C2PA manifest ("OpenAI Media Service API", gpt-image 2.0),
so the pixels are real OpenAI output; the exact non-preset size means a real Images API sits
behind the relay, with the relay stripping format/compression and re-hosting as PNG.
Pricing was ¥0.045 per 1K and ¥0.055 per 2K medium image, several times below OpenAI list.

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
