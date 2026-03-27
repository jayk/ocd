#!/usr/bin/env bash

OCD_IMAGE="${OPENCODE_DOCKER_IMAGE:-jayk/ocd:latest}"
# ------------------------------------------------------------
# Resolve project mount
# ------------------------------------------------------------
HOST_PROJECT_DIR="$(pwd -P)"
PROJECT_NAME="$(basename "${HOST_PROJECT_DIR}")"
# CTR_PROJECT_DIR="/opt/ocd_dev/dev/${PROJECT_NAME}"

# ------------------------------------------------------------
# Server password
# ------------------------------------------------------------
OPENCODE_SERVER_PASSWORD="${OPENCODE_SERVER_PASSWORD:-}"
case "${1:-}" in
    web|serve)
        if [[ -z "${OPENCODE_SERVER_PASSWORD}" ]]; then
            WORD_LIST="/usr/share/dict/words"
            if [[ -f "${WORD_LIST}" ]]; then
                OPENCODE_SERVER_PASSWORD="$(shuf -n 3 "${WORD_LIST}" | tr -d "'" | tr '\n' '-' | sed 's/-$//')"
            else
                OPENCODE_SERVER_PASSWORD="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 10)"
            fi
            echo "Securing your opencode service. Password is: ${OPENCODE_SERVER_PASSWORD}"
            # read -r -p "Press Enter to continue..." _
        fi
        ;;
esac
set -euo pipefail

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
CTR_CONFIG_DIR="/opt/ocd_dev/.config/opencode"
CTR_DATA_DIR="/opt/ocd_dev/.local/share/opencode"
CTR_AGENTS_DIR="/opt/ocd_dev/.agents"

# ------------------------------------------------------------
# Port mappings (conditional)
# ------------------------------------------------------------
PORT_ARGS=()
if [[ "${2:-}" == auth* ]]; then
    PORT_ARGS+=("-p" "127.0.0.1:1455:1455")
fi

case "${2:-}" in
    web|serve)
        PORT_ARGS+=("-p" "127.0.0.1:4096:4096")
        ;;
esac

if [ ! -z "${OPENCODE_EDITOR:-}" ]; then
    OC_EDITOR="${OPENCODE_EDITOR:-}"
elif [ ! -z "${EDITOR}" ]; then
   OC_EDITOR="${EDITOR}"
else
   OC_EDITOR="nano"
fi

# ------------------------------------------------------------
# Optional extra mounts (host path -> same container path)
# ------------------------------------------------------------
EXTRA_MOUNT_ARGS=()
if [[ -n "${OPENCODE_MOUNTS:-}" ]]; then
    IFS=':' read -r -a MOUNT_PATHS <<< "${OPENCODE_MOUNTS}"
    for MOUNT_PATH in "${MOUNT_PATHS[@]}"; do
        [[ -z "${MOUNT_PATH}" ]] && continue
        EXTRA_MOUNT_ARGS+=("-v" "${MOUNT_PATH}:${MOUNT_PATH}:rw")
    done
fi

# ------------------------------------------------------------
# Run container
# ------------------------------------------------------------
docker run --rm -it \
    --name "oc-${PROJECT_NAME}-$$" \
    --user 1000:1000 \
    --workdir "${HOST_PROJECT_DIR}" \
    --env "HOME=/opt/ocd_dev" \
    --env "TERM=${TERM:-xterm-256color}" \
    --env "XDG_CONFIG_HOME=/opt/ocd_dev/.config" \
    --env "XDG_DATA_HOME=/opt/ocd_dev/.local/share" \
    --env "OPENCODE_CONFIG_DIR=${CTR_CONFIG_DIR}" \
    --env "OPENCODE_SERVER_PASSWORD=${OPENCODE_SERVER_PASSWORD}" \
    --env "EDITOR=${OC_EDITOR}" \
    "${PORT_ARGS[@]}" \
    -v "${HOST_PROJECT_DIR}:${HOST_PROJECT_DIR}:rw" \
    -v "${FINAL_CONFIG_DIR}:${CTR_CONFIG_DIR}:rw" \
    -v "${FINAL_DATA_DIR}:${CTR_DATA_DIR}:rw" \
    -v "${FINAL_AGENTS_DIR}:${CTR_AGENTS_DIR}:rw" \
    "${EXTRA_MOUNT_ARGS[@]}" \
    --security-opt no-new-privileges:true \
    --cap-drop ALL \
    --pids-limit 512 \
    ${OCD_IMAGE} \
    "$@"
