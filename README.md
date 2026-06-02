# OCD: OpenCode Contained in Docker

OCD runs [OpenCode](https://opencode.ai/) inside a Docker container so OpenCode can work on the project you choose without getting broad access to the rest of your machine.

The normal workflow is:

```bash
cd /path/to/your/project
ocd
```

OCD mounts your current working directory into the container and starts OpenCode there. OpenCode can read and write that project folder, plus the OpenCode state directories you choose to mount.

This is not meant to be an impenetrable security sandbox. It is meant to make local access explicit and controlled: OpenCode gets your current project folder, not every folder on your computer.

## Quick Start

Pull the official image:

```bash
docker pull jayk/ocd:latest
```

Put `ocd.sh` somewhere on your `PATH`. The easiest option is to symlink it as `ocd`:

```bash
ln -s /path/to/ocd.sh ~/.local/bin/ocd
```

Then run it from a project folder:

```bash
cd /path/to/your/project
ocd
```

That starts OpenCode in the container with your current directory mounted at the same absolute path inside the container.

## Web Mode

To start OpenCode web mode:

```bash
cd /path/to/your/project
ocd web
```

OCD publishes the OpenCode web port on `127.0.0.1:4096`. It also adds `--hostname 0.0.0.0` automatically unless you pass your own `--hostname`, because the OpenCode server needs to listen inside the container for Docker port publishing to work.

If `OPENCODE_SERVER_PASSWORD` is set, OCD uses it. Otherwise, OCD generates a password and prints it before starting the container.

## What OCD Mounts

OCD always mounts your current working directory:

```text
host current directory -> same absolute path in the container
```

By default, OCD also mounts your existing OpenCode state so your settings, sessions, agents, and skills continue to work:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/opencode      -> /opt/ocd_dev/.config/opencode
${XDG_DATA_HOME:-$HOME/.local/share}/opencode   -> /opt/ocd_dev/.local/share/opencode
$HOME/.agents                                   -> /opt/ocd_dev/.agents
```

If you want OpenCode-in-Docker to use separate state, set `HOST_OPENCODE_DIR`:

```bash
export HOST_OPENCODE_DIR="$HOME/.ocd-opencode"
ocd
```

That maps:

```text
$HOST_OPENCODE_DIR/config -> OpenCode config
$HOST_OPENCODE_DIR/share  -> OpenCode data
$HOST_OPENCODE_DIR/agents -> agents and skills
```

## Shell Mode

To open a shell inside the same container environment instead of starting OpenCode:

```bash
ocd --bash
```

## Platform

OCD is intended for Linux.

It may be possible to run it on macOS with Docker Desktop, but the image and wrapper are built for Linux assumptions. If there is interest in a macOS-compatible version, contact the project maintainer.

## Advanced Options

### Use a Different Image

The official image is:

```text
jayk/ocd:latest
```

To use your own image:

```bash
export OPENCODE_DOCKER_IMAGE="yourname/ocd:latest"
ocd
```

You can build one from this repo:

```bash
docker build -t yourname/ocd:latest .
```

Modify the `Dockerfile` if you want OpenCode to have access to additional tools.

### Included Tools

The image includes OpenCode plus common command-line tools useful during coding sessions, including:

- Node.js 22 and npm
- Python 3
- PHP CLI
- git
- bash
- curl
- vim and nano
- ripgrep
- fd-find, usually available as `fdfind` on Debian
- tree
- jq
- make
- zip and unzip
- xz-utils
- diffutils, including standard tools such as `diff`
- common shell utilities available in Debian, including tools such as `sed` and `awk`
- dtl-js - Data transformation tools for JSON, CSV, and yaml, among others
- openssh-client

If your projects need more tools, create your own image by editing the `Dockerfile`, building it, and setting `OPENCODE_DOCKER_IMAGE`.

### Use Separate OpenCode State

For a single separate OpenCode directory:

```bash
export HOST_OPENCODE_DIR="$HOME/.ocd-opencode"
ocd
```

For explicit control over each location:

```bash
export OPENCODE_CONFIG_DIR="$HOME/.config/opencode-ocd"
export XDG_DATA_HOME="$HOME/.local/share-ocd"
export OPENCODE_AGENTS_DIR="$HOME/.agents-ocd"
ocd
```

Precedence is:

1. Explicit overrides: `OPENCODE_CONFIG_DIR`, `XDG_DATA_HOME`, `OPENCODE_AGENTS_DIR`
2. Consolidated override: `HOST_OPENCODE_DIR`
3. Native OpenCode locations under your home directory

### Add More Host Mounts

If you need additional host paths available in the container, set `OPENCODE_MOUNTS` to a colon-delimited list of absolute paths:

```bash
export OPENCODE_MOUNTS="/tmp/shared:/var/run/docker.sock"
ocd
```

Each listed path is mounted read/write at the same absolute path inside the container.

Only add mounts you actually want OpenCode to access.

### Auth Port

When the first argument starts with `auth`, OCD publishes port `1455` on `127.0.0.1`:

```bash
ocd auth
```

## Container Details

OCD runs the container with:

- user `1000:1000`
- `HOME=/opt/ocd_dev`
- dropped Linux capabilities via `--cap-drop ALL`
- `no-new-privileges:true`
- process limit `--pids-limit 512`
- temporary container removal via `--rm`

The container name is based on the current project folder and shell process ID.

## Project Files

- `Dockerfile` builds the OpenCode container image.
- `ocd.sh` is the host-side wrapper you run as `ocd`.
- `opencode-entrypoint.sh` starts OpenCode or a shell inside the container.
