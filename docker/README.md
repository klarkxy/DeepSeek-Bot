# DS Bot in Docker

This directory deploys DS Bot as a Docker image: a `dsh web` server (DeepSeek
Harness) with the `ds-bot` plugin installed, ready for a NAS or any always-on
box. The container is the sandbox boundary — see [Permissions](#permissions).

## Requirements

- Docker 24+ with Compose v2.24+ (Docker Desktop, or Docker Engine + the
  compose plugin — `env_file.required` needs 2.24).
- Linux containers, x86-64. arm64 builds should work (`node:24-bookworm-slim` is
  multi-arch) but are untested.
- A DeepSeek API key (or another Anthropic-Messages-compatible endpoint through
  `DEEPSEEK_BASE_URL`).

## Quick start

```sh
cd docker
cp .env.example .env
# edit .env: DEEPSEEK_API_KEY, DSH_TRUSTED_HOST (the NAS IP), PUID/PGID
docker compose up -d
docker compose logs ds-bot | grep "dsh web:"
```

The log prints a line like `dsh web: http://<container
IP>:3080/?token=…` (on dsh 0.2.1-alpha.1: `http://127.0.0.1:3080/?token=…
(LAN: http://172.x.x.x:3080/?token=…)`). Take the token from it and open
`http://<NAS IP>:3080/?token=…` once in your browser: the token sets a signed
cookie (valid 30 days, bound to that authority), after which
`http://<NAS IP>:3080/` opens the UI directly. The first time the team opens,
DS Bot creates a Main Bot called Chief.

## Permissions

The container is the only sandbox. DSH's own kernel sandbox (bubblewrap /
Landlock) does not run inside Docker's default seccomp profile or on most NAS
kernels, so the image offers exactly one permission preset, **Full access**:
every Bot command runs without asking. Only mount folders the Bots may change
into `/workspace`, and run the container with `PUID`/`PGID` of the share owner
so file ownership stays right.

## Network

`dsh web` binds one concrete interface address — by default the container's
own address, which the trust fence automatically trusts. Browsers reach it
through the published port, so list every IP and name you open the UI at in
`DSH_TRUSTED_HOST` (no port — a bare entry trusts it on any port): the fence
checks the `Host` header of every `/api` request and answers 403 for anything
untrusted. Loopback is always trusted. `DSH_HOST=127.0.0.1` keeps the server
on loopback only — useful when a reverse proxy shares its network namespace;
published ports then no longer reach it.

dsh 0.2.1-alpha.1 cannot bind a single address; on that version the
entrypoint binds all interfaces through a config overlay
(`legacy-bind-alpha1.sh`) — inside a container the published port is still
the boundary.

Alternatives:

- **Host network**: set `network_mode: host` in `compose.yml` and drop `ports:`.
  The server then binds the NAS's first address (`hostname -i`; set `DSH_HOST`
  to pick another) on `DSH_LISTEN_PORT` (default 3080); `DSH_HOST=127.0.0.1`
  narrows it to loopback again.
- **Reverse proxy / HTTPS**: set `DSH_PUBLIC_URL=https://ds-bot.example.com/`
  (trailing slash) and add `ds-bot.example.com` to `DSH_TRUSTED_HOST`.

**HTTPS is recommended, not required.** The UI works over plain
`http://<LAN IP>` on this dsh release, but the page is not a secure context
there: API keys and secret values you type cross the LAN in clear text. Put a
reverse proxy in front for regular use.

## Environment variables

See `.env.example` for the full list. The main ones:

| Variable | Purpose |
|---|---|
| `DEEPSEEK_API_KEY` | API key for the model endpoint |
| `DEEPSEEK_BASE_URL` | Override the endpoint (Anthropic-Messages-compatible) |
| `DSH_TRUSTED_HOST` | Comma-separated host names / IPs the UI answers to |
| `DSH_PUBLIC_URL` | Public URL behind a reverse proxy |
| `DSH_PORT` | Published port on the Docker host (default 3080; the container always listens on 3080) |
| `DSH_HOST` | Bind address (default: the container's own address; dsh 0.2.1-alpha.1: all interfaces). `127.0.0.1` = loopback only |
| `DSH_LISTEN_PORT` | Listen port inside the container (default 3080); only relevant with `network_mode: host` |
| `PUID` / `PGID` | User/group the server runs as and new files belong to |
| `DSH_TELEMETRY_DISABLED` | `1` turns off dsh's anonymous telemetry |

Extra `dsh` CLI flags can be appended to the container command.

## Data

- `/data` (`DATA_DIR`) is `DSH_HOME`: the team and chats (`bot/`, `sessions/`),
  profiles, settings and the login cookie key (`.credentials.yaml`).
- `/workspace` (`WORKSPACE_DIR`) is the team workspace where the Bots work.

**Backup**: stop the container, then copy `DATA_DIR`. Restore by putting the
folder back and starting again.

## Updating

```sh
docker compose build   # or: docker build -f docker/Dockerfile -t ds-bot:local .
docker compose up -d
```

DSH itself lives in the image and updates on rebuild. The plugin lives in the
profile inside the data volume, so the entrypoint compares the installed ds-bot
version with the image's on every start and reinstalls it into the web profile
when they differ — a new image updates an existing volume automatically.
Rebuilds with the same ds-bot version skip the reinstall; to force a fresh
profile, stop the container and delete `DATA_DIR/profiles/web` (not the whole
data dir). `DSH_VERSION` in `.env` pins the dsh release: `0.2.1-alpha.1` (what
the ds-bot README verifies against) or `0.2.1-alpha.2` and newer — alpha.2
passed the Docker smoke test here.

## Importing an existing team

To move a team from a dsh you already run: stop this container, then copy
`bot/`, `sessions/` and `storages/` from the old `DSH_HOME` (`~/.dsh`) into
`DATA_DIR` — but not `profiles/`, which the image seeds itself. The ds-bot
README's "Move to another computer" caveat applies: workspace paths are stored
as absolute paths, so this is safest between two Linux deployments (the
container's workspace is always `/workspace`).

## Limits

- No Bot browser / `read_browser` tool: those exist in dsh Desktop only.
- Over plain http, API keys and secret values you type cross the network in
  clear text — use HTTPS off-box (see [Network](#network)).
- Full access is the only permission mode: a Bot can change everything the
  container can see.
