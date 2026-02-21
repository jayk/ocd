#!/usr/bin/env bash
set -euo pipefail

OCD_IMAGE="jayk/ocd:latest"
# ------------------------------------------------------------
# Resolve project mount
# ------------------------------------------------------------
HOST_PROJECT_DIR="$(pwd -P)"
PROJECT_NAME="$(basename "${HOST_PROJECT_DIR}")"
# CTR_PROJECT_DIR="/opt/dev/dev/${PROJECT_NAME}"

# ------------------------------------------------------------
# Native OpenCode defaults (host-side)
# ------------------------------------------------------------
HOST_HOME="${HOME}"

NATIVE_CONFIG_DIR="${XDG_CONFIG_HOME:-${HOST_HOME}/.config}/opencode"
NATIVE_DATA_DIR="${XDG_DATA_HOME:-${HOST_HOME}/.local/share}/opencode"
NATIVE_AGENTS_DIR="${HOST_HOME}/.agents"

# ------------------------------------------------------------
# Consolidated override (Tier 2)
# ------------------------------------------------------------
HOST_OPENCODE_DIR="${HOST_OPENCODE_DIR:-}"

if [[ -n "${HOST_OPENCODE_DIR}" ]]; then
    CONSOLIDATED_CONFIG_DIR="${HOST_OPENCODE_DIR}/config"
    CONSOLIDATED_DATA_DIR="${HOST_OPENCODE_DIR}/share"
    CONSOLIDATED_AGENTS_DIR="${HOST_OPENCODE_DIR}/agents"
fi

# ------------------------------------------------------------
# Tier 1 explicit overrides (host-side)
# ------------------------------------------------------------
HOST_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-}"
HOST_DATA_DIR="${XDG_DATA_HOME:-}"
HOST_AGENTS_DIR="${OPENCODE_AGENTS_DIR:-}"

# ------------------------------------------------------------
# Resolve final host paths (precedence: Tier 1 → Tier 2 → native)
# ------------------------------------------------------------
FINAL_CONFIG_DIR="$(
    if [[ -n "${HOST_CONFIG_DIR}" ]]; then
        echo "${HOST_CONFIG_DIR}"
    elif [[ -n "${HOST_OPENCODE_DIR}" ]]; then
        echo "${CONSOLIDATED_CONFIG_DIR}"
    else
        echo "${NATIVE_CONFIG_DIR}"
    fi
)"

FINAL_DATA_DIR="$(
    if [[ -n "${HOST_DATA_DIR}" ]]; then
        echo "${HOST_DATA_DIR}/opencode"
    elif [[ -n "${HOST_OPENCODE_DIR}" ]]; then
        echo "${CONSOLIDATED_DATA_DIR}"
    else
        echo "${NATIVE_DATA_DIR}"
    fi
)"

FINAL_AGENTS_DIR="$(
    if [[ -n "${HOST_AGENTS_DIR}" ]]; then
        echo "${HOST_AGENTS_DIR}"
    elif [[ -n "${HOST_OPENCODE_DIR}" ]]; then
        echo "${CONSOLIDATED_AGENTS_DIR}"
    else
        echo "${NATIVE_AGENTS_DIR}"
    fi
)"

# ------------------------------------------------------------
# Ensure host directories exist
# ------------------------------------------------------------
mkdir -p \
    "${FINAL_CONFIG_DIR}" \
    "${FINAL_DATA_DIR}" \
    "${FINAL_AGENTS_DIR}"

# ------------------------------------------------------------
# Container canonical paths
# ------------------------------------------------------------
CTR_CONFIG_DIR="/opt/dev/.config/opencode"
CTR_DATA_DIR="/opt/dev/.local/share/opencode"
CTR_AGENTS_DIR="/opt/dev/.agents"

# ------------------------------------------------------------
# Run container
# ------------------------------------------------------------
docker run --rm -it \
    --name "oc-${PROJECT_NAME}-$$" \
    --user 1000:1000 \
    --workdir "${HOST_PROJECT_DIR}" \
    --env "HOME=/opt/dev" \
    --env "TERM=${TERM:-xterm-256color}" \
    --env "XDG_CONFIG_HOME=/opt/dev/.config" \
    --env "XDG_DATA_HOME=/opt/dev/.local/share" \
    --env "OPENCODE_CONFIG_DIR=${CTR_CONFIG_DIR}" \
    -v "${HOST_PROJECT_DIR}:${HOST_PROJECT_DIR}:rw" \
    -v "${FINAL_CONFIG_DIR}:${CTR_CONFIG_DIR}:rw" \
    -v "${FINAL_DATA_DIR}:${CTR_DATA_DIR}:rw" \
    -v "${FINAL_AGENTS_DIR}:${CTR_AGENTS_DIR}:rw" \
    --security-opt no-new-privileges:true \
    --cap-drop ALL \
    --pids-limit 512 \
    ${OCD_IMAGE} \
    "$@"
