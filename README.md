# ocd (OpenCode in Docker)

Run OpenCode inside a locked-down Docker container while mounting your current dev folder and your OpenCode state from the host.

## Quick start

1. Build the image (from this repo):

```bash
docker build -t myuser/ocd:latest .
```

2. Put `ocd.sh` on your PATH (or symlink it as `ocd`).

3. From any project folder you want to work in:

```bash
ocd
```

That mounts your current directory into the container at the same path and runs `opencode` there.

## How it works

- `Dockerfile` builds the image and installs OpenCode plus common CLI tools.
- `opencode-entrypoint.sh` is the container entrypoint.
- `ocd.sh` is the host wrapper you run instead of `opencode`.

`ocd.sh`:

- Uses your current directory as the project root.
- Mounts your project into the container at the same absolute path.
- Mounts your OpenCode config/data/agents from the host so sessions and settings persist.
- Runs the container with reduced privileges.

## Host state mounting

By default, with no environment variables set, `ocd` mounts the standard OpenCode locations from your host:

- Config: `${XDG_CONFIG_HOME:-$HOME/.config}/opencode`
- Data: `${XDG_DATA_HOME:-$HOME/.local/share}/opencode`
- Agents: `$HOME/.agents`

This preserves your existing OpenCode config and session history.

## Consolidated OpenCode directory

If you want all OpenCode state in a single folder on the host, set `HOST_OPENCODE_DIR`:

```bash
export HOST_OPENCODE_DIR="$HOME/.opencode"
ocd
```

This maps:

- Config: `${HOST_OPENCODE_DIR}/config`
- Data: `${HOST_OPENCODE_DIR}/share`
- Agents: `${HOST_OPENCODE_DIR}/agents`

## Explicit host overrides

You can control each mounted location explicitly. These take precedence over `HOST_OPENCODE_DIR`.

- `OPENCODE_CONFIG_DIR` (exact config dir)
- `XDG_DATA_HOME` (data dir base; `ocd` appends `/opencode`)
- `OPENCODE_AGENTS_DIR` (exact agents dir)

Example:

```bash
export OPENCODE_CONFIG_DIR="$HOME/.config/opencode-custom"
export XDG_DATA_HOME="$HOME/.local/share-custom"
export OPENCODE_AGENTS_DIR="$HOME/.agents-custom"
ocd
```

## Additional bind mounts

If you need extra host paths available in the container, set `OPENCODE_MOUNTS` to a colon-delimited list of absolute paths:

```bash
export OPENCODE_MOUNTS="/var/run/docker.sock:/tmp/shared"
ocd
```

Each listed path is mounted to the same absolute path inside the container (for example, `/tmp/shared` on host becomes `/tmp/shared` in container).

## Shell access inside the container

To start a shell instead of OpenCode:

```bash
ocd --bash
```

## Notes

- The container runs as UID/GID 1000 and sets `HOME=/opt/dev` inside the container.
- Port `1455` is bound to `127.0.0.1` only when the first argument starts with `auth`.
- Port `4096` is bound to `127.0.0.1` only when the first argument is `web` or `serve`.
- The default image name is `jayk/ocd:latest`.
- Override the image with `OPENCODE_DOCKER_IMAGE` if you built your own.
- `ocd` uses `OPENCODE_SERVER_PASSWORD` if set; otherwise it generates a 3-word password and pauses so you can copy it.
